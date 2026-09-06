---@meta

--- @class CodeModFileLua
--- @field usingGit boolean
--- @field hasMerge boolean
--- @field valid boolean
--- @field hasLocalChanges boolean
--- @field localContents any
--- @field revisions any
--- @field numRevisions any
--- @field changeTimestamp any
--- @field name string
CodeModFileLua = {}

--- MatchesSearch
--- @param search? string
--- @param options? any
--- @return boolean
function CodeModFileLua:MatchesSearch(search, options) end

--- SyncLocally
--- @param revision? any
function CodeModFileLua:SyncLocally(revision) end

--- LaunchExternalDiffWithLocal
function CodeModFileLua:LaunchExternalDiffWithLocal() end
