--- Downtime project containing all project data and progress tracking
--- Represents a complete downtime project with status tracking, rolls, and adjustments
--- @class DTProject: GameType
--- @field new fun(o?: table): DTProject
--- @field id string GUID identifier for this project
--- @field ownerId string GUID identifier of the owner of this project
--- @field sortOrder number The sort order for this objective
--- @field itemId string The GUID of the item we're crafting, if that's what we're doing
--- @field activityId string The GUID of the DowntimeActivity this project came from, if that's what we're doing
--- @field title string The name of the project
--- @field itemPrerequisite string Any special items required to start/continue the project
--- @field projectSource string The lore source (book, tutor, etc.) enabling this project
--- @field projectSourceLanguages string[] The languages this project requires
--- @field projectSourceLanguagePenalty string The character's language relationship to the project source language
--- @field testCharacteristic string The characteristic used for project rolls
--- @field testCharacteristics {} The list of potential test characteristics for project rolls
--- @field projectGoal number The total project points needed to complete the project
--- @field status string Current state of the project
--- @field statusReason string Explanation for why the project is paused (if applicable)
--- @field milestoneThreshold number|nil Progress value at which the project automatically pauses for Director review
--- @field projectRolls table Array of DTRoll objects - History of all rolls made on this project
--- @field progressAdjustments table Array of DTAdjustment objects - History of all adjustments made to project progress
--- @field createdBy string GUID identifier of the user who created this project
--- @field itemsGiven table<string, boolean>|nil Item ids this project has given; each is given once, even if picked again
DTProject = RegisterGameType("DTProject")
DTProject.sortOrder = 1

local DEFAULT_LANG_PENALTY = DTConstants.LANGUAGE_PENALTY.NONE.key
local DEFAULT_STATUS = DTConstants.STATUS.PAUSED.key

DTProject.itemId = ""
DTProject.activityId = ""
DTProject.title = ""
DTProject.itemPrerequisite = ""
DTProject.projectSource = ""
DTProject.projectSourceLanguagePenalty = DEFAULT_LANG_PENALTY -- Unneeded now?
DTProject.projectGoal = 1
DTProject.status = DEFAULT_STATUS
DTProject.statusReason = "New Project - Ask your Director to review"
DTProject.milestoneThreshold = 0
DTProject.createdBy = dmhub.userid

DTProject._cachedProgress = nil        -- Stores the calculated progress value
DTProject._progressDirty = true        -- Marks cache as needing recalculation



--- Creates a new downtime project instance
--- @param sortOrder number The sort order for this project
--- @param ownerId string The unique identifier of the token that owns this project
--- @param id string|nil Optional GUID to assign; a new one is generated when omitted
--- @return DTProject instance The new project instance
function DTProject.CreateNew(sortOrder, ownerId, id)

    local args = {
        id = id or dmhub.GenerateGuid(),
        ownerId = ownerId,
        sortOrder = sortOrder or 1,
        projectSourceLanguages = {},
        testCharacteristics = {},
        projectRolls = {},
        progressAdjustments = {},
        createdBy = dmhub.userid,
    }

    return DTProject.new(args)
end

--- Gets the identifier of this project
--- @return string id GUID id of this project
function DTProject:GetID()
    return self.id
end

--- Returns the owner of this project
--- @return string ownerId The owner of this project
function DTProject:GetOwnerID()
    local ownerId = self:try_get("ownerId") or ""
    if #ownerId == 0 then
        ownerId = DTHelpers.FindProjectOwner(self:GetID())
        self.ownerId = ownerId
    end
    return ownerId
end

--- Gets the identifier of the item we're crafting, if that's what we're doing
--- @return string itemId the GUID of the item
function DTProject:GetItemID()
    return self:try_get("itemId") or ""
end

--- Sets the id of the item we're crafting
--- @param itemId string The GUID of the item we're crafting
--- @return DTProject self For chaining
function DTProject:SetItemID(itemId)
    self.itemId = itemId or ""
    return self
end

--- Gets the identifier of the downtime activity this project came from, if that's what we're doing
--- @return string activityId The GUID of the DowntimeActivity, or "" if this project has no activity
function DTProject:GetActivityID()
    return self:try_get("activityId") or ""
end

--- Sets the id of the downtime activity this project came from
--- @param activityId string The GUID of the DowntimeActivity
--- @return DTProject self For chaining
function DTProject:SetActivityID(activityId)
    self.activityId = activityId or ""
    return self
end

--- Gets the title of this project
--- @return string title The project title
function DTProject:GetTitle()
    return self.title or ""
end

--- Sets the title of this project
--- @param title string The new title for the project
--- @return DTProject self For chaining
function DTProject:SetTitle(title)
    self.title = title or ""
    return self
end

--- Gets the item prerequisite for this project
--- @return string itemPrerequisite The item prerequisite
function DTProject:GetItemPrerequisite()
    return self.itemPrerequisite or ""
end

--- Sets the item prerequisite for this project
--- @param prerequisite string The item prerequisite
--- @return DTProject self For chaining
function DTProject:SetItemPrerequisite(prerequisite)
    self.itemPrerequisite = prerequisite or ""
    return self
end

--- Gets the project source
--- @return string projectSource The project source
function DTProject:GetProjectSource()
    return self.projectSource or ""
end

--- Sets the project source
--- @param source string The project source
--- @return DTProject self For chaining
function DTProject:SetProjectSource(source)
    self.projectSource = source or ""
    return self
end

--- Gets the language id's for the project source
--- @return string[] languageIds The list of language id's for the project source
function DTProject:GetProjectSourceLanguages()
    return self:try_get("projectSourceLanguages") or {}
end

--- Set the language id's for the project source
--- @param langIds string[] List of lanugage id's for the project source
--- @return DTProject self For chaining
function DTProject:SetProjectSourceLanguages(langIds)
    self.projectSourceLanguages = langIds
    return self
end

--- Gets the project source language penalty
--- @return string languagePenalty One of DTConstants.LANGUAGE_PENALTY values
function DTProject:GetProjectSourceLanguagePenalty()
    return self.projectSourceLanguagePenalty or DEFAULT_LANG_PENALTY
end

--- Sets the project source language penalty
--- @param penalty string One of DTConstants.LANGUAGE_PENALTY values
--- @return DTProject self For chaining
function DTProject:SetProjectSourceLanguagePenalty(penalty)
    if self:_isValidLanguagePenalty(penalty) then
        self.projectSourceLanguagePenalty = penalty
    end
    return self
end

--- Gets the list of test characteristics for this project
--- Falls back to legacy single characteristic if list is empty/nil
--- @return table characteristics Array of characteristic keys from DTConstants.CHARACTERISTICS
function DTProject:GetTestCharacteristics()
    if self:try_get("testCharacteristics") and #self.testCharacteristics > 0 then
        return self.testCharacteristics
    end

    local legacy = self:try_get("testCharacteristic")
    if legacy and legacy ~= "" then
        local newValue = {legacy}

        local current = self:get_or_add("testCharacteristics", newValue)
        current = legacy

        return newValue
    end

    return {}
end

--- Sets the list of test characteristics for this project
--- Validates and filters to only valid characteristics
--- @param characteristics table Array of characteristic keys from DTConstants.CHARACTERISTICS
--- @return DTProject self For chaining
function DTProject:SetTestCharacteristics(characteristics)
    self.testCharacteristics = self:_ensureValidCharacteristics(characteristics)
    return self
end

--- Gets the project goal
--- @return number goal The total project points needed to complete
function DTProject:GetProjectGoal()
    return self.projectGoal or 1
end

--- Sets the project goal
--- @param goal number|nil The total project points needed to complete; nil means 1
--- @return DTProject self For chaining
function DTProject:SetProjectGoal(goal)
    self.projectGoal = math.max(1, math.floor(goal or 1))
    return self
end

--- Gets the status of this project
--- @return string status One of DTConstants.STATUS values
function DTProject:GetStatus()
    return self.status or DEFAULT_STATUS
end

--- Sets the status of this project
--- @param status string One of DTConstants.STATUS values
--- @return DTProject self For chaining
function DTProject:SetStatus(status)
    if self:_isValidStatus(status) then
        self.status = status
    end
    return self
end

--- Gets the status reason
--- @return string reason The status reason
function DTProject:GetStatusReason()
    return self.statusReason or ""
end

--- Sets the status reason
--- @param reason string The status reason
--- @return DTProject self For chaining
function DTProject:SetStatusReason(reason)
    self.statusReason = reason or ""
    return self
end

--- Gets the milestone threshold
--- @return number|nil threshold The milestone threshold or nil if not set
function DTProject:GetMilestoneThreshold()
    return self.milestoneThreshold
end

--- Sets the milestone threshold
--- @param threshold number|nil The milestone threshold or nil to clear
--- @return DTProject self For chaining
function DTProject:SetMilestoneThreshold(threshold)
    if threshold ~= nil then
        self.milestoneThreshold = math.max(0, math.floor(threshold))
    else
        self.milestoneThreshold = 0
    end
    return self
end

--- Returns the number of Breakthroughs rolled against this project
--- @return number breakthroughs
function DTProject:GetBreakthroughRollCount()
    local i = 0
    for _, r in ipairs(self:GetRolls()) do
        if r:GetBreakthrough() then i = i + 1 end
    end
    return i
end

--- Determines whether the project is active / ready to roll
--- @return boolean active True if active
function DTProject:IsActive()
    return self.status == DTConstants.STATUS.ACTIVE.key
end

--- Determines whether this project is in a valid state to roll
--- @return boolean valid True if the project is in a valid state to roll
--- @return table|nil reasons If the state is invalid, the list of reasons it's invalid
function DTProject:IsValidStateToRoll()
    local isValid = true
    local reasons = {}

    if self:GetStatus() ~= DTConstants.STATUS.ACTIVE.key then
        table.insert(reasons, string.format("Project status is not %s.", DTConstants.STATUS.ACTIVE.displayText))
        isValid = false
    end

    if not self:_isValidLanguagePenalty(self:GetProjectSourceLanguagePenalty()) then
        table.insert(reasons, "Source Language Penalty not set or invalid.")
        isValid = false
    end

    if not self:_isValidTestCharacteristics(self:GetTestCharacteristics()) then
        table.insert(reasons, "Test Characteristics are not set or invalid.")
        isValid = false
    end

    if self:GetProjectGoal() <= 0 then
        table.insert(reasons, "Project Goal is not set or is zero.")
        isValid = false
    else
        if self:GetProgress() >= self:GetProjectGoal() then
            table.insert(reasons, "Progress already equals or exceeds goal.")
            isValid = false
        end
    end

    return isValid, #reasons and reasons or nil
end

--- Invalidates the progress cache, forcing recalculation on next GetProgress() call
--- Called internally by AddRoll, RemoveRoll, AddAdjustment, RemoveAdjustment
--- @private
function DTProject:_invalidateProgressCache()
    self._progressDirty = true
end

--- Repairs progress items that came back from storage as plain, method-less tables.
--- A record saved without its "__typeName" tag deserializes with no metatable, so
--- calling GetID or GetAmount on it would fail. The list it lives in says what it
--- should be, and every field of these types has a type-level default (or is read
--- via try_get), so re-attaching the metatable is the whole repair.
--- @param items table The projectRolls or progressAdjustments list
--- @param gameType table DTRoll or DTAdjustment
--- @return table items The same list, with every plain table entry restored
local function _rehydrateItems(items, gameType)
    for _, item in ipairs(items) do
        if type(item) == "table" and getmetatable(item) == nil then
            setmetatable(item, gameType.mt)
        end
    end
    return items
end

--- Gets a specific project roll
--- @param rollId string GUID ID of the roll to find
--- @return DTRoll|nil roll The roll object or nil if not found
--- @return number|nil index The index of the roll in the projectRolls table or nil if not found
function DTProject:GetRoll(rollId)
    if not rollId or type(rollId) ~= "string" or #rollId == 0 then
        return nil, nil
    end

    local rolls = self:GetRolls()
    for i = #rolls, 1, -1 do
        local roll = rolls[i]
        if roll and roll:GetID() == rollId then
            return roll, i
        end
    end

    return nil, nil
end

--- Gets all project rolls
--- @return table projectRolls Array of DTRoll instances
function DTProject:GetRolls()
    return _rehydrateItems(self.projectRolls or {}, DTRoll)
end

--- Sets project status before adding or removing a progress item
--- @param item DTRoll|DTAdjustment|DTProgressItem The progress item to be considered
--- @param direction number The direction of progress: 1 if adding, -1 if removing
--- @param priorProgress number|nil Progress value to use as the baseline instead of the current cached/recomputed progress (used when the item has already been inserted into its list)
function DTProject:_setStateFromProgressChange(item, direction, priorProgress)
    if type(direction) ~= "number" or math.abs(direction) ~= 1 then return end

    local function isRoll() return item.typeName == "DTRoll" end
    local function isAdjustment() return item.typeName == "DTAdjustment" end

    local STATUS = DTConstants.STATUS
    local oldValue = priorProgress or self:GetProgress()
    local newValue = oldValue + (direction * item:GetAmount())
    local currentStatus = self:GetStatus()
    local projectGoal = self:GetProjectGoal()
    local milestoneStop = self:GetMilestoneThreshold()

    self:_healLegacyGrant(oldValue)
    if newValue >= projectGoal then
        self:_markComplete(currentStatus)
    elseif currentStatus == DTConstants.STATUS.COMPLETE.key then
        if newValue < projectGoal then
            self:SetStatus(STATUS.ACTIVE.key)
                :SetStatusReason("")
        end
    elseif currentStatus == DTConstants.STATUS.MILESTONE.key then
        if newValue < self:GetMilestoneThreshold() then
            self:SetStatus(STATUS.ACTIVE.key)
                :SetStatusReason("")
        end
    else -- Active or Paused; same logic
        if milestoneStop > 0 and oldValue < milestoneStop and newValue >= milestoneStop then
            self:SetStatusReason("Milestone achieved! Consult with your Director.")
                :SetStatus(STATUS.MILESTONE.key)
        end
    end
end

--- Is the project stopped until the Director acts (Paused or at a Milestone)?
--- @return boolean
function DTProject:WaitsOnDirector()
    local status = self:GetStatus()
    return status == DTConstants.STATUS.PAUSED.key or status == DTConstants.STATUS.MILESTONE.key
end

--- Has this project already given the item it is crafting now?
--- @return boolean
function DTProject:HasGivenItem()
    local itemId = self:GetItemID()
    local given = self:try_get("itemsGiven")
    return itemId ~= "" and given ~= nil and given[itemId] == true
end

--- Records that this project gave the item it is crafting now.
--- A new table each time, so the write never lands on a shared default.
function DTProject:_recordItemGiven()
    local itemId = self:GetItemID()
    if itemId == "" then
        return
    end
    local given = {}
    for id, value in pairs(self:try_get("itemsGiven") or {}) do
        given[id] = value
    end
    given[itemId] = true
    self.itemsGiven = given
end

--- A crafting project finished before itemsGiven existed gave its item when its
--- progress reached the goal, so one that is Complete at its goal counts as given.
--- Without this, deleting its last roll and rolling again would give a second copy.
--- @param progress number The progress before the change being made
function DTProject:_healLegacyGrant(progress)
    if self:GetStatus() == DTConstants.STATUS.COMPLETE.key and progress >= self:GetProjectGoal()
            and self:try_get("itemsGiven") == nil then
        self:_recordItemGiven()
    end
end

--- Marks the project Complete. The item comes the first time progress reaches
--- the goal, whatever the status was (a Director may have picked Complete by
--- hand), and never again, so deleting a roll and rolling again never crafts a
--- second copy. The banner waits for the transition INTO complete, because
--- progress added to or removed from a finished project comes back through here.
--- @param currentStatus string The status before this change
function DTProject:_markComplete(currentStatus)
    local STATUS = DTConstants.STATUS
    local completing = currentStatus ~= STATUS.COMPLETE.key
    if not self:HasGivenItem() then
        if DTBusinessRules.GiveItemToCharacter(self) then
            self:_recordItemGiven()
        end
    end
    self:SetStatusReason("Project complete.")
        :SetStatus(STATUS.COMPLETE.key)

    -- Announce completion with a dramatic banner (synced to all clients,
    -- non-modal). Title falls back to "a project" for untitled projects.
    -- GetCharacterById, not GetTokenById: the owner may not be on the loaded
    -- map (a Respite run on another map), and the banner must still show.
    if completing then
        local token = dmhub.GetCharacterById(self:GetOwnerID())
        if token ~= nil and token.valid then
            local title = self:GetTitle()
            if title == nil or title == "" then
                title = "a project"
            end
            DramaticBanner.Show{
                tokenid = token.charid,
                text = "Project Complete",
                subtitle = string.format("%s completed %s", token.name, title),
            }
        end
    end
end

--- Changes the goal and settles the status it implies: reaching the new goal
--- completes the project (and gives its item, once); a Complete project whose
--- goal is raised past its progress is Active again.
--- Must be called within token:ModifyProperties on the project's owner.
--- @param goal number The new goal
--- @return DTProject self For chaining
function DTProject:ChangeProjectGoal(goal)
    local STATUS = DTConstants.STATUS
    local currentStatus = self:GetStatus()
    self:_healLegacyGrant(self:GetProgress())
    self:SetProjectGoal(goal)
    if self:GetProgress() >= self:GetProjectGoal() then
        self:_markComplete(currentStatus)
    elseif currentStatus == STATUS.COMPLETE.key then
        self:SetStatus(STATUS.ACTIVE.key)
            :SetStatusReason("")
    end
    return self
end

--- Adds a project roll to this project
--- **NOTE:** This method automatically calculates status
--- @param roll DTRoll The roll to add (only DTRoll has GetBreakthrough; AddRolls is the sole caller)
--- @return DTProject self For chaining
function DTProject:AddRoll(roll)
    
    if roll:GetBreakthrough() or self:IsValidStateToRoll() then

        if not self.projectRolls then
            self.projectRolls = {}
        end

        -- Capture progress BEFORE inserting the roll: _setStateFromProgressChange
        -- must compare against the pre-roll total, otherwise GetProgress() (which
        -- re-sums projectRolls when the cache is dirty) already includes this roll
        -- and the status check double-counts it.
        local priorProgress = self:GetProgress()
        roll:SetCommitInfo()
        self.projectRolls[#self.projectRolls + 1] = roll
        self:_setStateFromProgressChange(roll, 1, priorProgress)
        self:_invalidateProgressCache()

    end

    return self
end

--- Adds several rolls to this project
--- **NOTE:** This method automatically calculates status
--- @param rolls DTRoll[] The rolls to add to the project
--- @return DTProject self For chaining
function DTProject:AddRolls(rolls)
    if rolls and type(rolls) == "table" then
        for _, roll in ipairs(rolls) do
            self:AddRoll(roll)
        end
    end
    return self
end

--- Removes a project roll from this project by ID
--- **NOTE:** This method automatically calculates status
--- @param rollId string The GUID of the roll to remove
--- @return DTProject self For chaining
function DTProject:RemoveRoll(rollId)
    if not self.projectRolls or not rollId then
        return self
    end

    local roll, index = self:GetRoll(rollId)
    if roll then
        self:_setStateFromProgressChange(roll, -1)
        table.remove(self.projectRolls, index)
        self:_invalidateProgressCache()
    end

    return self
end

--- Gets all progress adjustments
--- @return table adjustments Array of DTAdjustment instances
function DTProject:GetAdjustments()
    return _rehydrateItems(self.progressAdjustments or {}, DTAdjustment)
end

--- Adds a progress adjustment to this project
--- **NOTE:** This method automatically calculates status
--- @param adjustment DTAdjustment|DTProgressItem The adjustment to add
--- @return DTProject self For chaining
function DTProject:AddAdjustment(adjustment)
    if not self.progressAdjustments then
        self.progressAdjustments = {}
    end

    self:_setStateFromProgressChange(adjustment, 1)
    adjustment:SetCommitInfo()
    self.progressAdjustments[#self.progressAdjustments + 1] = adjustment
    self:_invalidateProgressCache()
    return self
end

--- Removes a progress adjustment from this project by ID
--- **NOTE:** This method automatically calculates status
--- @param adjustmentId string The GUID of the adjustment to remove
--- @return DTProject self For chaining
function DTProject:RemoveAdjustment(adjustmentId)
    if not self.progressAdjustments or not adjustmentId then
        return self
    end

    local adjustments = self:GetAdjustments()
    for i = #adjustments, 1, -1 do
        local adjustment = adjustments[i]
        if adjustment and adjustment:GetID() == adjustmentId then
            self:_setStateFromProgressChange(adjustment, -1)
            table.remove(self.progressAdjustments, i)
            self:_invalidateProgressCache()
            break
        end
    end

    return self
end

--- Gets the sort order of this project
--- @return number sortOrder The sort order position
function DTProject:GetSortOrder()
    return self.sortOrder or 1
end

--- Sets the sort order of this project
--- @param sortOrder number The new sort order position
--- @return DTProject self For chaining
function DTProject:SetSortOrder(sortOrder)
    self.sortOrder = sortOrder or 1
    return self
end

--- Gets the current progress of this project
--- Uses cached value when available, recalculates only when cache is dirty
--- Cache is invalidated automatically when rolls or adjustments are added/removed
--- @return number progress The total progress points earned on this project
function DTProject:GetProgress()
    local cachedProgress = self:try_get("_cachedProgress")
    local progressDirty = self:try_get("_progressDirty")

    if cachedProgress ~= nil and not progressDirty then
        return cachedProgress
    end

    local progress = 0

    local rolls = self:GetRolls()
    for _, roll in ipairs(rolls) do
        progress = progress + roll:GetAmount()
    end

    local adjustments = self:GetAdjustments()
    for _, adjustment in ipairs(adjustments) do
        progress = progress + adjustment:GetAmount()
    end

    self._cachedProgress = progress
    self._progressDirty = false

    return progress
end

--- Return a list of the unique token ID's who rolled on this project
--- @return table rollers The unique ID's who've rolled on this project
function DTProject:GetUniqueRollers()
    local rollers = {}

    local rolls = self:GetRolls()
    for _, roll in pairs(rolls) do
        local roller = roll:GetRolledByID()
        if roller and #roller > 0 then
            rollers[roller] = true
        end
    end

    return DTHelpers.FlagListToList(rollers)
end

--- Validates if the given status is valid for projects
--- @param status string The status to validate
--- @return boolean valid True if the status is valid
function DTProject:_isValidStatus(status)
    for _, validStatus in pairs(DTConstants.STATUS) do
        if status == validStatus.key then
            return true
        end
    end
    return false
end

--- Validates if the given language penalty is valid
--- @param penalty string The language penalty to validate
--- @return boolean valid True if the penalty is valid
function DTProject:_isValidLanguagePenalty(penalty)
    for _, validPenalty in pairs(DTConstants.LANGUAGE_PENALTY) do
        if penalty == validPenalty.key then
            return true
        end
    end
    return false
end

--- Validates if the project has at least one valid test characteristic
--- @param characteristics table The characteristics list to validate
--- @return boolean valid True if at least one valid characteristic exists
function DTProject:_isValidTestCharacteristics(characteristics)
    local c = self:_ensureValidCharacteristics(self:GetTestCharacteristics())
    return #c > 0
end

--- Validates and filters a characteristics list to only valid entries
--- @param characteristics table Array of characteristic keys to validate
--- @return table validCharacteristics Filtered array containing only valid characteristic keys
function DTProject:_ensureValidCharacteristics(characteristics)
    local validList = {}

    if type(characteristics) ~= "table" then
        return validList
    end

    for _, char in ipairs(characteristics) do
        for _, validChar in pairs(DTConstants.CHARACTERISTICS) do
            if char == validChar.key then
                table.insert(validList, char)
                break
            end
        end
    end

    return validList
end
