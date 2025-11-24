--- Progress adjustment record for tracking manual adjustments to downtime project progress
--- Records manual progress changes made by directors or players with reasoning
--- @class DTAdjustment
--- @field reason string Required. The reason for the adjustment
DTAdjustment = RegisterGameType("DTAdjustment", "DTProgressItem")
DTAdjustment.__index = DTAdjustment

--- Creates a new progress adjustment instance
--- @param amount? number Progress points to add (negative to subtract)
--- @param reason? string The reason for the adjustment
--- @return DTAdjustment|DTProgressItem instance The new progress adjustment instance
function DTAdjustment:new(amount, reason)
    local instance = setmetatable(DTProgressItem:new(amount), self)

    instance.reason = reason or ""

    return instance
end

--- Sets the reason for the adjustment
--- @param reason string The reason for the adjustment
--- @return DTAdjustment self For chaining
function DTAdjustment:SetReason(reason)
    self.reason = reason or ""
    return self
end

--- Gets the reason for the adjustment
--- @return string reason The reason for the adjustment
function DTAdjustment:GetReason()
    return self.reason or ""
end

--- Returns description info
--- @return string description The reason value
function DTAdjustment:GetDescription()
    return self:GetReason()
end