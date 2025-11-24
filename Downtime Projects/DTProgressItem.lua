--- Base class for items that affect project progress
--- Provides common functionality for rolls and adjustments
--- @class DTProgressItem
--- @field id string GUID identifier for this item
--- @field amount number The progress value this item contributes
--- @field commitDate string|osdate ISO date when this item was committed
--- @field commitBy string GUID of user who committed this item
--- @field serverTime number VTT server time when roll was committed
DTProgressItem = RegisterGameType("DTProgressItem")
DTProgressItem.__index = DTProgressItem

--- Creates a new progress item instance
--- @param amount? number The progress amount for this item
--- @return DTProgressItem instance The new progress item instance
function DTProgressItem:new(amount)
    local instance = setmetatable({}, self)

    instance.id = dmhub.GenerateGuid()
    instance.amount = amount or 0
    instance.commitDate = ""
    instance.commitBy = ""
    instance.serverTime = 0

    return instance
end

--- Gets the identifier of this item
--- @return string id GUID id of this item
function DTProgressItem:GetID()
    return self.id
end

--- Sets the progress amount for this item
--- @param amount number The progress amount
--- @return DTProgressItem self For chaining
function DTProgressItem:SetAmount(amount)
    self.amount = math.floor(amount or 0)
    return self
end

--- Returns the progress amount this item contributes
--- @return number amount The progress amount
function DTProgressItem:GetAmount()
    return self.amount or 0
end

--- Sets commit information for this item
--- @return DTProgressItem self For chaining
function DTProgressItem:SetCommitInfo()
    self.commitDate = os.date("!%Y-%m-%dT%H:%M:%SZ")
    self.commitBy = dmhub.userid
    self.serverTime = dmhub.serverTime
    return self
end

--- Gets when this item was committed
--- @return string|osdate|nil commitDate ISO date string or nil if not committed
function DTProgressItem:GetCommitDate()
    return (self.commitDate and #self.commitDate) and self.commitDate or nil
end

--- Gets who committed this item
--- @return string commitBy User GUID or nil if not committed
function DTProgressItem:GetCommitBy()
    return (self.commitBy and #self.commitBy) and self.commitBy or nil
end

--- Gets the VTT time this item was committed
--- @return number|nil serverTime The VTT server time or nil if not committed
function DTProgressItem:GetServerTime()
    return (self.serverTime and self.serverTime > 0) and self.serverTime or nil
end

function DTProgressItem:GetDescription()
    -- Unimplemented method - Derivations should implement
    return ""
end
