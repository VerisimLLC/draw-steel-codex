--- General utility functions and styling configuration for downtime system
--- Provides data formatting, array operations, and centralized UI styles
--- @class DTHelpers
DTHelpers = RegisterGameType("DTHelpers")

-- Turn on the background to see lines around the downtime tab panels
local DEBUG_PANEL_BG = DTConstants.DEVUI and "panels/square.png" or nil

--- Return the owning token's uniuqe ID given a project id
--- @param projectId string The project to find the owner for
--- @return string ownerId The unique identifier for the owner
function DTHelpers.FindProjectOwner(projectId)
    local ownerId = ""

    local function tokenOwnsProject(token)
        local dtInfo = token.properties:GetDowntimeInfo()
        if dtInfo then
            local project = dtInfo:GetProject(projectId)
            if project then
                ownerId = token.charid
                return true
            end
        end
        return false
    end

    DTBusinessRules.IterateHeroTokens(tokenOwnsProject)

    return ownerId
end

--- Transform a flag list to the list of flags that are true
--- @param flagList table The flag list to transform
--- @return table list The list of keys
function DTHelpers.FlagListToList(flagList)
    local array = {}
    for key, value in pairs(flagList) do
        if value then
            array[#array + 1] = key
        end
    end
    return array
end

--- Formats any display name string with the specified user's color
--- @param displayName string The name to format (character name, follower name, or user name)
--- @param userId string The user ID to get color from
--- @return string coloredDisplayName The name with HTML color tags, or plain name if color unavailable
function DTHelpers.FormatNameWithUserColor(displayName, userId)
    if not displayName or #displayName == 0 then
        return "{unknown}"
    end

    if userId and #userId > 0 then
        local sessionInfo = dmhub.GetSessionInfo(userId)
        if sessionInfo and sessionInfo.displayColor and sessionInfo.displayColor.tostring then
            local colorCode = sessionInfo.displayColor.tostring
            return string.format("<color=%s>%s</color>", colorCode, displayName)
        end
    end

    -- Return plain name if no color available
    return displayName
end

--- Gets the standardized styling configuration for Quest Manager dialogs
--- Provides consistent styling across all Quest Manager UI components
--- @return table styles Array of GUI styles using DTBase inheritance pattern
function DTHelpers.GetDialogStyles()
    return {
        -- DTBase: Foundation style for all Quest Manager controls
        gui.Style{
            selectors = {"DTBase"},
            fontSize = 18,
            fontFace = "Berling",
            color = Styles.textColor,
            height = 24,
        },

        -- DT Dialog Windows
        gui.Style{
            selectors = {"DTDialog"},
            halign = "center",
            valign = "center",
            bgcolor = "#111111ff",
            borderWidth = 2,
            borderColor = Styles.textColor,
            bgimage = "panels/square.png",
            flow = "vertical",
            hpad = 20,
            vpad = 20,
        },

        -- Panels
        gui.Style{
            selectors = {"DTPanel", "DTBase"},
            height = "auto",
            hmargin = 2,
            vmargin = 2,
            hpad = 2,
            vpad = 2,
            flow = "horizontal",
            bgimage = DEBUG_PANEL_BG,
            border = DEBUG_PANEL_BG and 1 or 0,
        },
        gui.Style{
            selectors = {"DTPanelRow", "DTPanel", "DTBase"},
            vmargin = 4,
            height = 60,
            width = "100%-4",
            valign = "top",
        },
        gui.Style{
            selectors = {"DTPanelReadRow", "DTPanel", "DTBase"},
            vmargin = 2,
            height = 30,
            width = "100%-4",
            valign = "bottom",
        },

        -- DT Control Types: Inherit from DTBase, add specific properties
        gui.Style{
            selectors = {"DTLabel", "DTBase"},
            bold = true,
            textAlignment = "left",
            cornerRadius = 4,
        },
        gui.Style{
            selectors = {"DTInput", "DTBase"},
            bgcolor = Styles.backgroundColor,
            borderWidth = 1,
            borderColor = Styles.textColor,
            bold = false,
            cornerRadius = 4,
        },
        gui.Style{
            selectors = {"DTDropdown", "DTBase"},
            bgcolor = Styles.backgroundColor,
            borderWidth = 1,
            borderColor = Styles.textColor,
            height = 30,
            bold = false,
            cornerRadius = 4,
        },
        gui.Style{
            selectors = {"DTCheck", "DTBase"},
            halign = "left",
            cornerRadius = 4,
        },

        -- Buttons
        gui.Style{
            selectors = {"DTButton", "DTBase"},
            fontSize = 22,
            textAlignment = "center",
            bold = true,
            height = 35,
            cornerRadius = 4,
        },
        gui.Style{
            selectors = {"DTDanger", "DTButton", "DTBase"},
            bgcolor = "#220000",
            borderColor = "#440000",
        },
        gui.Style{
            selectors = {"DTDisabled", "DTButton", "DTBase"},
            bgcolor = "#222222",
            borderColor = "#444444",
        },
        gui.Style{
            selectors = {"downtime-edit-button"},
            width = 20,
            height = 20
        },

        -- Rolling status color classes
        gui.Style{
            selectors = {"DTStatusAvailable"},
            color = "#4CAF50"  -- Green for available/enabled
        },
        gui.Style{
            selectors = {"DTStatusPaused"},
            color = "#FF9800"  -- Orange for paused
        },

        -- Objective drag handle styles
        gui.Style{
            selectors = {"objective-drag-handle"},
            width = 24,
            height = 24,
            bgcolor = "#444444aa",
            bgimage = "panels/square.png",
            transitionTime = 0.2
        },
        gui.Style{
            selectors = {"objective-drag-handle", "hover"},
            bgcolor = "#666666cc"
        },
        gui.Style{
            selectors = {"objective-drag-handle", "dragging"},
            bgcolor = "#888888ff",
            opacity = 0.8
        },
        gui.Style{
            selectors = {"objective-drag-handle", "drag-target"},
            bgcolor = "#4CAF50aa"
        },

        -- Compact List Styles for efficient list views
        gui.Style {
            selectors = {"DTListBase"},
            fontSize = 12,
            bgimage = DEBUG_PANEL_BG,
            border = DEBUG_PANEL_BG and 1 or 0,
        },
        gui.Style {
            selectors = {"DTListRow", "DTListBase"},
            width = "98%",
            height = 45,
            pad = 2,
            flow = "horizontal",
            valign = "top",
            halign = "right",
            bgimage = "panels/square.png",
            border = { y1 = 1, y2 = 0, x1 = 0, x2 = 0 },
            borderColor = "#666666",
        },
        gui.Style {
            selectors = {"DTListDetail", "DTListBase"},
            width = 100,
            height = 45,
            valign = "top",
            flow = "vertical",
        },
        gui.Style {
            selectors = {"DTListHeader", "DTListBase"},
            width = "98%",
            margin = 2,
            height = 20,
            flow = "horizontal",
            valign = "top",
            fontSize = 14,
        },
        gui.Style {
            selectors = {"DTListTimestamp"},
            width = 120,
            hmargin = 2,
        },
        gui.Style {
            selectors = {"DTListAmount"},
            width = 25,
            hmargin = 2,
        },
        gui.Style {
            selectors = {"DTListAmountPositive"},
            color = "#4CAF50",
        },
        gui.Style {
            selectors = {"DTListAmountNegative"},
            color = "#F44336",
        },
        gui.Style {
            selectors = {"DTListDetail", "DTListBase"},
            width = "100%",
            valign = "top",
            height = 20,
            margin = 2,
            border = 1,
        },

        -- Multiselect chips
        gui.Style{
            selectors = {"DTChip", "hover"},
            bgcolor = "#330000",
            borderColor = "#990000",
        },
    }
end

--- Gets player display name with color formatting from user ID
--- @param userId string The user ID to look up
--- @return string coloredDisplayName The player's display name with HTML color tags, or "{unknown}" if not found
function DTHelpers.GetPlayerDisplayName(userId)
    if userId and #userId > 0 then
        local sessionInfo = dmhub.GetSessionInfo(userId)
        if sessionInfo and sessionInfo.displayName then
            return DTHelpers.FormatNameWithUserColor(sessionInfo.displayName, userId)
        end
    end

    return "{unknown}"
end

--- Returns whether the value passed is numeric by type or can be converted to a number
--- @param value any The value to check
--- @return boolean isNumeric Whether the value is a number
function DTHelpers.IsNumeric(value)
    return type(value) == "number" or tonumber(value) ~= nil
end

--- Compares two arrays to determine if they contain the same values
--- Handles both simple arrays and arrays of objects using reference equality
--- @param a1 table First array to compare
--- @param a2 table Second array to compare
--- @return boolean same True if arrays contain the same values, false otherwise
function DTHelpers.ListsHaveSameValues(a1, a2)
    -- Handle nil cases
    if not a1 and not a2 then return true end
    if not a1 or not a2 then return false end

    -- Convert to simple arrays (handle both keyed and simple arrays)
    local arr1 = {}
    local arr2 = {}
    for _, v in ipairs(a1) do arr1[#arr1 + 1] = v end
    for _, v in ipairs(a2) do arr2[#arr2 + 1] = v end

    -- Quick length check
    if #arr1 ~= #arr2 then return false end

    -- Build frequency map for arr1
    local freq = {}
    for _, v in ipairs(arr1) do
        freq[v] = (freq[v] or 0) + 1
    end

    -- Verify arr2 matches frequency map
    for _, v in ipairs(arr2) do
        if not freq[v] or freq[v] == 0 then
            return false
        end
        freq[v] = freq[v] - 1
    end

    return true
end

--- Compares two dictionaries to check if they have the same keys with truthy values
--- @param d1 table The first dictionary
--- @param d2 table The second dictionary
--- @return boolean equal Whether the dictionaries have the same truthy keys
function DTHelpers.DictsAreEqual(d1, d2)
    -- Handle nil cases
    if not d1 and not d2 then return true end
    if not d1 or not d2 then return false end

    -- Count truthy keys in d1 and verify they exist in d2
    local count1 = 0
    for k, v in pairs(d1) do
        if v then
            count1 = count1 + 1
            if not d2[k] then
                return false
            end
        end
    end

    -- Count truthy keys in d2
    local count2 = 0
    for k, v in pairs(d2) do
        if v then
            count2 = count2 + 1
        end
    end

    return count1 == count2
end

--- Transforms a list of DTConstant instances into a list of id, text pairs for dropdown lists
--- @param sourceList table The table containing DTConstant instances
--- @return table destList The transformed table, sorted by sortOrder
function DTHelpers.ListToDropdownOptions(sourceList)
    local destList = {}
    if sourceList and type(sourceList) == "table" and #sourceList > 0 then
        -- Sort DTConstant instances by sortOrder
        local sortedList = {}
        for _, constant in ipairs(sourceList) do
            sortedList[#sortedList + 1] = constant
        end
        table.sort(sortedList, function(a, b) return a.sortOrder < b.sortOrder end)

        -- Create dropdown options using displayText
        for _, constant in ipairs(sortedList) do
            destList[#destList+1] = { id = constant.key, text = constant.displayText}
        end
    end
    return destList
end

--- Transform the target to the source, returning true if we changed anything in the process
--- @param target table The destination array of strings
--- @param source table The source array of strings
--- @return boolean changed Whether we changed the destination array
function DTHelpers.SyncArrays(target, source)
    local changed = false

    -- Build a lookup table for fast checking
    local sourceSet = {}
    for _, str in ipairs(source) do
        sourceSet[str] = true
    end

    -- Remove items not in source
    for i = #target, 1, -1 do
        if not sourceSet[target[i]] then
            table.remove(target, i)
            changed = true
        end
    end

    -- Build lookup of current strings
    local targetSet = {}
    for _, str in ipairs(target) do
        targetSet[str] = true
    end

    -- Add items from source that aren't in target
    for _, str in ipairs(source) do
        if not targetSet[str] then
            target[#target + 1] = str
            changed = true
        end
    end

    return changed
end

--- Merge the source flag list into the target
--- @param target table The flag list to move source items into
--- @param source table The flag list to move into target
--- @param onlyTrue boolean|nil Whether to move only true values
--- @return table target The resulting merged list
function DTHelpers.MergeFlagLists(target, source, onlyTrue)
    for k,v in pairs(source) do
        if onlyTrue == nil or (onlyTrue and v == true) then
            target[k] = v
        end
    end
    return target
end
