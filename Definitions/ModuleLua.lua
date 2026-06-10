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
--- @field published boolean 
--- @field deleted boolean 
--- @field dmhubCanUse boolean 
--- @field publishingProperties any 
--- @field contentSummary any 
--- @field isdisabled boolean 
--- @field ourModule boolean 
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
