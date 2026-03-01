--- @class module Provides the Lua interface for managing modules, including querying, publishing, installing, and inspecting module content and dependencies.
--- @field savedAuthorid nil|string The saved author ID for the current user, or nil if no author ID has been set.
module = {}

--- AdminAbsorbModules: Absorbs all currently imported modules into the game. Requires admin privileges.
--- @return nil
function module.AdminAbsorbModules()
	-- dummy implementation for documentation purposes only
end

--- PrepareModuleStats: Ensures module statistics are loaded, then invokes the callback function when ready.
--- @param fn function Callback invoked when module stats have been loaded.
function module.PrepareModuleStats(fn)
	-- dummy implementation for documentation purposes only
end

--- QueryModuleIndex: Queries the module index with the given options. Supports filtering by 'purchased', 'installed', or 'published' index types. Calls options.success with a ModuleIndexLua on success or options.failure on error.
--- @param options table Options table with 'index' (string), 'success' (function(ModuleIndexLua)), and 'failure' (function(string)) fields.
function module.QueryModuleIndex(options)
	-- dummy implementation for documentation purposes only
end

--- CreateDependencySearcher: Creates a ModuleDependencySearcher that analyzes the current game to find dependency relationships among the given set of GUIDs.
--- @param dynGuidsAll table A table whose keys are GUID strings to include in the dependency search.
--- @return ModuleDependencySearcher
function module.CreateDependencySearcher(dynGuidsAll)
	-- dummy implementation for documentation purposes only
end

--- CreateModule: Creates a new empty module owned by the current user.
--- @return ModuleLua
function module.CreateModule()
	-- dummy implementation for documentation purposes only
end

--- GetModule: Gets a module by its full ID. Returns nil if the module is not found or the ID is empty.
--- @param fullid string The full module ID.
--- @return nil|ModuleLua
function module.GetModule(fullid)
	-- dummy implementation for documentation purposes only
end

--- GetOurPurchasedModules: Gets a list of module IDs that the current user has purchased.
--- @return string[]
function module.GetOurPurchasedModules()
	-- dummy implementation for documentation purposes only
end

--- GetOurPublishedModules: Gets a list of module IDs that the current user has published.
--- @return string[]
function module.GetOurPublishedModules()
	-- dummy implementation for documentation purposes only
end

--- GetModulesPublishedFromThisGame: Gets a list of modules that have been published from the current game, each with id, mtime, and properties fields.
--- @return table[]
function module.GetModulesPublishedFromThisGame()
	-- dummy implementation for documentation purposes only
end

--- DownloadModuleInfo: Downloads module information from the server. Calls options.success with a ModuleLua on success or options.failure with an error message on failure.
--- @param options table Options table with 'moduleid' (string), 'success' (function(ModuleLua)), and 'failure' (function(string)) fields.
function module.DownloadModuleInfo(options)
	-- dummy implementation for documentation purposes only
end

--- CalculateDownloadSizeInKBytes: Calculates the estimated download size in kilobytes for the given set of GUIDs, including assets, modules, and object tables.
--- @param dynGuids table A table whose keys are GUID strings to calculate size for.
--- @return number
function module.CalculateDownloadSizeInKBytes(dynGuids)
	-- dummy implementation for documentation purposes only
end

--- GetEligibleDependentModules: Gets all modules that could be listed as dependencies when publishing the given module. Returns a table mapping module ID to ModuleLua, excluding premium modules and the module itself.
--- @param dynModuleid string The module ID being published.
--- @return table<string, ModuleLua>
function module.GetEligibleDependentModules(dynModuleid)
	-- dummy implementation for documentation purposes only
end

--- GetLoadedModules: Gets all currently loaded modules as a list of ModuleLua objects.
--- @return ModuleLua[]
function module.GetLoadedModules()
	-- dummy implementation for documentation purposes only
end

--- GetDisabledModules: Gets all currently disabled modules as a list of ModuleLua objects.
--- @return ModuleLua[]
function module.GetDisabledModules()
	-- dummy implementation for documentation purposes only
end

--- GetModuleDependencies: Traces all module dependencies for the current game and invokes the callback with a list of ModuleDependency objects in dependency order.
--- @param callback function Callback invoked with a list of ModuleDependency objects.
function module.GetModuleDependencies(callback)
	-- dummy implementation for documentation purposes only
end

--- GuidsLoaded: Collects all GUIDs loaded by the given list of modules. Returns a table mapping each GUID to true. Accepts 'core' and 'currentgame' as special module names.
--- @param modulesList table A list of module ID strings (or 'core'/'currentgame').
--- @param options nil|table Optional table with 'includeAllTouches' (boolean) to include all touched GUIDs.
--- @return table<string, boolean>
function module.GuidsLoaded(modulesList, options)
	-- dummy implementation for documentation purposes only
end

--- GetMonsterEntryChanges: Gets all modules that have modified a monster entry, returning a list of tables with moduleid, ctime, and mtime fields.
--- @param guid string The GUID of the monster entry.
--- @return table[]
function module.GetMonsterEntryChanges(guid)
	-- dummy implementation for documentation purposes only
end

--- GetObjectTableChanges: Gets all modules that have modified an object in the given table, returning a list of tables with moduleid, ctime, and mtime fields.
--- @param tableName string The name of the object table.
--- @param guid string The GUID of the object.
--- @return table[]
function module.GetObjectTableChanges(tableName, guid)
	-- dummy implementation for documentation purposes only
end

--- HasNovelContent: Checks whether novel content exists for the given content type and optional key. Returns true/false if no key is given, or the content value if a key is provided.
--- @param contentType string The type of novel content to check.
--- @param key nil|string Optional specific key within the content type.
--- @return boolean|table
function module.HasNovelContent(contentType, key)
	-- dummy implementation for documentation purposes only
end

--- GetNovelContent: Gets the novel content table for the given content type, or nil if none exists.
--- @param contentType string The type of novel content to retrieve.
--- @return nil|table
function module.GetNovelContent(contentType)
	-- dummy implementation for documentation purposes only
end

--- RemoveNovelContent: Removes a specific entry from the novel content for the given content type. Cleans up the content type entirely if it becomes empty.
--- @param contentType string The type of novel content.
--- @param id string|number The key to remove from the content table.
function module.RemoveNovelContent(contentType, id)
	-- dummy implementation for documentation purposes only
end

--- SyncModuleSnapshots: Synchronizes module snapshot caches from the server.
--- @return nil
function module.SyncModuleSnapshots()
	-- dummy implementation for documentation purposes only
end

--- IsMapAvailableInModule: Whether a map with the given ID is available for reinstallation from any module snapshot.
--- @param mapid string
--- @return boolean
function module.IsMapAvailableInModule(mapid)
	-- dummy implementation for documentation purposes only
end

--- ReinstallMap: Reinstalls a map from its module snapshot. Invokes the callback with a boolean indicating success or failure.
--- @param mapid string The ID of the map to reinstall.
--- @param callback function Callback invoked with a boolean indicating success.
function module.ReinstallMap(mapid, callback)
	-- dummy implementation for documentation purposes only
end
