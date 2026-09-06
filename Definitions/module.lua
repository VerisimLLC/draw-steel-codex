---@meta

--- Provides the Lua interface for managing modules, including querying, publishing, installing, and inspecting module content and dependencies.
--- @class module
--- @field savedAuthorid nil|string The saved author ID for the current user, or nil if no author ID has been set.
module = {}

--- Absorbs all currently imported modules into the game. Requires admin privileges.
function module.AdminAbsorbModules() end

--- Ensures module statistics are loaded, then invokes the callback function when ready.
--- @param fn function Callback invoked when module stats have been loaded.
function module.PrepareModuleStats(fn) end

--- Queries the module index with the given options. Supports filtering by 'purchased', 'installed', 'published', or 'patreon' index types. Calls options.success with a ModuleIndexLua on success or options.failure on error.
--- @param options table Options table with 'index' (string), 'success' (function(ModuleIndexLua)), and 'failure' (function(string)) fields.
function module.QueryModuleIndex(options) end

--- Creates a ModuleDependencySearcher that analyzes the current game to find dependency relationships among the given set of GUIDs.
--- @param dynGuidsAll table A table whose keys are GUID strings to include in the dependency search.
--- @return ModuleDependencySearcher
function module.CreateDependencySearcher(dynGuidsAll) end

--- Creates a new empty module owned by the current user.
--- @return ModuleLua
function module.CreateModule() end

--- Gets a module by its full ID. Returns nil if the module is not found or the ID is empty.
--- @param fullid string The full module ID.
--- @return nil|ModuleLua
function module.GetModule(fullid) end

--- Gets a list of module IDs granted to the current user by a Patreon membership of the publishing creator organization. Empty if no Patreon account is linked or no supported organization includes any modules.
--- @return string[]
function module.GetOurPatreonModules() end

--- Gets a list of module IDs that the current user has purchased from the store. Modules granted by a Patreon membership are not included -- see GetOurPatreonModules.
--- @return string[]
function module.GetOurPurchasedModules() end

--- Gets a list of module IDs that the current user has published, including modules published by organizations the user belongs to.
--- @return string[]
function module.GetOurPublishedModules() end

--- Gets the (cached) list of creator organizations the current user belongs to. Each entry has id, displayName, role ('owner' or 'member'), members (list of {userid, displayName, owner}), modules (list of module ids), and the optional branding fields logo (image id) and url (website). Use RefreshOurOrganizations to re-download the list.
--- @return table[]
function module.GetOurOrganizations() end

--- Looks up one creator organization by id and calls options.success with {id, displayName, logo, url, modules, patreonModules, patreonCampaign}, or options.failure with an error message. logo (an image id usable as a bgimage) and url (the organization's website) are optional branding set by the owner. patreonCampaign is {name, url} for the org's linked Patreon campaign, or nil if none. Unlike GetOurOrganizations this works for ANY organization, not just ones the user belongs to -- ModuleAuthor records are publicly readable. Used to show a patron which modules their Patreon membership of someone else's organization includes, and to offer 'Become a patron' to someone who has not pledged.
--- @param options table Options table with 'orgid' (string), 'success' (function(table)), and 'failure' (function(string)) fields.
function module.GetOrganizationInfo(options) end

--- Re-downloads the list of creator organizations the current user belongs to, then calls options.success with the same list GetOurOrganizations returns.
--- @param options table Options table with 'success' (function(table[])) field.
function module.RefreshOurOrganizations(options) end

--- Creates a new creator organization owned by the current user. A user may only create one organization. Calls options.success on success or options.failure with an error message.
--- @param options table Options table with 'orgid' (string), 'success' (function), and 'failure' (function(string)) fields.
function module.CreateOrganization(options) end

--- Updates the branding of an organization the current user owns: its display name (shown as the author of its modules), logo image, and website URL. options.displayName is required. options.logo is an image id already uploaded to cloud storage (load it with assets:LoadImageFileLocallyResized and call Upload on the result first), or an empty string to remove the logo; omit it to leave the logo unchanged. options.url is an http(s) URL, or an empty string to remove it; omit it to leave it unchanged. Calls options.success on success or options.failure with an error message.
--- @param options table Options table with 'orgid' (string), 'displayName' (string), 'logo' (nil|string), 'url' (nil|string), 'success' (function), and 'failure' (function(string)) fields.
function module.UpdateOrganizationBranding(options) end

--- Converts the current user's personal creator id into an organization. All modules already published under the id are adopted by the organization, and the personal author id is cleared from the account. Calls options.success on success or options.failure with an error message.
--- @param options table Options table with 'success' (function) and 'failure' (function(string)) fields.
function module.ConvertAuthorIdToOrganization(options) end

--- Creates a one-use invite code for an organization the current user owns. Calls options.success with the code string to give to the invitee, or options.failure with an error message.
--- @param options table Options table with 'orgid' (string), 'success' (function(string)), and 'failure' (function(string)) fields.
function module.CreateOrgInvite(options) end

--- Gets the outstanding invite codes for an organization the current user owns. Calls options.success with a list of {code, inviteCode, created} entries, or options.failure with an error message.
--- @param options table Options table with 'orgid' (string), 'success' (function(table[])), and 'failure' (function(string)) fields.
function module.GetOrgInvites(options) end

--- Revokes an outstanding invite code for an organization the current user owns. Calls options.success on success.
--- @param options table Options table with 'orgid' (string), 'code' (string), and 'success' (function) fields.
function module.RevokeOrgInvite(options) end

--- Removes a member from an organization the current user owns. Calls options.success on success or options.failure with an error message.
--- @param options table Options table with 'orgid' (string), 'userid' (string), 'success' (function), and 'failure' (function(string)) fields.
function module.RemoveOrgMember(options) end

--- Transfers ownership of an organization the current user owns to another member. Calls options.success on success or options.failure with an error message.
--- @param options table Options table with 'orgid' (string), 'userid' (string), 'success' (function), and 'failure' (function(string)) fields.
function module.TransferOrgOwnership(options) end

--- Deletes an organization the current user owns. The organization id remains reserved (tombstoned) so it can never be claimed by someone else; modules published by the organization remain installed for users who have them. Calls options.success on success or options.failure with an error message.
--- @param options table Options table with 'orgid' (string), 'success' (function), and 'failure' (function(string)) fields.
function module.DeleteOrganization(options) end

--- Leaves an organization the current user is a member (but not the owner) of. Calls options.success on success or options.failure with an error message.
--- @param options table Options table with 'orgid' (string), 'success' (function), and 'failure' (function(string)) fields.
function module.LeaveOrganization(options) end

--- Gets a list of modules that have been published from the current game, each with id, mtime, and properties fields.
--- @return table[]
function module.GetModulesPublishedFromThisGame() end

--- Downloads module information from the server. Calls options.success with a ModuleLua on success or options.failure with an error message on failure.
--- @param options table Options table with 'moduleid' (string), 'success' (function(ModuleLua)), and 'failure' (function(string)) fields.
function module.DownloadModuleInfo(options) end

--- Downloads a published module's content snapshot WITHOUT installing it into the current game. Calls options.success with {moduleid, version, characters} where characters maps the module's character ids to character tokens (browse their name/properties/appearance; they are not in any game). The snapshot is cached permanently on disk, so repeat calls are local. Calls options.failure with an error message on failure.
--- @param options table Options table with 'moduleid' (string), 'success' (function(table)), and 'failure' (function(string)) fields.
function module.DownloadModuleSnapshot(options) end

--- Calculates the estimated download size in kilobytes for the given set of GUIDs, including assets, modules, and object tables.
--- @param dynGuids table A table whose keys are GUID strings to calculate size for.
--- @return number
function module.CalculateDownloadSizeInKBytes(dynGuids) end

--- Gets all modules that could be listed as dependencies when publishing the given module. Returns a table mapping module ID to ModuleLua, excluding premium modules and the module itself.
--- @param dynModuleid string The module ID being published.
--- @return table<string, ModuleLua>
function module.GetEligibleDependentModules(dynModuleid) end

--- Gets all currently loaded modules as a list of ModuleLua objects.
--- @return ModuleLua[]
function module.GetLoadedModules() end

--- Gets all currently disabled modules as a list of ModuleLua objects.
--- @return ModuleLua[]
function module.GetDisabledModules() end

--- Traces all module dependencies for the current game and invokes the callback with a list of ModuleDependency objects in dependency order.
--- @param callback function Callback invoked with a list of ModuleDependency objects.
function module.GetModuleDependencies(callback) end

--- Collects all GUIDs loaded by the given list of modules. Returns a table mapping each GUID to true. Accepts 'core' and 'currentgame' as special module names.
--- @param modulesList table A list of module ID strings (or 'core'/'currentgame').
--- @param options nil|table Optional table with 'includeAllTouches' (boolean) to include all touched GUIDs.
--- @return table<string, boolean>
function module.GuidsLoaded(modulesList, options) end

--- Gets all modules that have modified a monster entry, returning a list of tables with moduleid, ctime, and mtime fields.
--- @param guid string The GUID of the monster entry.
--- @return table[]
function module.GetMonsterEntryChanges(guid) end

--- Gets all modules that have modified a bestiary folder, returning a list of tables with moduleid, ctime, and mtime fields.
--- @param guid string The GUID of the bestiary folder.
--- @return table[]
function module.GetMonsterFolderChanges(guid) end

--- Gets all modules that have modified an object in the given table, returning a list of tables with moduleid, ctime, and mtime fields.
--- @param tableName string The name of the object table.
--- @param guid string The GUID of the object.
--- @return table[]
function module.GetObjectTableChanges(tableName, guid) end

--- Checks whether novel content exists for the given content type and optional key. Returns true/false if no key is given, or the content value if a key is provided.
--- @param contentType string The type of novel content to check.
--- @param key nil|string Optional specific key within the content type.
--- @return boolean|table
function module.HasNovelContent(contentType, key) end

--- Gets the novel content table for the given content type, or nil if none exists.
--- @param contentType string The type of novel content to retrieve.
--- @return nil|table
function module.GetNovelContent(contentType) end

--- Removes a specific entry from the novel content for the given content type. Cleans up the content type entirely if it becomes empty.
--- @param contentType string The type of novel content.
--- @param id string|number The key to remove from the content table.
function module.RemoveNovelContent(contentType, id) end

--- Synchronizes module snapshot caches from the server.
function module.SyncModuleSnapshots() end

--- Whether a map with the given ID is available for reinstallation from any module snapshot.
--- @param mapid? string
--- @return boolean
function module.IsMapAvailableInModule(mapid) end

--- Reinstalls a map from its module snapshot. Invokes the callback with a boolean indicating success or failure.
--- @param mapid string The ID of the map to reinstall.
--- @param callback function Callback invoked with a boolean indicating success.
function module.ReinstallMap(mapid, callback) end

--- Whether a character with the given ID is available for reinstallation from any module snapshot.
--- @param charid? string
--- @return boolean
function module.IsCharacterAvailableInModule(charid) end

--- Reinstalls a character from its module snapshot, resetting it to its state in the module. Invokes the callback with a boolean indicating success or failure.
--- @param charid string The ID of the character to reinstall.
--- @param callback function Callback invoked with a boolean indicating success.
function module.ReinstallCharacter(charid, callback) end
