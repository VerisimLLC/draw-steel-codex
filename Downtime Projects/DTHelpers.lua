--- General utility functions and styling configuration for downtime system
--- Provides data formatting, array operations, and centralized UI styles
--- @class DTHelpers
DTHelpers = RegisterGameType("DTHelpers")

-- Turn on the background to see lines around the downtime tab panels
local DEBUG_PANEL_BG = DTConstants.DEVUI and "panels/square.png" or nil

--- Find a token given a creature object
--- @param creature creature
--- @return CharacterToken|nil
function DTHelpers.GetTokenFromCreature(creature)
    local token = dmhub.LookupToken(creature)
    if token ~= nil then return token end

    -- TODO: Is there a better way to find them when their
    -- token is not on the map?
    local allTokens = table.values(game.GetGameGlobalCharacters())
    for _,token in ipairs(allTokens) do
        if dmhub.DeepEqual(token.properties, creature) then
            return token
        end
    end

    return nil
end

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

        -- Help hover targets
        gui.Style{
            selectors = {"DTLabel", "DTBase", "DTHelpHover"},
            height = 20,
            width = 20,
            fontSize = 20,
            halign= "left",
            valign = "center",
            hmargin = 4,
            bgimage = true,
            borderColor = "#FF9800",
            color = "#FF9800",
            border = 1,
            textAlignment = "center",
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
            print("TYPE::", constant.typeName, constant.sortOrder)
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
