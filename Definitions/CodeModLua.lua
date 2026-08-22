--- @class CodeModLua 
--- @field isUsingGit boolean 
--- @field gitFolderPath nil|string The absolute path of this mod's folder in the git working copy, or nil if the mod is not git-mapped.
--- @field unmanagedGitFiles any 
--- @field filesMissingFromGit any 
--- @field dependencies any 
--- @field valid boolean 
--- @field canWrite boolean 
--- @field name string 
--- @field description string 
--- @field resources any 
--- @field isowner boolean 
--- @field canedit boolean 
--- @field files any 
--- @field patches any 
--- @field changelists any 
--- @field checkedout boolean 
--- @field isModified boolean 
--- @field filesThatMayRequireMerge nil|CodeModFileLua[] 
--- @field localChangeEvent any 
--- @field hasLocalChanges boolean 
CodeModLua = {}

--- ReplicateToGit
--- @return nil
function CodeModLua:ReplicateToGit()
	-- dummy implementation for documentation purposes only
end

--- ReplicateFileToGit
--- @param fname string
--- @return boolean
function CodeModLua:ReplicateFileToGit(fname)
	-- dummy implementation for documentation purposes only
end

--- AddResource
--- @param p any
--- @return nil
function CodeModLua:AddResource(p)
	-- dummy implementation for documentation purposes only
end

--- ReorderFiles
--- @param a number
--- @param b number
--- @return nil
function CodeModLua:ReorderFiles(a, b)
	-- dummy implementation for documentation purposes only
end

--- AddFile
--- @param fname any
--- @return nil
function CodeModLua:AddFile(fname)
	-- dummy implementation for documentation purposes only
end

--- Upload
--- @return nil
function CodeModLua:Upload()
	-- dummy implementation for documentation purposes only
end

--- RepairLocal
--- @return boolean
function CodeModLua:RepairLocal()
	-- dummy implementation for documentation purposes only
end

--- ImportLocal
--- @return nil
function CodeModLua:ImportLocal()
	-- dummy implementation for documentation purposes only
end

--- DeleteLocalFiles
--- @return nil
function CodeModLua:DeleteLocalFiles()
	-- dummy implementation for documentation purposes only
end

--- OpenFile
--- @param file any
--- @return boolean
function CodeModLua:OpenFile(file)
	-- dummy implementation for documentation purposes only
end

--- OpenFileMerge
--- @param file any
--- @return boolean
function CodeModLua:OpenFileMerge(file)
	-- dummy implementation for documentation purposes only
end

--- AcceptFileMerge
--- @param file any
--- @return nil
function CodeModLua:AcceptFileMerge(file)
	-- dummy implementation for documentation purposes only
end

--- AutoMergeFile
--- @param file any
--- @return boolean
function CodeModLua:AutoMergeFile(file)
	-- dummy implementation for documentation purposes only
end

--- GetFileMergeInfo
--- @param file any
--- @return any
function CodeModLua:GetFileMergeInfo(file)
	-- dummy implementation for documentation purposes only
end

--- SaveMerged
--- @param file any
--- @return boolean
function CodeModLua:SaveMerged(file)
	-- dummy implementation for documentation purposes only
end

--- OpenLocal
--- @return nil
function CodeModLua:OpenLocal()
	-- dummy implementation for documentation purposes only
end

--- CommitChanges
--- @param comment string
--- @param engineVersion string
--- @param oncomplete any
--- @return string
function CodeModLua:CommitChanges(comment, engineVersion, oncomplete)
	-- dummy implementation for documentation purposes only
end

--- SubmitPatch
--- @param comment string
--- @param engineVersion string
--- @return string
function CodeModLua:SubmitPatch(comment, engineVersion)
	-- dummy implementation for documentation purposes only
end

--- CheckOutPatch
--- @param patchid string
--- @param callback any
--- @return nil
function CodeModLua:CheckOutPatch(patchid, callback)
	-- dummy implementation for documentation purposes only
end
