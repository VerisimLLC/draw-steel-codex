--- Project roll record for tracking dice rolls made on downtime projects
--- Records all details of a roll including modifiers, results, and context
--- @class DTRoll
--- @field rollString string The text representation of the roll
--- @field rolledBy string The name of the character or follower responsible for the roll
--- @field rolledById string The unique identifier of the token responsible for the roll
--- @field rolledByFollowerId string|nil The unique identifier of the follower who rolled, if applicable
--- @field naturalRoll number The unmodified die roll result
--- @field breakthrough boolean Whether this roll was triggered by a Breakthrough
--- @field rollGuid string The VTT's GUID for the roll instance
--- @field audit string Text representation of the roll setup
DTRoll = RegisterGameType("DTRoll", "DTProgressItem")
DTRoll.__index = DTRoll

--- Creates a new project roll instance
--- @param naturalRoll? number The unmodified die roll result
--- @param modifiedRoll? number The final roll result after applying all modifiers
--- @return DTRoll|DTProgressItem instance The new project roll instance
function DTRoll:new(naturalRoll, modifiedRoll)
    local instance = setmetatable(DTProgressItem:new(modifiedRoll), self)

    instance.rollString = ""
    instance.rolledBy = ""
    instance.rolledById = ""
    instance.rolledByFollowerId = nil
    instance.naturalRoll = math.floor(naturalRoll or 0)
    instance.breakthrough = false
    instance.rollGuid = ""
    instance.audit = ""

    return instance
end

--- Sets the progress amount for this item
--- @param amount number The progress amount
--- @return DTRoll self For chaining
function DTRoll:SetAmount(amount)
    self.amount = math.max(1, math.floor(amount or 0))
    return self
end

--- Sets the rollString used for this roll
--- @param rollString string|nil The rollString name or nil to clear
--- @return DTRoll self For chaining
function DTRoll:SetRollString(rollString)
    self.rollString = rollString or ""
    return self
end

--- Gets the rollString used for this roll
--- @return string|nil rollString The rollString name or nil if no rollString was used
function DTRoll:GetRollString()
    return self.rollString or ""
end

--- Sets the name of the entity responsible for this roll
--- @param rolledBy string The name of the entity responsible for this roll
--- @return DTRoll self For chaining
function DTRoll:SetRolledBy(rolledBy)
    self.rolledBy = rolledBy or ""
    return self
end

--- Gets the name of the entity responsible for this roll
--- @return string rolledBy The name of the entity responsible for this roll
function DTRoll:GetRolledBy()
    return self.rolledBy or ""
end

--- Sets the identifier of the entity responsible for this roll
--- @param rolledById string The id of the entity responsible for this roll
--- @return DTRoll self For chaining
function DTRoll:SetRolledByID(rolledById)
    self.rolledById = rolledById or ""
    return self
end

--- Gets the unique id of the entity responsible for this roll
--- @return string rolledById The id of the entity responsible for this roll
function DTRoll:GetRolledByID()
    return self:try_get("rolledById") or ""
end

--- Sets the identifier of the follower responsible for this roll
--- @param followerId string|nil The id of the follower responsible for this roll
--- @return DTRoll self For chaining
function DTRoll:SetRolledByFollowerID(followerId)
    self.rolledByFollowerId = followerId
    return self
end

--- Gets the unique id of the follower responsible for this roll
--- @return string|nil followerId The unique ID of the follower responsible for the roll or nil if none
function DTRoll:GetRolledByFollowerID()
    return self:try_get("rolledByFollowerId")
end

--- Custom format for our committed by - add roller if we have it
--- @return string commitBy User GUID or nil if not committed
--- @return string rolledBy Name of the entity responsible for the roll
function DTRoll:GetCommitBy()
    return DTProgressItem.GetCommitBy(self), self:GetRolledBy()
end

--- Returns audit detail
--- @return string description Audit information
function DTRoll:GetDescription()
    return self:GetAudit()
end

--- Sets the natural (unmodified) roll result
--- @param roll number The unmodified die roll result
--- @return DTRoll self For chaining
function DTRoll:SetNaturalRoll(roll)
    self.naturalRoll = math.floor(roll or 0)
    return self
end

--- Gets the natural (unmodified) roll result
--- @return number naturalRoll The unmodified die roll result
function DTRoll:GetNaturalRoll()
    return self.naturalRoll or 0
end

--- Sets whether this roll was triggered by a breakthrough
--- @param isBreakthrough boolean True if this was a breakthrough roll
--- @return DTRoll self For chaining
function DTRoll:SetBreakthrough(isBreakthrough)
    self.breakthrough = isBreakthrough or false
    return self
end

--- Gets whether this roll was triggered by a breakthrough
--- @return boolean breakthrough True if this was a breakthrough roll
function DTRoll:GetBreakthrough()
    return self.breakthrough or false
end

--- Sets the audit information for this roll
--- @param audit string The audit information for the roll
--- @return DTRoll self For chaining
function DTRoll:SetAudit(audit)
    self.audit = audit or ""
    return self
end

--- Gets the audit information for this roll
--- @return string audit The text representation of the audit
function DTRoll:GetAudit()
    return self.audit or ""
end

--- Sets the VTT roll Id for this roll
--- @param guid string The VTT id for the roll
--- @return DTRoll self For chaining
function DTRoll:SetRollGuid(guid)
    self.rollGuid = guid or ""
    return self
end

--- Gets the VTT roll ID for this roll
--- @return string rollGuid The VTT roll ID
function DTRoll:GetRollGuid()
    return self.rollGuid or ""
end

--- Validates if the given language penalty is valid
--- @param penalty string The language penalty to validate
--- @return boolean valid True if the penalty is valid
--- @private
function DTRoll:_isValidLanguagePenalty(penalty)
    for _, validPenalty in pairs(DTConstants.LANGUAGE_PENALTY) do
        if penalty == validPenalty.key then
            return true
        end
    end
    return false
end
