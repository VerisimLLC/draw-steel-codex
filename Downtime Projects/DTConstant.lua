--- DTConstant class for representing typed constant values with metadata
--- Provides a clean object-oriented approach to enum-like constants with sorting and display information
--- @class DTConstant
--- @field key string The internal key value used for storage and comparison
--- @field sortOrder number Display order for dropdown lists and UI sorting
--- @field displayText string User-friendly display text for UI presentation
DTConstant = RegisterGameType("DTConstant")
DTConstant.__index = DTConstant

--- Creates a new DTConstant instance
--- @param key string The internal key value (e.g., "ACTIVE", "PAUSED")
--- @param sortOrder number Display order for sorting (lower numbers appear first)
--- @param displayText string User-friendly text for display (e.g., "Active", "Paused")
--- @return DTConstant instance The new DTConstant instance
function DTConstant:new(key, sortOrder, displayText)
    local instance = setmetatable({}, self)
    instance.key = key
    instance.sortOrder = sortOrder
    instance.displayText = displayText
    return instance
end

--- Returns the key when the constant is converted to a string
--- This allows natural string comparisons and debugging
--- @return string key The internal key value
function DTConstant:__tostring()
    return self.key
end

--- Enables equality comparisons with strings and other DTConstant instances
--- Supports both DTConstant-to-DTConstant and DTConstant-to-string comparisons
--- @param other DTConstant|string The value to compare against
--- @return boolean equal True if the values are equal
function DTConstant:__eq(other)
    if type(other) == "string" then
        return self.key == other
    elseif getmetatable(other) == DTConstant then
        return self.key == other.key
    end
    return false
end

--- Gets the internal key value
--- @return string key The internal key value
function DTConstant:GetKey()
    return self.key
end

--- Gets the display text for UI presentation
--- @return string displayText The user-friendly display text
function DTConstant:GetDisplayText()
    return self.displayText
end

--- Gets the sort order for UI sorting
--- @return number sortOrder The sort order value
function DTConstant:GetSortOrder()
    return self.sortOrder
end