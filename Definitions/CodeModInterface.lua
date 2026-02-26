--- A shared cloud document snapshot. Provides key-value storage that syncs
--- across all clients in a game session. Read from doc.data; to write, wrap
--- mutations in BeginChange/CompleteChange. Monitor changes in UI panels by
--- setting monitorGame = doc.path.
--- @class DocumentSnapshot
--- @field data table The document contents (read/write between BeginChange/CompleteChange)
--- @field path string The monitoring path -- assign to a panel's monitorGame to receive refreshGame events on change
local DocumentSnapshot = {}

--- Begin a mutation transaction. Must be called before modifying doc.data.
--- @return nil
function DocumentSnapshot:BeginChange()
	-- dummy implementation for documentation purposes only
end

--- Complete a mutation transaction and sync the changes to all clients.
--- @param description string A short description of the change (for undo/logging)
--- @param options? {undoable?: boolean} Optional settings, e.g. {undoable = false}
--- @return nil
function DocumentSnapshot:CompleteChange(description, options)
	-- dummy implementation for documentation purposes only
end


--- The mod interface returned by dmhub.GetModLoading(). Provides access to
--- module identity, document storage, and lifecycle state.
--- @class CodeModInterface
--- @field isowner boolean
--- @field canedit boolean
--- @field modid string
--- @field unloaded boolean
CodeModInterface = {}

--- GetMod
--- @return any
function CodeModInterface:GetMod()
	-- dummy implementation for documentation purposes only
end

--- Register a document so it is included in game-state checkpoint saves/backups.
--- @param id string The document ID to register
--- @return nil
function CodeModInterface:RegisterDocumentForCheckpointBackups(id)
	-- dummy implementation for documentation purposes only
end

--- Get the monitoring path string for a document (equivalent to GetDocumentSnapshot(id).path).
--- Useful when you only need the path for monitorGame and not the full snapshot.
--- @param id string The document ID
--- @return string path The monitoring path
function CodeModInterface:GetDocumentPath(id)
	-- dummy implementation for documentation purposes only
end

--- Get a snapshot of a shared cloud document. The returned object has a .data
--- table for reading and a .path string for monitoring. To write, call
--- doc:BeginChange(), modify doc.data, then call doc:CompleteChange(description).
--- @param docid string A unique string identifying the document
--- @return DocumentSnapshot snapshot The document snapshot
function CodeModInterface:GetDocumentSnapshot(docid)
	-- dummy implementation for documentation purposes only
end

--- Open a debug URL for inspecting a document in the browser.
--- @param docid string The document ID to inspect
--- @return nil
function CodeModInterface:OpenDocumentDebugURL(docid)
	-- dummy implementation for documentation purposes only
end

--- SaveDefaultDocuments
--- @param callback any
--- @return nil
function CodeModInterface:SaveDefaultDocuments(callback)
	-- dummy implementation for documentation purposes only
end

--- CallEnterGame
--- @return nil
function CodeModInterface:CallEnterGame()
	-- dummy implementation for documentation purposes only
end

--- GlobalStyle
--- @param t any
--- @return nil
function CodeModInterface:GlobalStyle(t)
	-- dummy implementation for documentation purposes only
end

--- RecordEventHandlerInstance
--- @param eventName string
--- @param guid string
--- @return nil
function CodeModInterface:RecordEventHandlerInstance(eventName, guid)
	-- dummy implementation for documentation purposes only
end
