--- @class ModuleLua 
--- @field idvalid boolean 
--- @field fullid any 
--- @field authorid string 
--- @field moduleid string 
--- @field name string 
--- @field details string 
--- @field keywords any 
--- @field keywordsAsJoinedString any 
--- @field coverDocumentId string 
--- @field coverart any 
--- @field owned boolean 
--- @field premium boolean
--- @field hasAccessThroughPatreon boolean True if a Patreon membership grants this account access to this module: it is published under a creator organization we are entitled to, and that organization includes it with membership. A premium module is normally hidden on builds with no store; this is the second route past that, so patrons can see and install what they were granted.
--- @field published boolean
--- @field deleted boolean 
--- @field deprecated boolean True if an administrator has deprecated this module. A deprecated module is disabled in every game by default, but the user may explicitly enable it again with SetDisabled(false). Read-only: deprecation is set by an offline admin script.
--- @field deprecationOverridden boolean True if this module is deprecated but this game has explicitly enabled it anyway. Only meaningful when deprecated is true.
--- @field deprecationMessage string The message explaining why this module is deprecated. Only meaningful when deprecated is true, in which case it is never nil.
--- @field dmhubCanUse boolean 
--- @field publishingProperties any 
--- @field contentSummary any 
--- @field isdisabled boolean 
--- @field ourModule boolean 
--- @field org nil|string The organization id this module is published under, or nil for a personal module.
--- @field publishedFromThisGame any 
--- @field loadedVersion any 
--- @field installedVersion any 
--- @field latestVersion any 
--- @field installationBandwidthInKBytes any 
--- @field versions any 
--- @field cachedStats any 
--- @field vote number 
ModuleLua = {}

--- IsModuleIdValid
--- @param id string
--- @return boolean
function ModuleLua:IsModuleIdValid(id)
	-- dummy implementation for documentation purposes only
end

--- IsAuthorIdValid
--- @param id string
--- @return boolean
function ModuleLua:IsAuthorIdValid(id)
	-- dummy implementation for documentation purposes only
end

--- Upload
--- @param options any
--- @return nil
function ModuleLua:Upload(options)
	-- dummy implementation for documentation purposes only
end

--- Delete: Soft-deletes this module. Marks the module record deleted (so direct-id lookups and searches no longer find it), removes it from the public index and from the current user's published-module lists. Users who already installed the module keep access to the content they imported. Calls options.success on success or options.failure with an error message.
--- @param options table Options table with 'success' (function) and 'failure' (function(string)) fields.
function ModuleLua:Delete(options)
	-- dummy implementation for documentation purposes only
end

--- ReserveAuthorID
--- @param options any
--- @return nil
function ModuleLua:ReserveAuthorID(options)
	-- dummy implementation for documentation purposes only
end

--- CheckAuthorIDAvailable
--- @param callback any
--- @return nil
function ModuleLua:CheckAuthorIDAvailable(callback)
	-- dummy implementation for documentation purposes only
end

--- CheckModuleIDAvailable
--- @param options any
--- @return nil
function ModuleLua:CheckModuleIDAvailable(options)
	-- dummy implementation for documentation purposes only
end

--- UploadModuleVersion
--- @param options any
--- @return nil
function ModuleLua:UploadModuleVersion(options)
	-- dummy implementation for documentation purposes only
end

--- UploadModulePublishProperties
--- @param properties any
--- @return nil
function ModuleLua:UploadModulePublishProperties(properties)
	-- dummy implementation for documentation purposes only
end

--- Install
--- @param options any
--- @return nil
function ModuleLua:Install(options)
	-- dummy implementation for documentation purposes only
end

--- Uninstall
--- @param options any
--- @return nil
function ModuleLua:Uninstall(options)
	-- dummy implementation for documentation purposes only
end

--- SetDisabled
--- @param disabled boolean
--- @return nil
function ModuleLua:SetDisabled(disabled)
	-- dummy implementation for documentation purposes only
end

--- QueryStats
--- @param fn any
--- @return nil
function ModuleLua:QueryStats(fn)
	-- dummy implementation for documentation purposes only
end
