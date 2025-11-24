--- Downtime information manager for a character
--- Manages available rolls and downtime projects for a single character
--- Stored within the character object in the root node named 'downtimeInfo'
--- @class DTInfo
--- @field availableRolls number Counter that the Director increments via Grant Rolls to All
--- @field downtimeProjects DTProject[] The list of DTProject records for the character
DTInfo = RegisterGameType("DTInfo")
DTInfo.__index = DTInfo

--- Creates a new downtime info instance
--- @return DTInfo instance The new downtime info instance
function DTInfo:new()
    local instance = setmetatable({}, self)

    instance.availableRolls = 0
    instance.downtimeProjects = {}

    return instance
end

--- Gets the number of available rolls
--- @return number availableRolls The number of available rolls
function DTInfo:GetAvailableRolls()
    return self:try_get("availableRolls") or 0
end

--- Sets the number of available rolls
--- @param rolls number The new number of available rolls
--- @return DTInfo self For chaining
function DTInfo:SetAvailableRolls(rolls)
    self.availableRolls = math.max(0, math.floor(rolls or 0))
    return self
end

--- Modifies the available rolls counter
--- @param rolls number The number of rolls to add
--- @return DTInfo self For chaining
function DTInfo:GrantRolls(rolls)
    self.availableRolls = math.max(0, self:GetAvailableRolls() + (rolls or 0))
    return self
end

--- Uses available rolls (decrements counter)
--- @param rolls number The number of rolls to use
--- @return DTInfo self For chaining
function DTInfo:UseAvailableRolls(rolls)
    local useCount = math.max(0, math.floor(rolls or 0))
    self.availableRolls = math.max(0, self:GetAvailableRolls() - useCount)
    return self
end

--- Gets all downtime projects for this character
--- @return table downtimeProjects Hash table of DTProject instances keyed by GUID
function DTInfo:GetProjects()
    return self:try_get("downtimeProjects") or {}
end

--- Gets all downtime projects sorted by sort order
--- @return table projectsArray Array of DTProject instances sorted by sortOrder
function DTInfo:GetSortedProjects()
    -- Convert hash table to array
    local projectsArray = {}
    local projects = self:GetProjects()
    for _, project in pairs(projects or {}) do
        projectsArray[#projectsArray + 1] = project
    end

    -- Sort the array
    table.sort(projectsArray, function(a, b)
        return a:GetSortOrder() < b:GetSortOrder()
    end)

    return projectsArray
end

--- Returns the project matching the key or nil if not found
--- @param projectId string The GUID identifier of the project to return
--- @return DTProject|nil project The project referenced by the key or nil if it doesn't exist
function DTInfo:GetProject(projectId)
    return self:GetProjects()[projectId or ""]
end

--- Adds a new downtime project to this character
--- @param ownerId string The unique identifier of the token that owns this project
--- @return DTProject project The newly created project
function DTInfo:AddProject(ownerId)
    local nextOrder = self:_maxProjectOrder() + 1
    local project = DTProject:new(nextOrder, ownerId)
    self:GetProjects()[project:GetID()] = project
    return project
end

--- Removes a downtime project from this character
--- @param projectId string The GUID of the project to remove
--- @return DTInfo self For chaining
function DTInfo:RemoveProject(projectId)
    local projects = self:GetProjects()
    if projects[projectId] then
        projects[projectId] = nil
    end
    return self
end

--- Gets the highest sort order number among all projects for this character
--- @return number maxOrder The highest sort order number, or 0 if no projects exist
--- @private
function DTInfo:_maxProjectOrder()
    local maxOrder = 0

    local projects = self:GetProjects()
    for _, project in pairs(projects or {}) do
        local order = project:GetSortOrder()
        if order > maxOrder then
            maxOrder = order
        end
    end

    return maxOrder
end

--- Extend creature to get Downtime Information
--- @return DTinfo|nil downtimeInfo the Downtme Info for the character or nil if we can't find or create
creature.GetDowntimeInfo = function(self)
    local downtimeInfo = self:try_get(DTConstants.CHARACTER_STORAGE_KEY)
    if downtimeInfo == nil then
        local token = dmhub.LookupToken(self)
        if token then
            downtimeInfo = DTInfo:new()
            token:ModifyProperties{
                description = "Adding Downtime Info",
                undoable = false,
                execute = function()
                    token.properties[DTConstants.CHARACTER_STORAGE_KEY] = downtimeInfo
                end
            }
        end
    end
    if downtimeInfo and type(downtimeInfo.GetAvailableRolls) ~= "function" then
        setmetatable(downtimeInfo, DTInfo)
    end
    return downtimeInfo
end