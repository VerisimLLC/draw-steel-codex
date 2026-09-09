---@meta

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
--- @field modid string
CodeModLua = {}

--- ReplicateToGit
function CodeModLua:ReplicateToGit() end

--- ReplicateFileToGit
--- @param fname? string
--- @return boolean
function CodeModLua:ReplicateFileToGit(fname) end

--- AddResource
--- @param p? any
function CodeModLua:AddResource(p) end

--- ReorderFiles
--- @param a? number
--- @param b? number
function CodeModLua:ReorderFiles(a, b) end

--- AddFile
--- @param fname? any
function CodeModLua:AddFile(fname) end

--- Permanently removes a file and its entire revision history from the mod, deletes its local/git working copy from disk if present, records a changelist entry, and uploads the change. Returns true if the file was deleted.
--- @param file? any
--- @return boolean
function CodeModLua:DeleteFile(file) end

--- Upload
function CodeModLua:Upload() end

--- RepairLocal
--- @return boolean
function CodeModLua:RepairLocal() end

--- ImportLocal
function CodeModLua:ImportLocal() end

--- DeleteLocalFiles
function CodeModLua:DeleteLocalFiles() end

--- OpenFile
--- @param file? any
--- @return boolean
function CodeModLua:OpenFile(file) end

--- OpenFileMerge
--- @param file? any
--- @return boolean
function CodeModLua:OpenFileMerge(file) end

--- AcceptFileMerge
--- @param file? any
function CodeModLua:AcceptFileMerge(file) end

--- AutoMergeFile
--- @param file? any
--- @return boolean
function CodeModLua:AutoMergeFile(file) end

--- GetFileMergeInfo
--- @param file? any
--- @return any
function CodeModLua:GetFileMergeInfo(file) end

--- SaveMerged
--- @param file? any
--- @return boolean
function CodeModLua:SaveMerged(file) end

--- OpenLocal
function CodeModLua:OpenLocal() end

--- CommitChanges
--- @param comment? string
--- @param engineVersion? string
--- @param oncomplete? any
--- @return string
function CodeModLua:CommitChanges(comment, engineVersion, oncomplete) end

--- SubmitPatch
--- @param comment? string
--- @param engineVersion? string
--- @return string
function CodeModLua:SubmitPatch(comment, engineVersion) end

--- CheckOutPatch
--- @param patchid? string
--- @param callback? any
function CodeModLua:CheckOutPatch(patchid, callback) end
