--- Settings manager for downtime system configuration
--- Handles document-based storage of global downtime settings
--- @class DTSettings
--- @field mod table The Codex mod loading instance
--- @field documentName string The name of the document used for settings storage
DTSettings = RegisterGameType("DTSettings")

-- Module-level document monitor for persistence (timing-critical)
local mod = dmhub.GetModLoading()
local documentName = "DTSettings"

--- Creates a new settings manager instance
--- @return DTSettings instance The new settings manager instance
function DTSettings.CreateNew()
    return DTSettings.new{
        mod = mod,
        documentName = documentName,
    }
end

--- Initializes the settings document with default structure
--- WARNING!!! All data will be lost!
--- @return table doc The initialized document
function DTSettings:InitializeDocument()
    local doc = self.mod:GetDocumentSnapshot(self.documentName)
    doc:BeginChange()
    --The document carries no settings any more. What is left of it is the
    --timestamp, which every downtime panel monitors: touching it is how a
    --change made on one client repaints the others.
    doc.data = {
        modifiedAt = dmhub.serverTime,
    }
    doc:CompleteChange("Initialize downtime settings", {undoable = false})
    return doc
end

--- Touches the document to trigger network refresh
function DTSettings:TouchDoc()
    local doc = self:_safeDoc()
    if doc then
        doc:BeginChange()
        doc.data.modifiedAt = dmhub.serverTime
        doc:CompleteChange("touch timestamp", {undoable = false})
    end
end

--- Static method to touch the settings document without requiring callers to manage instances
--- Triggers network refresh by updating the modifiedAt timestamp
function DTSettings.Touch()
    local instance = DTSettings.CreateNew()
    instance:TouchDoc()
end


--- Initializes the settings document with default structure if it's not already set
--- @return table doc The document
function DTSettings:_ensureDocInitialized()
    local doc = self.mod:GetDocumentSnapshot(self.documentName)
    if DTSettings._validDoc(doc) then
        return doc
    end
    return self:InitializeDocument()
end

--- Return a document object that is guaranteed to be valid or nil
--- @return table|nil doc The doc if it's valid
function DTSettings:_safeDoc()
    local doc = self:_ensureDocInitialized()
    if DTSettings._validDoc(doc) then
        return doc
    end
    return nil
end

--- Determine whether the document has the valid / expected structure
--- @param doc table The document to validate
--- @return boolean isValid Whether the document has the expected structure
function DTSettings._validDoc(doc)
    return doc.data ~= nil and type(doc.data) == "table" and
           doc.data.modifiedAt ~= nil
end

--- Gets the path for document monitoring in UI
--- @return string path The document path for monitoring
function DTSettings.GetDocumentPath()
    return mod:GetDocumentSnapshot(documentName).path
end
