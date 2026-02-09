--[[
    Description Status
    Tracks completion status for character description fields.
    Inherits from CBSelectionStatus but overrides status calculation
    to count filled description fields instead of using FeatureCache.
]]
CBDescriptionStatus = RegisterGameType("CBDescriptionStatus", "CBSelectionStatus")

--- Override CreateNew to return CBDescriptionStatus instance (not parent)
--- @param config table Configuration options
--- @return CBDescriptionStatus
function CBDescriptionStatus.CreateNew(config)
    local opts = {
        selectorName = config.selectorName,
        visible = config.visible ~= false,
        suppressRow1 = config.suppressRow1 or false,
        displayName = config.displayName or "Character",
    }
    return CBDescriptionStatus.new(opts)
end

--- Description fields to track for completion (getter method names)
CBDescriptionStatus.DESCRIPTION_FIELDS = {
    "GetHeight",
    "GetWeight",
    "GetHair",
    "GetEyes",
    "GetSkinTone",
    "GetBuild",
    "GetGenderPresentation",
    "GetPronouns",
    "GetPhysicalFeatures",
}

--- Override CalculateStatus to count description fields instead of features
--- @return table Array of status entry tables
function CBDescriptionStatus:CalculateStatus()
    local hero = CharacterBuilder._getHero()
    local filled = 0
    local total = #CBDescriptionStatus.DESCRIPTION_FIELDS

    if hero then
        local desc = hero:Description()
        if desc then
            for _, getter in ipairs(CBDescriptionStatus.DESCRIPTION_FIELDS) do
                local method = desc[getter]
                if method then
                    local value = method(desc)
                    if value and type(value) == "string" and #value > 0 then
                        filled = filled + 1
                    end
                end
            end
        end
    end

    self.numSelected = filled
    self.numAvailable = total

    -- Return empty status entries (we don't need detailed breakdown for right panel)
    self.statusEntries = {}
    return self.statusEntries
end
