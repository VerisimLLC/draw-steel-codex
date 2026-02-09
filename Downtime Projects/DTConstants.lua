--- Shared constants for the Downtime Projects system
--- Provides centralized constant definitions used across multiple downtime classes
--- @class DTConstants
DTConstants = RegisterGameType("DTConstants")

DTConstants.DEVMODE = false
DTConstants.DEVUI = false

--- The location on the character we're storing the downtime
DTConstants.CHARACTER_STORAGE_KEY = "downtimeInfo"
DTConstants.FOLLOWERS_STORAGE_KEY = "followers"
DTConstants.FOLLOWER_AVAILROLL_KEY = "availableRolls"
DTConstants.FOLLOWER_ROLLS_KEY = "followerRolls"

--- The natural roll at and above which is considered a crit or breakthrough
DTConstants.BREAKTHROUGH_MIN = 19

--- Valid language penalty values used in downtime projects and rolls
DTConstants.LANGUAGE_PENALTY = {
    DTConstant.CreateNew("NONE", 1, "None"),
    DTConstant.CreateNew("RELATED", 2, "Related"),
    DTConstant.CreateNew("UNKNOWN", 3, "Unknown")
}

--- Valid test characteristics used in downtime projects
DTConstants.CHARACTERISTICS = {
    DTConstant.CreateNew("mgt", 1, "Might"),
    DTConstant.CreateNew("agl", 2, "Agility"),
    DTConstant.CreateNew("rea", 3, "Reason"),
    DTConstant.CreateNew("inu", 4, "Intuition"),
    DTConstant.CreateNew("prs", 5, "Presence")
}

print("TYPE:: CHARACTERISTICS = ", DTConstants.CHARACTERISTICS[1].typeName)

--- Valid status values for downtime projects
DTConstants.STATUS = {
    DTConstant.CreateNew("ACTIVE", 1, "Active"),
    DTConstant.CreateNew("PAUSED", 2, "Paused"),
    DTConstant.CreateNew("MILESTONE", 3, "Milestone"),
    DTConstant.CreateNew("COMPLETE", 4, "Complete")
}

--- Valid follower types
DTConstants.FOLLOWER_TYPE = {
    DTConstant.CreateNew("artisan", 1, "Artisan"),
    DTConstant.CreateNew("sage", 2, "Sage")
}

--- Convenience accessors for direct access to specific constants
DTConstants.LANGUAGE_PENALTY.NONE = DTConstants.LANGUAGE_PENALTY[1]
DTConstants.LANGUAGE_PENALTY.RELATED = DTConstants.LANGUAGE_PENALTY[2]
DTConstants.LANGUAGE_PENALTY.UNKNOWN = DTConstants.LANGUAGE_PENALTY[3]

DTConstants.CHARACTERISTICS.MIGHT = DTConstants.CHARACTERISTICS[1]
DTConstants.CHARACTERISTICS.AGILITY = DTConstants.CHARACTERISTICS[2]
DTConstants.CHARACTERISTICS.REASON = DTConstants.CHARACTERISTICS[3]
DTConstants.CHARACTERISTICS.INTUITION = DTConstants.CHARACTERISTICS[4]
DTConstants.CHARACTERISTICS.PRESENCE = DTConstants.CHARACTERISTICS[5]

DTConstants.STATUS.ACTIVE = DTConstants.STATUS[1]
DTConstants.STATUS.PAUSED = DTConstants.STATUS[2]
DTConstants.STATUS.MILESTONE = DTConstants.STATUS[3]
DTConstants.STATUS.COMPLETE = DTConstants.STATUS[4]

DTConstants.FOLLOWER_TYPE.ARTISAN = DTConstants.FOLLOWER_TYPE[1]
DTConstants.FOLLOWER_TYPE.SAGE = DTConstants.FOLLOWER_TYPE[2]

--- Helper function to get display text for enum keys
--- Looks up the DTConstant in the enum table and returns displayText
--- Falls back to title-case formatting if key not found
--- @param enumTable table The enum table containing DTConstant instances
--- @param key string The key to look up
--- @return string displayText The display text or formatted key
function DTConstants.GetDisplayText(enumTable, key)
    -- First try to find the DTConstant record
    if enumTable and type(enumTable) == "table" then
        for _, constant in ipairs(enumTable) do
            if constant.key == key then
                return constant.displayText
            end
        end
    end

    -- Fallback: convert key to title case
    if key and type(key) == "string" then
        -- Handle both underscores and spaces, convert to title case
        return key:gsub("[_%s]+", " ")  -- Replace underscores and multiple spaces with single space
                  :gsub("(%a)([%w]*)", function(first, rest)  -- Title case each word
                      return first:upper() .. rest:lower()
                  end)
                  :gsub("^%s+", ""):gsub("%s+$", "")  -- Trim leading/trailing spaces
    end

    return key or ""
end