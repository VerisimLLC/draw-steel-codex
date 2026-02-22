--- Project shares manager for downtime system configuration
--- Handles document-based storage of global downtime project shares
--- @class DTShares
--- @field mod table The Codex mod loading instance
--- @field documentName string The name of the document used for project shares storage
DTShares = RegisterGameType("DTShares")

-- Module-level document monitor for persistence (timing-critical)
local mod = dmhub.GetModLoading()
local documentName = "DTShares"

--- Creates a new project shares manager instance
--- @return DTShares instance The new project shares manager instance
function DTShares.CreateNew()
    return DTShares.new{
        mod = mod,
        documentName = documentName,
    }
end

--- Gets the path for document monitoring in UI
--- @return string path The document path for monitoring
function DTShares.GetDocumentPath()
    return mod:GetDocumentSnapshot(documentName).path
end

--- Initializes the project shares document with default structure
--- WARNING!!! All data will be lost!
--- @return table doc The initialized document
function DTShares:InitializeDocument()
    local doc = self.mod:GetDocumentSnapshot(self.documentName)
    doc:BeginChange()
    doc.data = {
        senders = {},
        recipients = {},
        modifiedAt = dmhub.serverTime,
    }
    doc:CompleteChange("Initialize downtime project shares", {undoable = false})
    return doc
end

--- Return the projects shared by a token or nil if none
--- @param tokenId string The token for which to get shares
--- @return table|nil projects The list of projects shared by the token
function DTShares:GetSharedBy(tokenId)
    if tokenId == nil or type(tokenId) ~= "string" or #tokenId == 0 then return nil end
    local doc = self:_safeDoc()
    if doc then
        return doc.data.senders[tokenId]
    end
    return nil
end

--- Return the list of projects shared with a token or nil if none
--- @param tokenId string The token for which to get the shares
--- @return table|nil projects The list of projects shared with the token
function DTShares:GetSharedWith(tokenId)
    if tokenId == nil or type(tokenId) ~= "string" or #tokenId == 0 then return nil end
    local doc = self:_safeDoc()
    if doc then
        return doc.data.recipients[tokenId]
    end
    return nil
end

--- Return the list of all shares
--- @return table|nil shares The list of all shares
function DTShares:GetShares()
    local doc = self:_safeDoc()
    if doc then
        return doc.data
    end
    return nil
end

--- Returns the list of token IDs with whom a specific project is shared
--- @param tokenId string The token ID of the character who shared the project
--- @param projectId string The unique identifier of the project
--- @return table recipients Array of token IDs with whom the project is shared (empty if none)
function DTShares:GetProjectSharedWith(tokenId, projectId)
    if not tokenId or type(tokenId) ~= "string" or #tokenId == 0 then return {} end
    if not projectId or type(projectId) ~= "string" or #projectId == 0 then return {} end

    local doc = self:_safeDoc()
    if not doc then return {} end

    local recipients = {}
    if doc.data.senders[tokenId] and doc.data.senders[tokenId][projectId] then
        for recipientId, _ in pairs(doc.data.senders[tokenId][projectId]) do
            recipients[#recipients + 1] = recipientId
        end
    end

    return recipients
end

--- Revokes a project share
--- @param sharedBy string VTT Token ID of the character who shared the project
--- @param sharedWith string VTT Token ID of the character who received the project
--- @param projectId string Unique identifier of the project being shared
function DTShares:Revoke(sharedBy, sharedWith, projectId)
    local doc = self:_safeDoc()
    if doc then
        local data = doc.data
        local hasChange = data.senders[sharedBy]
            and data.senders[sharedBy][projectId]
            and data.senders[sharedBy][projectId][sharedWith]
        if hasChange then
            doc:BeginChange()
            data.senders[sharedBy][projectId][sharedWith] = nil
            if next(data.senders[sharedBy][projectId]) == nil then
                data.senders[sharedBy][projectId] = nil
            end
            if next(data.senders[sharedBy]) == nil then
                data.senders[sharedBy] = nil
            end
            data.recipients[sharedWith][projectId] = nil
            if next(data.recipients[sharedWith]) == nil then
                data.recipients[sharedWith] = nil
            end
            doc:CompleteChange("Removed project share", {undoable = false})
        end
    end
end

--- Revokes all shares by and to a specific character
--- @param tokenId string VTT Token ID of the character to revoke shares from
function DTShares:RevokeAll(tokenId)
    local doc = self:_safeDoc()
    if doc then
        local data = doc.data
        local hasChange = data.senders[tokenId] ~= nil or data.recipients[tokenId] ~= nil
        if hasChange then
            doc:BeginChange()
            data.senders[tokenId] = nil
            data.recipients[tokenId] = nil
            doc:CompleteChange("Revoked all shares for a character", {undoable = false})
        end
    end
end

--- Shares a project with recipients or revokes all if empty array
--- @param sharedBy string VTT Token ID of the character sharing the project
--- @param projectId string Unique identifier of the project being shared
--- @param sharedWith table Array of VTT Token IDs to share with (empty array revokes all)
function DTShares:Share(sharedBy, projectId, sharedWith)
    if not sharedBy or type(sharedBy) ~= "string" or #sharedBy == 0 then return end
    if not projectId or type(projectId) ~= "string" or #projectId == 0 then return end
    if not sharedWith or type(sharedWith) ~= "table" then return end

    local doc = self:_safeDoc()
    if not doc then return end

    local data = doc.data

    -- Build set of new recipients for easy lookup
    local newRecipients = {}
    for _, recipientId in ipairs(sharedWith) do
        newRecipients[recipientId] = true
    end

    -- Get set of current recipients (or empty if none exist)
    local currentRecipients = {}
    if data.senders[sharedBy] and data.senders[sharedBy][projectId] then
        for recipientId, _ in pairs(data.senders[sharedBy][projectId]) do
            currentRecipients[recipientId] = true
        end
    end

    -- Determine what changed
    local toAdd = {}
    local toRemove = {}

    for recipientId, _ in pairs(newRecipients) do
        if not currentRecipients[recipientId] then
            toAdd[#toAdd + 1] = recipientId
        end
    end

    for recipientId, _ in pairs(currentRecipients) do
        if not newRecipients[recipientId] then
            toRemove[#toRemove + 1] = recipientId
        end
    end

    -- If nothing changed, bail out
    if #toAdd == 0 and #toRemove == 0 then return end

    -- Make changes in single transaction
    doc:BeginChange()

    -- Ensure sender structures exist if we're adding
    if #toAdd > 0 then
        if not data.senders[sharedBy] then
            data.senders[sharedBy] = {}
        end
        if not data.senders[sharedBy][projectId] then
            data.senders[sharedBy][projectId] = {}
        end
    end

    -- Add new recipients
    for _, recipientId in ipairs(toAdd) do
        data.senders[sharedBy][projectId][recipientId] = true

        if not data.recipients[recipientId] then
            data.recipients[recipientId] = {}
        end
        data.recipients[recipientId][projectId] = sharedBy
    end

    -- Remove old recipients
    for _, recipientId in ipairs(toRemove) do
        data.senders[sharedBy][projectId][recipientId] = nil

        if data.recipients[recipientId] then
            data.recipients[recipientId][projectId] = nil
            if next(data.recipients[recipientId]) == nil then
                data.recipients[recipientId] = nil
            end
        end
    end

    -- Clean up empty sender nodes
    if next(data.senders[sharedBy][projectId]) == nil then
        data.senders[sharedBy][projectId] = nil
    end
    if data.senders[sharedBy] and next(data.senders[sharedBy]) == nil then
        data.senders[sharedBy] = nil
    end

    doc:CompleteChange("Updated project shares", {undoable = false})
end

--- Static method to touch the settings document without requiring callers to manage instances
--- Triggers network refresh by updating the modifiedAt timestamp
function DTShares.Touch()
    DTShares.CreateNew():TouchDoc()
end

--- Touches the document to trigger network refresh
function DTShares:TouchDoc()
    local doc = self:_safeDoc()
    if doc then
        doc:BeginChange()
        doc.data.modifiedAt = dmhub.serverTime
        doc:CompleteChange("touch timestamp", {undoable = false})
    end
end

--- Initializes the settings document with default structure if it's not already set
--- @return table doc The document
function DTShares:_ensureDocInitialized()
    local doc = self.mod:GetDocumentSnapshot(self.documentName)
    if DTShares._validDoc(doc) then
        return doc
    end
    return self:InitializeDocument()
end

--- Return a document object that is guaranteed to be valid or nil
--- @return table|nil doc The doc if it's valid
function DTShares:_safeDoc()
    local doc = self:_ensureDocInitialized()
    if DTShares._validDoc(doc) then
        return doc
    end
    return nil
end

--- Determine whether the document has the valid / expected structure
--- @param doc table The document to validate
--- @return boolean isValid Whether the document has the expected structure
function DTShares._validDoc(doc)
    local isValid = doc.data and type(doc.data) == "table"
        and doc.data.senders and type(doc.data.senders) == "table"
        and doc.data.recipients and type(doc.data.recipients) == "table"
    return isValid
end

if DTConstants.DEVMODE then
    Commands.thcdtshares = function(args)
        local shares = DTShares.CreateNew()
        if shares then
            print("THC:: SHARES::", json(shares:GetShares()))
        end
    end

    Commands.thcdtclearshares = function(args)
        DTShares.CreateNew():InitializeDocument()
    end
end
