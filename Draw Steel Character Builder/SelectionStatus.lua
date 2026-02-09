--[[
    Selection Status
    Orchestrates status reporting for character builder selectors.
    Optionally uses FeatureCache when available; designed for future
    expansion to support other status types.
]]
CBSelectionStatus = RegisterGameType("CBSelectionStatus")

local _formatOrder = CharacterBuilder._formatOrder
local _mergeKeyedTables = CharacterBuilder._mergeKeyedTables
local _toArray = CharacterBuilder._toArray
local _ucFirst = CharacterBuilder._ucFirst

--- Create a new selection status reporter
--- @param config table Configuration options
--- @return CBSelectionStatus
function CBSelectionStatus.CreateNew(config)
    local opts = {
        featureCache = config.featureCache,  -- OPTIONAL: may be nil
        selectorName = config.selectorName,
        visible = config.visible ~= false,   -- default true
        suppressRow1 = config.suppressRow1 or false,
        displayName = config.displayName or _ucFirst(config.selectorName),
        -- Note: statusEntries, numSelected, numAvailable are lazily created on first CalculateStatus()
    }
    return CBSelectionStatus.new(opts)
end

--[[
    Configuration Methods
]]

--- Check if this status panel should be visible
--- @param hero character The hero character
--- @return boolean
function CBSelectionStatus:IsVisible(hero)
    local visible = self:try_get("visible", true)
    if type(visible) == "function" then
        return visible(hero)
    end
    return visible == true
end

--- Check if the first row should be suppressed
--- @return boolean
function CBSelectionStatus:SuppressFirstRow()
    return self:try_get("suppressRow1", false)
end

--- Get the display name for this status
--- @return string
function CBSelectionStatus:GetDisplayName()
    return self:try_get("displayName", "Unknown")
end

--- Get the selector name
--- @return string
function CBSelectionStatus:GetSelectorName()
    return self:try_get("selectorName", "")
end

--[[
    FeatureCache Access (Optional)
]]

--- Get the underlying feature cache
--- @return CBFeatureCache|nil
function CBSelectionStatus:GetFeatureCache()
    return self:try_get("featureCache")
end

--- Check if a feature cache is present
--- @return boolean
function CBSelectionStatus:HasFeatureCache()
    return self:GetFeatureCache() ~= nil
end

--- Get the name of the currently selected item (delegates to featureCache)
--- @return string
function CBSelectionStatus:GetSelectedName()
    local cache = self:GetFeatureCache()
    if cache then return cache:GetSelectedName() end
    return ""
end

--- Get the ID of the currently selected item (delegates to featureCache)
--- @return string
function CBSelectionStatus:GetSelectedId()
    local cache = self:GetFeatureCache()
    if cache then return cache:GetSelectedId() end
    return ""
end

--[[
    Status Calculation
]]

--- Calculate and return status entries (sorted array)
--- @return table Array of status entry tables
function CBSelectionStatus:CalculateStatus()
    -- Return cached if available
    -- local cached = self:try_get("statusEntries")
    -- if cached then return cached end

    local statusEntries = {}
    local numSelected = 0
    local numAvailable = 0
    local displayName = self:GetDisplayName()
    local featureCache = self:GetFeatureCache()

    -- Add base row if not suppressed
    if not self:SuppressFirstRow() then
        local baseEntry = {
            id = displayName,
            order = _formatOrder(0, displayName),
            available = 1,
            selected = 0,
            selectedDetail = {},
        }

        if featureCache then
            baseEntry.selected = 1
            baseEntry.selectedDetail = { featureCache:GetSelectedName() }
        end

        statusEntries[displayName] = baseEntry
        numAvailable = numAvailable + 1
        if featureCache then numSelected = numSelected + 1 end
    end

    -- Get feature-based status from FeatureCache if present
    if featureCache then
        local featureStatusEntries = featureCache:CalculateStatus()
        statusEntries = _mergeKeyedTables(statusEntries, featureStatusEntries)

        local fcSelected, fcAvailable = featureCache:GetStatusSummary()
        numSelected = numSelected + fcSelected
        numAvailable = numAvailable + fcAvailable
    end

    -- Sort and cache
    statusEntries = _toArray(statusEntries)
    table.sort(statusEntries, function(a, b) return a.order < b.order end)

    self.statusEntries = statusEntries
    self.numSelected = numSelected
    self.numAvailable = numAvailable

    return statusEntries
end

--- Get status summary
--- @return integer numSelected
--- @return integer numAvailable
function CBSelectionStatus:GetStatusSummary()
    self:CalculateStatus()
    return self:try_get("numSelected", 0), self:try_get("numAvailable", 0)
end

--- Check if all selections are complete
--- @return boolean
function CBSelectionStatus:AllComplete()
    local numSelected, numAvailable = self:GetStatusSummary()
    return numSelected >= numAvailable
end

--- Invalidate cached status (call when underlying data changes)
function CBSelectionStatus:Invalidate()
    self.statusEntries = nil
    self.numSelected = 0
    self.numAvailable = 0
end
