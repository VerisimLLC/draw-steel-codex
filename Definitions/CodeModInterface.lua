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

--- Includes one of this mod's shared documents in combat checkpoints, so Revert Turn rolls it back with the rest of the board. Register only state the current turn can change and that should be undone with it (resources, combat logs). Ordinary game saves include every document whether registered or not.
--- @param id string The document id within this mod.
function CodeModInterface:RegisterDocumentForCheckpointBackups(id) end

--- Names this mod's document that holds the DM's broadcast mix levels (a 'broadcast' table of mix-group id -> level 0..1). On every game load the engine applies those levels before the game's sounds start, rather than playing at full volume until Lua pushes them. One document at a time; a later call replaces it.
--- @param id? string
function CodeModInterface:RegisterBroadcastMixDocument(id) end

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
