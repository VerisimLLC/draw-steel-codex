--- Progress adjustment record for tracking manual adjustments to downtime project progress
--- Records manual progress changes made by directors or players with reasoning
--- @class DTAdjustment: DTProgressItem
--- @field reason string Required. The reason for the adjustment
DTAdjustment = RegisterGameType("DTAdjustment", "DTProgressItem")
DTAdjustment.reason = ""

function DTAdjustment.CreateNew(args)
    args = args or {}
    args.id = args.id or dmhub.GenerateGuid()
    return DTAdjustment.new(args)
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