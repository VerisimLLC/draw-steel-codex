--- @class import Provides an interface for importing game assets such as monsters, characters, and object tables from external sources.
--- @field importers table Returns a table of all registered importers keyed by their ID.
--- @field importedAssets table Table tracking imported asset IDs, mapping each asset ID to true on success or an error string on failure.
--- @field pendingUpload boolean True if an upload operation is currently in progress.
--- @field error nil|string The current error message from the import process, or nil if no error has occurred.
--- @field uploadCostKB number The estimated upload cost in kilobytes for all pending imports.
--- @field haveEnoughBandwidth boolean True if the account has enough upload bandwidth remaining to complete the pending imports.
import = {}

--- CreateImporter: Creates a new LuaImport instance.
--- @return LuaImport
function import.CreateImporter()
	-- dummy implementation for documentation purposes only
end

--- BookmarkLog: Returns a bookmark index into the current log, which can be used later with StoreLogFromBookmark.
--- @return number
function import:BookmarkLog()
	-- dummy implementation for documentation purposes only
end

--- IsReimport: Returns true if the asset was previously imported and is being reimported.
--- @param asset LuaImport|MonsterAssetLua|LuaCharacterToken The asset to check.
--- @return boolean
function import:IsReimport(asset)
	-- dummy implementation for documentation purposes only
end

--- GetAssetLog: Returns the import log stored on the given asset, or nil if none exists.
--- @param asset LuaImport|MonsterAssetLua|LuaCharacterToken The asset to retrieve the log from.
--- @return nil|table
function import:GetAssetLog(asset)
	-- dummy implementation for documentation purposes only
end

--- GetImage: Returns the portrait image ID for a character token asset, or nil if none is set.
--- @param asset LuaCharacterToken The character token asset.
--- @return nil|string
function import:GetImage(asset)
	-- dummy implementation for documentation purposes only
end

--- StoreLogFromBookmark: Stores log entries accumulated since the given bookmark onto the asset's metadata, then removes them from the main log.
--- @param bookmark integer The bookmark index returned by BookmarkLog.
--- @param asset LuaImport|MonsterAssetLua|LuaCharacterToken The asset to attach the log to.
function import:StoreLogFromBookmark(bookmark, asset)
	-- dummy implementation for documentation purposes only
end

--- GetLog: Returns a table containing all log entries recorded during this import session.
--- @return table
function import:GetLog()
	-- dummy implementation for documentation purposes only
end

--- CreateCharacter: Creates a new empty character for importing.
--- @return LuaCharacterToken
function import:CreateCharacter()
	-- dummy implementation for documentation purposes only
end

--- CreateMonster: Creates a new empty monster asset for importing.
--- @return MonsterAssetLua
function import:CreateMonster()
	-- dummy implementation for documentation purposes only
end

--- CreateMonsterFolder: Creates a new monster folder with the given description and registers it in the importer.
--- @return MonsterFolderLua
function import:CreateMonsterFolder(description)
	-- dummy implementation for documentation purposes only
end

--- GetExistingItem: Looks up an existing asset by table name and item name. Returns the matching asset or nil if not found.
--- @return nil|MonsterAssetLua|MonsterFolderLua|table
function import:GetExistingItem(tableName, itemName)
	-- dummy implementation for documentation purposes only
end

--- GetImports: Returns a table of all pending imports organized by type (monster, character, or object table name).
--- @return table
function import:GetImports()
	-- dummy implementation for documentation purposes only
end

--- Log: Appends a log entry to the import log.
--- @param text any The log entry to record.
function import:Log(text)
	-- dummy implementation for documentation purposes only
end

--- OnImportConfirmed: Registers a callback function to be executed when the current asset's import is confirmed and uploaded.
--- @param fn function The callback to invoke on confirmation.
function import:OnImportConfirmed(fn)
	-- dummy implementation for documentation purposes only
end

--- ImportMonsterFolder: Stages a monster folder asset for import. The folder will be uploaded when CompleteImportStep is called.
--- @param asset MonsterFolderLua The monster folder to import.
function import:ImportMonsterFolder(asset)
	-- dummy implementation for documentation purposes only
end

--- ImportMonster: Stages a monster asset for import. The monster will be uploaded when CompleteImportStep is called.
--- @param asset MonsterAssetLua The monster asset to import.
function import:ImportMonster(asset)
	-- dummy implementation for documentation purposes only
end

--- ImportCharacter: Stages a character asset for import and returns the assigned character ID.
--- @param asset LuaCharacterToken The character token to import.
function import:ImportCharacter(asset)
	-- dummy implementation for documentation purposes only
end

--- ImportAsset: Stages a generic table asset for import into the specified object table.
--- @param tableName string The name of the object table to import into.
--- @param asset table The asset data table to import.
function import:ImportAsset(tableName, asset)
	-- dummy implementation for documentation purposes only
end

--- SetImportRemoved: Marks or unmarks an asset ID as removed, preventing it from being uploaded during CompleteImportStep.
--- @param id string
--- @param remove boolean
--- @return nil
function import:SetImportRemoved(id, remove)
	-- dummy implementation for documentation purposes only
end

--- CompleteImportStep: Uploads the next batch of staged imports. Returns true if there are more imports to process, false when all imports are complete.
--- @return boolean
function import:CompleteImportStep()
	-- dummy implementation for documentation purposes only
end

--- Register: Registers an importer with the given options table. The options table should contain an 'id' field and handler functions.
--- @param options table The importer configuration table.
function import.Register(options)
	-- dummy implementation for documentation purposes only
end

--- GetCurrentImporter: Returns the currently active importer's options table, or nil if none is found.
--- @return nil|table
function import:GetCurrentImporter()
	-- dummy implementation for documentation purposes only
end

--- ImportPlainText: Imports plain text content by passing it to matching registered importers' text handlers.
--- @param text string
--- @return nil
function import:ImportPlainText(text)
	-- dummy implementation for documentation purposes only
end

--- ImportFromText: Parses the given text as JSON and imports it by passing the parsed data to matching registered importers.
--- @param text string
--- @return nil
function import:ImportFromText(text)
	-- dummy implementation for documentation purposes only
end

--- SetActiveImporter: Sets the active importer by ID, restricting subsequent import operations to that importer.
--- @param importerid nil|string The importer ID to activate, or nil to allow all importers.
function import:SetActiveImporter(importerid)
	-- dummy implementation for documentation purposes only
end

--- ImportFromJson: Imports a parsed JSON object by passing it to matching registered importers' JSON handlers.
--- @param obj table The parsed JSON data to import.
--- @param filename string The source filename for logging purposes.
function import:ImportFromJson(obj, filename)
	-- dummy implementation for documentation purposes only
end

--- ImportImageFromURL: Downloads an image from the given URL, optionally processes it, and saves it locally. Calls the success callback with the file path or the error callback on failure.
--- @param url string The URL to download the image from.
--- @param success function Callback receiving the local file path on success.
--- @param error function Callback receiving an error message string on failure.
--- @param options nil|table Optional settings such as 'removeBackground' with a hex color string.
function import:ImportImageFromURL(url, success, error, options)
	-- dummy implementation for documentation purposes only
end

--- ClearState: Resets all importer state, clearing pending imports, logs, errors, and dependent actions.
--- @return nil
function import:ClearState()
	-- dummy implementation for documentation purposes only
end
