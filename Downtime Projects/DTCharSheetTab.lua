--- Downtime character sheet tab for managing downtime activities and projects
--- Provides a dedicated interface for tracking downtime activities within the character sheet
--- @class DTCharSheetTab
--- @field _instance DTCharSheetTab The singleton instance of this class
DTCharSheetTab = RegisterGameType("DTCharSheetTab")

local mod = dmhub.GetModLoading()

--- The id is kept as it was: changing it would orphan the value every game has
--- already stored against it.
local playersManageProjects = setting{
	id = "permission:playersprojectrolls",
	description = "Players Manage Downtime Projects",
	editor = "check",
	default = false,

	storage = "game",
	section = "game",
	classes = {"dmonly"},
}

--- May the current user work the Director's controls on a downtime project -
--- status, milestones, adjustments, the event roll? True for the Director
--- always, and for a player only while the game hands it to them. Asked again
--- on every refresh, since the permission can be granted with a sheet open.
--- @return boolean
function DTCharSheetTab.CanManageProjects()
	return dmhub.isDM or playersManageProjects:Get()
end

--- Whether this game lets players roll from the project detail. The setting
--- alone, unlike CanManageProjects.
--- @return boolean
function DTCharSheetTab.RollingFromSheetEnabled()
	return playersManageProjects:Get()
end

function DTCharSheetTab.GetToken()
    if CharacterSheet.instance and CharacterSheet.instance.data and CharacterSheet.instance.data.info then
        return CharacterSheet.instance.data.info.token
    end
    return nil
end
local getToken = DTCharSheetTab.GetToken

function DTCharSheetTab.ModifyTokenProps(info)
    local token = DTCharSheetTab.GetToken()
    if token then
        token:ModifyProperties{
            description = info.description or "Update Character Downtime Info",
            undoable = false,
            execute = info.execute,
        }
    end
end
local modifyTokenProps = DTCharSheetTab.ModifyTokenProps

--- Creates the main downtime panel for the character sheet
--- @return table|nil panel The GUI panel containing downtime content
function DTCharSheetTab.CreateDowntimePanel()

    local downtimePanel = gui.Panel {
        id = "downtimeController",
        classes = {"downtimeController"},
        bgimage = true,
        bgcolor = "clear",
        width = "100%",
        height = "100%",
        flow = "vertical",
        valign = "top",
        halign = "center",
        styles = ThemeEngine.GetStyles(),
        data = {
            getDowntimeFollowers = function()
                local token = getToken()
                return token and token.properties:GetDowntimeFollowers()
            end,
            getDowntimeInfo = function()
                local token = getToken()
                return token and token.properties:GetDowntimeInfo()
            end,
        },

        refreshToken = function(element)
            local token = getToken()
            if token and token.properties and token.properties:IsHero() then
                local downtimeInfo = token.properties:GetDowntimeInfo()
                if not downtimeInfo:IsMigrated() then

                    local migratedRolls = {}
                    local followers = token.properties:try_get(DTConstants.FOLLOWERS_STORAGE_KEY)
                    if followers and type(followers) == "table" then
                        for followerId, _ in pairs(followers) do
                            local follower = dmhub.GetCharacterById(followerId)
                            if follower and follower.properties then
                                local legacyRolls = follower.properties:try_get(DTConstants.FOLLOWER_AVAILROLL_KEY)
                                if legacyRolls and legacyRolls > 0 then
                                    migratedRolls[followerId] = legacyRolls
                                end
                            end
                        end
                    end

                    modifyTokenProps{
                        execute = function()
                            downtimeInfo.followerRolls = migratedRolls
                        end
                    }
                end
            end
        end,

        deleteProject = function(element, projectId)
            if projectId and type(projectId) == "string" and #projectId then
                local downtimeInfo = element.data.getDowntimeInfo()
                if downtimeInfo then
                    modifyTokenProps{
                        execute = function()
                            downtimeInfo:RemoveProject(projectId)
                        end,
                    }
                    DTSettings.Touch()
                    element:FireEventTree("refreshToken")
                end
            end
        end,

        adjustRolls = function(element, amount, roller)
            DTProjectEditor.AdjustDowntimeRolls(getToken(), roller:GetTokenID(), amount)
            DTSettings.Touch()
            element:FireEventTree("refreshToken")
        end,

        DTCharSheetTab._createHeaderPanel(),
        DTCharSheetTab._createBodyPanel(),
    }

    -- The CharSheet system caches this panel for the session, so its `styles`
    -- array would be frozen at construction. Subscribe to ThemeEngine so the
    -- styles refresh whenever the active theme or scheme changes.
    ThemeEngine.OnThemeChanged(mod, function()
        if downtimePanel and downtimePanel.valid then
            downtimePanel.styles = ThemeEngine.GetStyles()
        end
    end)

    return downtimePanel
end

--- Creates the bar above the projects list
--- @return table panel The counters, and the button that adds a project
function DTCharSheetTab._createHeaderPanel()

    --How many downtime activities the hero has left to spend.
    --@return number
    local function HeroActivities()
        local token = getToken()
        if token == nil or token.properties == nil or not token.properties:IsHero() then
            return 0
        end

        local downtimeInfo = token.properties:GetDowntimeInfo()
        if downtimeInfo == nil then
            return 0
        end

        return downtimeInfo:GetAvailableRolls() or 0
    end

    --Every activity the hero's followers hold between them, as one number.
    --@return number
    local function FollowerActivities()
        local token = getToken()
        if token == nil or token.properties == nil or not token.properties:IsHero() then
            return 0
        end

        local followers = token.properties:GetDowntimeFollowers()
        if followers == nil then
            return 0
        end

        return followers:AggregateAvailableRolls() or 0
    end

    --A counter on the bar. Plain text in the ordinary colour: these are a
    --running total to glance at, not a status to react to.
    --@param caption string What the number counts
    --@param Count fun(): number Reads the number
    --@return Panel
    local function CounterLabel(caption, Count)
        return gui.Label {
            classes = {"sizeL"},
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            rmargin = 24,
            text = caption,

            --The document is not up yet when the sheet builds its panels, so
            --the monitor is attached once it is.
            create = function(element)
                element:FireEvent("refreshToken")
                dmhub.Schedule(0.2, function()
                    if element.valid then
                        element.monitorGame = DTSettings.GetDocumentPath()
                    end
                end)
            end,
            refreshGame = function(element)
                element:FireEvent("refreshToken")
            end,
            refreshToken = function(element)
                element.text = string.format("%s: %d", caption, Count())
            end,
        }
    end

    --Setting the counts is the Director's business, and a player's only when
    --the Director has handed it to them. Re-checked on every refresh, since the
    --permission can be granted while the sheet is open.
    local activitiesButton = gui.Button {
        classes = {"settingsButton", "sizeS", cond(not DTCharSheetTab.CanManageProjects(), "collapsed")},
        halign = "left",
        valign = "center",
        linger = function(element)
            gui.Tooltip("Set downtime activities for this hero and their followers")(element)
        end,
        refreshToken = function(element)
            element:SetClass("collapsed", not DTCharSheetTab.CanManageProjects())
        end,
        click = function()
            DTActivitiesDialog.ShowDialog(getToken())
        end,
    }

    local addButton = gui.Button {
        classes = {"addButton"},
        halign = "right",
        vmargin = 5,
        hmargin = 20,
        linger = function(element)
            gui.Tooltip("Add a new project")(element)
        end,
        click = function(element)
            local token = getToken()
            if token and token.properties and token.properties:IsHero() then
                local downtimeInfo = token.properties:GetDowntimeInfo()
                if downtimeInfo then
                    local newProjectId = dmhub.GenerateGuid()
                    modifyTokenProps{
                        execute = function()
                            downtimeInfo:AddProject(token.charid, newProjectId)
                        end
                    }
                    DTSettings.Touch()
                    local scrollArea = CharacterSheet.instance:Get("projectScrollArea")
                    if scrollArea then
                        scrollArea:FireEventTree("refreshToken")
                    end

                    -- Immediately prompt the user to choose a source for the new project
                    CharacterSheet.instance:AddChild(DTSelectItemDialog.CreateAsChild({
                        confirm = function(sourceType, selectedId)
                            local di = token.properties:GetDowntimeInfo()
                            local project = di and di:GetProject(newProjectId)
                            if project then
                                modifyTokenProps{
                                    execute = function()
                                        DTBusinessRules.ApplySourceToProject(project, sourceType, selectedId)
                                    end
                                }
                                local sa = CharacterSheet.instance:Get("projectScrollArea")
                                if sa then
                                    sa:FireEventTree("refreshToken")
                                end
                                dmhub.Schedule(0.1, function()
                                    DTSettings.Touch()
                                    DTShares.Touch()
                                end)
                            end
                        end,
                        cancel = function()
                            -- Custom / cancel: leave the new project empty for manual editing
                        end
                    }))
                end
            end
        end
    }

    return gui.Panel {
        classes = {"surfaceLinear"},
        width = "100%",
        height = 36,
        flow = "horizontal",
        halign = "center",
        valign = "center",
        -- Counters. They share one row rather than a column each, so the
        -- next ones to arrive line up beside these instead of resizing the
        -- bar around them.
        gui.Panel {
            width = "90%",
            height = "100%",
            flow = "horizontal",
            halign = "left",
            valign = "center",
            lmargin = 20,
            CounterLabel("Hero Available Activities", HeroActivities),
            CounterLabel("Follower Aggregate Activities", FollowerActivities),
            activitiesButton,
        },

        -- Add button
        gui.Panel {
            width = "10%",
            height = "100%",
            flow = "horizontal",
            halign = "right",
            valign = "center",
            addButton,
        },
    }
end

--- Creates the downtime projects panel
--- @return table panel The panel for managing downtime projects
function DTCharSheetTab._createBodyPanel()
    return gui.Panel {
        classes = {"surfaceRadial"},
        width = "100%",
        height = "100%-50",
        flow = "vertical",
        halign = "center",
        valign = "top",
        vmargin = 4,
        -- Scrollable projects area
        gui.Panel{
            width = "100%",
            height = "100%",
            valign = "top",
            vscroll = true,
            -- Inner auto-height container that pins content to top
            gui.Panel{
                id = "projectScrollArea",
                classes = {"projectListController"},
                width = "100%",
                height = "auto",
                flow = "vertical",
                halign = "center",
                valign = "top",
                create = function(element)
                    dmhub.Schedule(0.2, function()
                        element.monitorGame = DTShares.GetDocumentPath()
                    end)
                end,
                refreshGame = function(element)
                    element:FireEvent("refreshToken")
                end,
                refreshToken = function(element)
                    DTCharSheetTab._refreshProjectsList(element)
                end
            },
        },
    }
end

--- Refreshes the projects list display
--- Reconciles existing editor panels with current project list to avoid expensive panel recreation
--- @param element table The projects list container element
function DTCharSheetTab._refreshProjectsList(element)
    if CharacterSheet.instance.data.info == nil then return end
    local token = getToken()
    if not token or not token.properties or not token.properties:IsHero() then
        element.children = {}
        return
    end

    local sharedProjects = DTBusinessRules.GetSharedProjectsForRecipient(token.id)

    local downtimeInfo = token.properties:GetDowntimeInfo()
    if not downtimeInfo and #sharedProjects == 0 then
        element.children = {
            gui.Label {
                text = "(ERROR: unable to create downtime info)",
                classes = {"sizeL"},
                width = "100%",
                height = 40,
                textAlignment = "center",
                halign = "center",
                valign = "top",
            }
        }
        return
    end

    local projects
    if downtimeInfo then
        projects = downtimeInfo:GetSortedProjects()
        if (not projects or #projects == 0) and #sharedProjects == 0 then
            element.children = {
                gui.Label {
                    classes = {"sizeL"},
                    text = "No projects yet.\nClick the Add button to create one.",
                    width = "100%",
                    height = 40,
                    textAlignment = "center",
                    halign = "center",
                    valign = "top",
                }
            }
            return
        end
    end

    -- Reconcile existing panels with current projects
    local panels = element.children or {}

    -- Step 1: Remove panels for projects that no longer exist OR have wrong type
    for i = #panels, 1, -1 do
        local panel = panels[i]
        local isSharedPanel = panel:HasClass("sharedProject")
        local shouldRemove = true

        -- Check owned projects (should NOT be shared panel)
        for _, project in ipairs(projects) do
            if project:GetID() == panel.id then
                if not isSharedPanel then
                    shouldRemove = false
                end
                break
            end
        end

        -- If not matched in owned, check shared projects (MUST be shared panel)
        if shouldRemove then
            for _, entry in ipairs(sharedProjects) do
                if entry.project:GetID() == panel.id then
                    if isSharedPanel then
                        shouldRemove = false
                    end
                    break
                end
            end
        end

        if shouldRemove then
            table.remove(panels, i)
        end
    end

    -- Step 2: Add panels for new projects that don't have panels yet

    -- Add panels for owned projects
    for _, project in ipairs(projects) do
        local foundPanel = false
        for _, panel in ipairs(panels) do
            if panel.id == project:GetID() and not panel:HasClass("sharedProject") then
                panel:FireEvent("setProject", project)
                foundPanel = true
                break
            end
        end
        if not foundPanel then
            panels[#panels + 1] = DTProjectEditor.new{project = project}:CreateEditorPanel()
        end
    end

    -- Add panels for shared projects
    for _, entry in ipairs(sharedProjects) do
        if entry.project then
            local foundPanel = false
            for _, panel in ipairs(panels) do
                if panel.id == entry.project:GetID() and panel:HasClass("sharedProject") then
                    foundPanel = true
                    break
                end
            end
            if not foundPanel then
                panels[#panels + 1] = DTProjectEditor.new{project = entry.project}:CreateSharedProjectPanel(entry.ownerName, entry.ownerId, entry.ownerColor)
            end
        end
    end

    -- Step 3: Sort panels - owned projects first (by sort order), then shared projects (by sort order)
    local projectSortOrder = {}

    -- Add owned projects with their natural sort order
    for _, project in ipairs(projects) do
        projectSortOrder[project:GetID()] = project:GetSortOrder()
    end

    -- Add shared projects with offset to ensure they come after owned projects
    for _, entry in ipairs(sharedProjects) do
        -- Offset by 1000000 to ensure shared projects come after owned projects
        projectSortOrder[entry.project:GetID()] = 1000000 + entry.project:GetSortOrder()
    end

    table.sort(panels, function(a, b)
        local aOrder = projectSortOrder[a.id] or 999999
        local bOrder = projectSortOrder[b.id] or 999999
        return aOrder < bOrder
    end)

    element.children = panels
end
