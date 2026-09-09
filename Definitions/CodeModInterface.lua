---@meta

--- @class CodeModInterface
--- @field isowner boolean
--- @field canedit boolean
--- @field modid string
--- @field unloaded boolean
--- @field instanceGuid string
--- @field images table<string,string>
--- @field shared table
--- @field enterGameHandlers function[]
--- @field unloadHandlers function[]
CodeModInterface = {}

--- GetMod
--- @return any
function CodeModInterface:GetMod() end

--- RegisterDocumentForCheckpointBackups
--- @param id? string
function CodeModInterface:RegisterDocumentForCheckpointBackups(id) end

--- GetDocumentPath
--- @param id? string
--- @return any
function CodeModInterface:GetDocumentPath(id) end

--- Returns a snapshot of one of this mod's documents, creating it from the mod's default document (or an empty table) if it does not exist yet in the game.
--- @param id string The document id within this mod.
--- @return LuaCodeModDocumentSnapshot
function CodeModInterface:GetDocumentSnapshot(id) end

--- OpenDocumentDebugURL
--- @param docid? string
function CodeModInterface:OpenDocumentDebugURL(docid) end

--- SaveDefaultDocuments
--- @param callback? any
function CodeModInterface:SaveDefaultDocuments(callback) end

--- CallEnterGame
function CodeModInterface:CallEnterGame() end

--- GlobalStyle
--- @param t? any
function CodeModInterface:GlobalStyle(t) end

--- RecordEventHandlerInstance
--- @param eventName? string
--- @param guid? string
function CodeModInterface:RecordEventHandlerInstance(eventName, guid) end
