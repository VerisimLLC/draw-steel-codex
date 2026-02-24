--- Downtime character sheet tab for managing downtime activities and projects
--- Provides a dedicated interface for tracking downtime activities within the character sheet
--- @class DTCharSheetTab
--- @field _instance DTCharSheetTab The singleton instance of this class
DTCharSheetTab = RegisterGameType("DTCharSheetTab")

local playersEditProjectRols = setting{
	id = "permission:playersprojectrolls",
	description = "Players Edit Project Rolls",
	editor = "check",
	default = false,

	storage = "game",
	section = "game",
	classes = {"dmonly"},
}

local CanEditProjectRolls = function()
	return dmhub.isDM or playersEditProjectRols:Get()
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
        classes = {"downtimeController", "DTPanel"},
        bgimage = true,
        bgcolor = "clear",
        width = "100%",
        height = "100%",
        flow = "vertical",
        valign = "top",
        halign = "center",
        borderColor = "purple",
        styles = DTHelpers.GetDialogStyles(),
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
            local token = getToken()
            local tokenId = token.id
            local rollerTokenId = roller:GetTokenID()
            local dtInfo = token.properties:GetDowntimeInfo()
            if dtInfo then
                token:ModifyProperties{
                    execute = function()
                        if rollerTokenId == tokenId then
                            dtInfo:GrantRolls(amount)
                        else
                            dtInfo:GrantFollowerRolls(rollerTokenId, amount)
                        end
                    end
                }
            end
            DTSettings.Touch()
            element:FireEventTree("refreshToken")
        end,

        children = {
            DTCharSheetTab._createHeaderPanel(),
            DTCharSheetTab._createBodyPanel(),
        }
    }

    return downtimePanel
end

--- Creates the available rolls display panel
--- @return table panel The panel showing available rolls count
function DTCharSheetTab._createHeaderPanel()

    local rollStatusGroup = gui.Panel {
        width = "100%",
        height = "100%",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        hmargin = 20,
        children = {
            gui.Label {
                text = "Rolling Status: ",
                classes = {"DTLabel", "DTBase"},
                width = "auto",
                height = "100%",
                hmargin = 2,
                fontSize = 20,
                halign = "left",
                valign = "center"
            },
            gui.Label {
                text = "CALCULATING...",
                classes = {"DTLabel", "DTBase"},
                width = "auto",
                hmargin = 2,
                height = "100%",
                fontSize = 20,
                halign = "left",
                valign = "center",
                interactable = CanEditProjectRolls(),
                create = function(element)
                    dmhub.Schedule(0.2, function()
                        element.monitorGame = DTSettings.GetDocumentPath()
                    end)
                end,
                refreshGame = function(element)
                    element:FireEvent("refreshToken")
                end,
                press = function(element)
                    local status
                    local settings = DTSettings.CreateNew()
                    if settings then
                        status = settings:GetPauseRolls()
                        settings:SetPauseRolls(not status)
                    end
                    element:FireEventTree("refreshToken")
                end,
                refreshToken = function(element)
                    local status = "UNKNOWN"
                    local settings = DTSettings.CreateNew()
                    if settings then
                        status = settings:GetPauseRolls() and "PAUSED" or "AVAILABLE"
                    end
                    element.text = status
                    element:SetClass("DTStatusAvailable", status == "AVAILABLE")
                    element:SetClass("DTStatusPaused", status ~= "AVAILABLE")
                end
            },
            gui.Label {
                text = "",
                classes = {"DTLabel", "DTBase"},
                width = "auto",
                height = "100%",
                fontSize = 20,
                halign = "left",
                valign = "center",
                bold = false,
                create = function(element)
                    dmhub.Schedule(0.2, function()
                        element.monitorGame = DTSettings.GetDocumentPath()
                    end)
                end,
                refreshGame = function(element)
                    element:FireEvent("refreshToken")
                end,
                refreshToken = function(element)
                    local reason = ""
                    local settings = DTSettings.CreateNew()
                    if settings then
                        if settings:GetPauseRolls() then
                            reason = "(<i>" .. settings:GetPauseRollsReason() .. "</i>)"
                        end
                    end
                    element.text = reason
                end
            },
            gui.Label {
                classes = {"DTLabel", "DTBase", "DTHelpHover"},
                bold = true,
                text = "?",
                create = function(element)
                    dmhub.Schedule(0.2, function()
                        element.monitorGame = DTSettings.GetDocumentPath()
                    end)
                end,
                linger = function(element)
                    gui.Tooltip{
                        maxWidth = 300,
                        fontSize = 16,
                        bgimage = true,
                        bgcolor = "#663100",
                        text = "Your Director can enable rolling by opening Panels -> Downtime Projects, then clicking the gear button.",
                    }(element)
                end,
                refreshGame = function(element)
                    element:FireEvent("refreshToken")
                end,
                refreshToken = function(element)
                    local visible = false
                    local settings = DTSettings.CreateNew()
                    if settings then
                        visible = settings:GetPauseRolls()
                    end
                    element:SetClass("collapsed", not visible)
                end,
            },
        }
    }

    local availableRollsGroup = gui.Panel {
        width = "100%",
        height = "100%",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        data = {
            availableRolls = 0,
            message = "",
        },
        create = function(element)
            dmhub.Schedule(0.2, function()
                element.monitorGame = DTSettings.GetDocumentPath()
            end)
        end,
        refreshGame = function(element)
            element:FireEventTree("refreshToken")
        end,
        refreshToken = function(element)
            local fmt = "%d%s"
            local msg = ""
            element.data.availableRolls = 0
            if CharacterSheet.instance.data.info then
                local token = CharacterSheet.instance.data.info.token
                if token and token.properties and token.properties:IsHero() then
                    local downtimeInfo = token.properties:GetDowntimeInfo()
                    if downtimeInfo then
                        element.data.availableRolls = downtimeInfo:GetAvailableRolls()
                    else
                        msg = " (Can't get downtime info)"
                    end
                else
                    msg = " (Not a Hero)"
                end
                element.data.message = string.format(fmt, element.data.availableRolls, msg)
                element:SetClass("DTStatusAvailable", element.data.availableRolls > 0)
                element:SetClass("DTStatusPaused", element.data.availableRolls <= 0)
            end
        end,
        children = {
            gui.Label {
                text = "Available Rolls: ",
                classes = {"DTLabel", "DTBase"},
                width = "auto",
                height = "100%",
                hmargin = 2,
                fontSize = 20,
                halign = "left",
                valign = "center"
            },
            gui.Label {
                text = "CALCULATING...",
                classes = {"DTLabel", "DTBase"},
                width = "auto",
                height = "100%",
                halign = "left",
                valign = "center",
                editable = CanEditProjectRolls(),
                hmargin = 2,
                fontSize = 20,
                refreshToken = function(element)
                    local availableRolls = element.parent.data.availableRolls
                    element.text = element.parent.data.message
                    element:SetClass("DTStatusAvailable", availableRolls > 0)
                    element:SetClass("DTStatusPaused", availableRolls <= 0)
                end,
                change = function(element)
                    if tonumber(element.text) then
                        local token = getToken()
                        local downtimeInfo = token and token.properties:GetDowntimeInfo()
                        if downtimeInfo then
                            modifyTokenProps{
                                execute = function ()
                                    downtimeInfo.availableRolls = tonumber(element.text)
                                end,
                            }
                            element:FireEventTree("refreshToken")
                        end
                    end
                end,
            },
            gui.Label {
                classes = {"DTLabel", "DTBase", "DTHelpHover"},
                bold = true,
                text = "?",
                linger = function(element)
                    gui.Tooltip{
                        maxWidth = 300,
                        fontSize = 16,
                        bgimage = true,
                        bgcolor = "#663100",
                        text = "Your Director can grant rolls by opening Panels -> Downtime Projects, then clicking the dice button.",
                    }(element)
                end,
                refreshToken = function(element)
                    local visible = element.parent.data.availableRolls == 0
                    element:SetClass("collapsed", not visible)
                end,
            },
        }
    }

    local followerRollsGroup = gui.Panel {
        width = "100%",
        height = "100%",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        children = {
            gui.Label {
                text = "Follower Rolls: ",
                classes = {"DTLabel", "DTBase"},
                width = "auto",
                height = "100%",
                hmargin = 2,
                fontSize = 20,
                halign = "left",
                valign = "center"
            },
            gui.Label {
                text = "CALCULATING...",
                classes = {"DTLabel", "DTBase"},
                width = "auto",
                height = "100%",
                halign = "left",
                valign = "center",
                hmargin = 2,
                fontSize = 20,
                create = function(element)
                    dmhub.Schedule(0.2, function()
                        element.monitorGame = DTSettings.GetDocumentPath()
                    end)
                end,
                refreshGame = function(element)
                    element:FireEvent("refreshToken")
                end,
                refreshToken = function(element)
                    local fmt = "%d%s"
                    local availableRolls = 0
                    local msg = ""
                    if CharacterSheet.instance.data.info then
                        local token = CharacterSheet.instance.data.info.token
                        if token and token.properties and token.properties:IsHero() then
                            local downtimeInfo = token.properties:GetDowntimeInfo()
                            if downtimeInfo then
                                availableRolls = downtimeInfo:AggregateFollowerRolls()
                            else
                                msg = " (Can't get follower rolls)"
                            end
                        else
                            msg = " (Not a Hero)"
                        end
                        element.text = string.format(fmt, availableRolls, msg)
                        element:SetClass("DTStatusAvailable", availableRolls > 0)
                        element:SetClass("DTStatusPaused", availableRolls <= 0)
                    end
                end
            }
        }
    }

    local addButton = gui.AddButton {
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
                    modifyTokenProps{
                        execute = function()
                            downtimeInfo:AddProject(token.charid)
                        end
                    }
                    DTSettings.Touch()
                    local scrollArea = CharacterSheet.instance:Get("projectScrollArea")
                    if scrollArea then
                        scrollArea:FireEventTree("refreshToken")
                    end
                end
            end
        end
    }

    return gui.Panel {
        width = "100%",
        height = 40,
        flow = "horizontal",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#2a2a2a",
        border = { y1 = 1, y2 = 0, x1 = 0, x2 = 0 },
        borderColor = "white",
        children = {
            -- Roll Status
            gui.Panel {
                width = "30%",
                height = "100%",
                flow = "horizontal",
                halign = "left",
                valign = "center",
                children = {
                    rollStatusGroup
                }
            },

            -- Available Rolls
            gui.Panel {
                width = "30%",
                height = "100%",
                flow = "horizontal",
                halign = "left",
                valign = "center",
                children = {
                    availableRollsGroup
                },
            },

            -- Follower Rolls
            gui.Panel {
                width = "30%",
                height = "100%",
                flow = "horizontal",
                halign = "left",
                valign = "center",
                children = {
                    followerRollsGroup
                },
            },

            -- Add button
            gui.Panel {
                width = "10%",
                height = "100%",
                flow = "horizontal",
                halign = "right",
                valign = "center",
                children = {
                    addButton
                }
            }
        }
    }
end

--- Creates the downtime projects panel
--- @return table panel The panel for managing downtime projects
function DTCharSheetTab._createBodyPanel()
    return gui.Panel {
        width = "100%",
        height = "100%-50",
        flow = "vertical",
        halign = "center",
        valign = "top",
        vmargin = 10,
        children = {
            -- Scrollable projects area
            gui.Panel{
                width = "100%",
                height = "100%",
                valign = "top",
                vscroll = true,
                styles = DTHelpers.GetDialogStyles(),
                children = {
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
                    }
                }
            }
        }
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
                classes = {"DTLabel", "DTBase"},
                width = "100%",
                height = 40,
                textAlignment = "center",
                halign = "center",
                valign = "top"
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
                    text = "No projects yet.\nClick the Add button to create one.",
                    classes = {"DTLabel", "DTBase"},
                    width = "100%",
                    height = 40,
                    textAlignment = "center",
                    halign = "center",
                    valign = "top"
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
