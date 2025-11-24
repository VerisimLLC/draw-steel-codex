local mod = dmhub.GetModLoading()

-- Triangle icon styles for character expand/collapse (based on QuestTrackerPanel pattern)
local characterTriangleStyles = {
    gui.Style{
        selectors = {"character-triangle"},
        bgimage = "panels/triangle.png",
        bgcolor = "white",
        hmargin = 4,
        halign = "left",
        valign = "center",
        height = 12,
        width = 12,
        rotate = 90,
    },
    gui.Style{
        selectors = {"character-triangle", "expanded"},
        rotate = 0,
        transitionTime = 0.2,
    },
    gui.Style{
        selectors = {"character-triangle", "hover"},
        bgcolor = "yellow",
    },
    gui.Style{
        selectors = {"character-triangle", "press"},
        bgcolor = "gray",
    },
}

--- Downtime Director Panel - Main dockable panel for downtime project management
--- Provides the primary interface for directors to manage downtime projects and settings
--- @class DTDirectorPanel
--- @field downtimeSettings DTSettings The downtime settings for shared data management
DTDirectorPanel = RegisterGameType("DTDirectorPanel")
DTDirectorPanel.__index = DTDirectorPanel

--- Clean toggle-style tab styles (no backgrounds, borders, or lines)
DTDirectorPanel.TabsStyles = {
    gui.Style{
        selectors = {"dtTabContainer"},
        height = 24,
        width = "100%",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        hmargin = 5,
    },
    gui.Style{
        selectors = {"dtTab"},
        fontFace = "Berling",
        bold = false,
        valign = "center",
        halign = "center",
        hpad = 6,
        vpad = 4,
        width = 75,
        height = "100%",
        hmargin = 8,
        bgimage = "panels/square.png",
        borderColor = Styles.textColor,
        border = { y1 = 0, y2 = 0, x1 = 0, x2 = 0 },
        color = "#666666",
        textAlignment = "center",
        fontSize = 12,
        transitionTime = 0.2,
    },
    gui.Style{
        selectors = {"dtTab", "hover"},
        color = "#aaaaaa",
        borderColor = "#aaaaaa",
        border = { y1 = 1, y2 = 0, x1 = 0, x2 = 0 },
        transitionTime = 0.2,
    },
    gui.Style{
        selectors = {"dtTab", "important"},
        color = "orange"
    },
    gui.Style{
        selectors = {"dtTab", "selected"},
        color = "#ffffff",
        border = { y1 = 1, y2 = 0, x1 = 0, x2 = 0 },
        borderColor = "#ffffff",
        bold = true,
        fontSize = 12,
        transitionTime = 0.2,
    },
}

--- Creates a new Downtime Director Panel instance
--- @param downtimeSettings DTSettings The downtime settings instance for shared data management
--- @return DTDirectorPanel|nil instance The new panel instance
function DTDirectorPanel:new(downtimeSettings)
    if not downtimeSettings then return nil end

    local instance = setmetatable({}, self)
    instance.downtimeSettings = downtimeSettings

    return instance
end

--- Registers the dockable panel with the Codex UI system
--- Creates and configures the main downtime director interface
function DTDirectorPanel:Register()
    local directorPanel = self
    DockablePanel.Register {
        name = "Downtime Projects",
        icon = mod.images.downtimeProjects,
        minHeight = 100,
        maxHeight = 600,
        content = function()
            local panel = directorPanel:_buildMainPanel()
            directorPanel.panelElement = panel
            return panel
        end
    }
end

--- Builds the main panel structure for the downtime director
--- @return table panel The main GUI panel containing all downtime director elements
function DTDirectorPanel:_buildMainPanel()
    local directorPanel = self
    return gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",
        monitorGame = directorPanel.downtimeSettings.GetDocumentPath(),
        refreshGame = function(element)
            directorPanel:_refreshPanelContent(element)
        end,
        children = {
            self:_buildHeaderPanel(),
            self:_buildContentPanel()
        }
    }
end

--- Builds the header panel containing title and settings summary
--- @return table panel The header panel with title and settings summary
function DTDirectorPanel:_buildHeaderPanel()
    local isPaused = self.downtimeSettings:GetPauseRolls()
    local pauseReason = self.downtimeSettings:GetPauseRollsReason()

    local statusText = string.format("Rolling: %s", isPaused and "Paused" or "Enabled")

    return gui.Panel {
        width = "100%",
        height = "40",
        flow = "horizontal",
        halign = "left",
        valign = "center",
        styles = DTHelpers.GetDialogStyles(),
        children = {
            -- Settings panel - edit button & state
            gui.Panel {
                width = "50%",
                height = "100%",
                flow = "horizontal",
                halign = "left",
                valign = "center",
                children = {
                    gui.SettingsButton {
                        width = 20,
                        height = 20,
                        halign = "right",
                        valign = "center",
                        hmargin = 5,
                        classes = {"downtime-edit-button"},
                        linger = function(element)
                            gui.Tooltip("Edit downtime settings")(element)
                        end,
                        press = function()
                            self:_showSettingsDialog()
                        end
                    },
                    gui.Panel {
                        width = "100%-20",
                        height = "100%",
                        flow = "vertical",
                        halign = "left",
                        valign = "center",
                        children = {
                            gui.Label {
                                text = statusText,
                                classes = {"DTLabel", "DTBase"},
                                width = "auto",
                                height = "auto",
                                halign = "left",
                                valign = "center"
                            },
                            gui.Label {
                                text = pauseReason,
                                classes = {"DTLabel", "DTBase", (not isPaused) and "collapsed" or nil},
                                fontSize = 12,
                                width = "auto",
                                height = "auto",
                                halign = "left",
                                valign = "center"
                            }
                        },
                    },
                }
            },
            -- Buttons panel - Grant rolls
            gui.Panel{
                width = "50%",
                height = "100%",
                flow = "horizontal",
                halign = "right",
                valign = "center",
                children = {
                    gui.EnhIconButton {
                        bgimage = "panels/initiative/initiative-dice.png",
                        width = "30",
                        height = "30",
                        halign = "right",
                        valign = "center",
                        hmargin = 5,
                        borderWidth = 0,
                        hoverColor = "#00cccc",
                        pressColor = "#00aaaa",
                        linger = function(element)
                            gui.Tooltip("Grant rolls to characters")(element)
                        end,
                        click = function()
                            DTGrantRollsDialog:new():ShowDialog()
                        end,
                    },
                }
            },
        }
    }
end

--- Shows the settings edit dialog for downtime configuration
--- Allows editing pause rolls setting and reason
function DTDirectorPanel:_showSettingsDialog()
    local isPaused = self.downtimeSettings:GetPauseRolls()
    local pauseReason = self.downtimeSettings:GetPauseRollsReason()

    local settingsDialog = gui.Panel{
        classes = {"dtSettingsController", "DTDialog"},
        width = 500,
        height = 300,
        styles = DTHelpers.GetDialogStyles(),

        saveAndClose = function(element)
            local chkPause = element:Get("chkPauseRolls")
            local txtReason = element:Get("txtPauseReason")
            if chkPause and txtReason then
                self.downtimeSettings:SetData(chkPause.value, txtReason.text)
                gui.CloseModal()
            end
        end,

        validateForm = function(element)
            local enabled = false
            local chkPause = element:Get("chkPauseRolls")
            if chkPause and not chkPause.value then
                enabled = true
            else
                local txtReason = element:Get("txtPauseReason")
                enabled = (txtReason and txtReason.text) and #txtReason.text > 0
            end
            element:FireEventTree("enableConfirm", enabled)
        end,

        create = function(element)
            element:FireEvent("validateForm")
        end,

        escape = function(element)
            gui.CloseModal()
        end,

        children = {
            gui.Label{
                text = "Edit Downtime Settings",
                width = "100%",
                height = 30,
                fontSize = "24",
                classes = {"DTLabel", "DTBase"},
                textAlignment = "center",
                halign = "center",
                valign = "top",
            },
            gui.Divider { width = "50%" },

            -- Content
            gui.Panel {
                classes = {"DTPanel", "DTBase"},
                height = "100%-124",
                width = "98%",
                valign="top",
                flow = "vertical",
                borderColor = "red",
                children = {
                    gui.Panel {
                        classes = {"DTPanelRow", "DTPanel", "DTBase"},
                        width = "98%",
                        borderColor = "blue",
                        children = {
                            DTUIComponents.CreateLabeledCheckbox({
                                id = "chkPauseRolls",
                                text = "Pause Rolls",
                                value = isPaused,
                                change = function(element)
                                    local controller = element:FindParentWithClass("dtSettingsController")
                                    if controller then
                                        controller:FireEvent("validateForm")
                                    end
                                end
                            }, {
                                halign = "left",
                                height = "auto",
                            }),
                        }
                    },

                    gui.Panel {
                        classes = {"DTPanelRow", "DTPanel", "DTBase"},
                        width = "98%",
                        borderColor = "blue",
                        children = {
                            DTUIComponents.CreateLabeledInput("Pause Reason", {
                                id = "txtPauseReason",
                                text = pauseReason,
                                placeholderText = "Enter reason for pausing rolls...",
                                lineType = "Single",
                                editlag = 0.5,
                                change = function(element)
                                    element:FireEvent("edit")
                                end,
                                edit = function(element)
                                    local controller = element:FindParentWithClass("dtSettingsController")
                                    if controller then
                                        controller:FireEvent("validateForm")
                                    end
                                end,
                            }, {}),
                        }
                    }
                }
            },

            -- Footer
            gui.Panel{
                classes = {"DTPanel", "DTBase"},
                width = "100%",
                height = 40,
                vmargin = 10,
                halign = "center",
                valign = "bottom",
                flow = "horizontal",
                borderColor = "red",
                children = {
                    -- Cancel button
                    gui.Button{
                        text = "Cancel",
                        width = 120,
                        valign = "bottom",
                        classes = {"DTButton", "DTBase"},
                        click = function(element)
                            gui.CloseModal()
                        end
                    },
                    -- Confirm button
                    gui.Button{
                        text = "Confirm",
                        width = 120,
                        valign = "bottom",
                        classes = {"DTButton", "DTBase", "DTDisabled"},
                        interactable = false,
                        enableConfirm = function(element, enabled)
                            element:SetClass("DTDisabled", not enabled)
                            element.interactable = enabled
                        end,
                        click = function(element)
                            if not element.interactable then return end
                            local controller = element:FindParentWithClass("dtSettingsController")
                            if controller then
                                controller:FireEvent("saveAndClose")
                            end
                        end
                    }
                }
            }
        },
    }

    gui.ShowModal(settingsDialog)
end

--- Gets all hero characters in the game that have downtime projects
--- @return table tokenInfo Array of {id, name} objects for characters with downtime projects
function DTDirectorPanel:_getAllCharactersWithDowntimeProjects()
    local tokenInfo = {}

    -- Local validation function to check if character meets criteria
    local function isHeroWithDowntimeProjects(token)
        if token and token.properties and token.properties:IsHero() then
            local dti = token.properties:GetDowntimeInfo()
            if dti then
                local projects = dti:GetProjects()
                if projects and next(projects) then return true end
            end
        end
        return false
    end

    local allHeroes = DTBusinessRules.GetAllHeroTokens(isHeroWithDowntimeProjects)
    for _, token in ipairs(allHeroes) do
        local downtimeInfo = token.properties:GetDowntimeInfo()
        local rolls = downtimeInfo ~= nil and downtimeInfo:GetAvailableRolls() or 0
        tokenInfo[#tokenInfo + 1] = {
            id = token.id,
            name = token.name or "Unknown Hero",
            rolls = rolls,
        }
    end

    return tokenInfo
end

--- Categorizes downtime projects into 4 status-based buckets for tab display
--- @return table categorizedProjects Object with attention, milestones, active, completed arrays
function DTDirectorPanel:_categorizeDowntimeProjects()
    local characterInfoList = self:_getAllCharactersWithDowntimeProjects()

    local categorized = {
        attention = {},   -- PAUSED projects
        milestones = {},  -- MILESTONE projects
        active = {},      -- ACTIVE and other projects
        completed = {}    -- COMPLETE projects
    }

    for _, characterInfo in ipairs(characterInfoList) do
        local token = dmhub.GetCharacterById(characterInfo.id)
        if token and token.properties then
            local characterId = characterInfo.id
            local characterName = characterInfo.name

            local downtimeInfo = token.properties:GetDowntimeInfo()
            if downtimeInfo then
                local projects = downtimeInfo:GetProjects()

                for _, project in pairs(projects) do
                    local projectEntry = {
                        characterId = characterId,
                        characterName = characterName,
                        characterRolls = characterInfo.rolls,
                        projectId = project:GetID(),
                        projectTitle = project:GetTitle(),
                        progress = project:GetProgress(),
                        goal = project:GetProjectGoal(),
                        milestoneThreshold = project:GetMilestoneThreshold(),
                        pauseRollsReason = project:GetStatusReason(),
                    }

                    local status = project:GetStatus()
                    if status == DTConstants.STATUS.PAUSED.key then
                        categorized.attention[#categorized.attention + 1] = projectEntry
                    elseif status == DTConstants.STATUS.MILESTONE.key then
                        categorized.milestones[#categorized.milestones + 1] = projectEntry
                    elseif status == DTConstants.STATUS.COMPLETE.key then
                        categorized.completed[#categorized.completed + 1] = projectEntry
                    else -- ACTIVE or any other status goes to active
                        categorized.active[#categorized.active + 1] = projectEntry
                    end
                end
            end
        end
    end

    return categorized
end

--- Builds a character header with token, names, triangle, and settings button
--- @param characterInfo table Object with {id, name} for the character
--- @param contentPanel table The content panel this header will toggle
--- @param tabType string The tab type for preference key
--- @return table panel The character header panel
function DTDirectorPanel:_buildCharacterHeader(characterInfo, contentPanel, tabType)
    local characterId = characterInfo.id
    local characterName = characterInfo.name
    local prefKey = string.format("dt_char_expanded:%s:%s:%s", tabType, characterId, dmhub.gameid or "default")
    local isExpanded = dmhub.GetPref(prefKey) or false

    -- Get token for display
    local token = dmhub.GetCharacterById(characterId)

    -- Build player name with color if available
    local playerDisplay = ""
    if token and token.playerNameOrNil then
        local color = token.playerColor.tostring
        playerDisplay = string.format(" (<color=%s>%s</color>) [Rolls: %d]", color, token.playerNameOrNil, characterInfo.rolls)
    end

    local triangle = gui.Panel{
        classes = {"character-triangle", isExpanded and "expanded" or nil},
        styles = characterTriangleStyles,
        click = function(element)
            local isExpanded = not element:HasClass("expanded")
            element:SetClass("expanded", isExpanded)
            if contentPanel then
                contentPanel:SetClass("collapsed", not isExpanded)
            end
            dmhub.SetPref(prefKey, isExpanded)
        end
    }

    return gui.Panel{
        width = "98%",
        height = 30,
        flow = "horizontal",
        classes = {"character-header"},
        children = {
            triangle,
            -- Character token
            gui.Panel {
                width = 20,
                height = 20,
                valign = "center",
                hmargin = 4,
                borderWidth = 1,
                borderColor = Styles.textColor,
                children = token and {
                    gui.CreateTokenImage(token, {
                        width = 24,
                        height = 24,
                        halign = "center",
                        valign = "center",
                        refresh = function(element)
                            if token == nil or not token.valid then return end
                            element:FireEventTree("token", token)
                        end,
                    })
                } or {}
            },
            -- Character name + player name
            gui.Label{
                text = characterName .. playerDisplay,
                classes = {"DTLabel", "DTBase"},
                width = "70%",
                height = "100%",
                valign = "center",
                hmargin = 4,
                fontSize = 14
            },
            -- Settings button (right-aligned)
            gui.Panel{
                width = "30",
                height = "100%",
                flow = "horizontal",
                halign = "right",
                valign = "center",
                children = {
                    gui.SettingsButton {
                        width = 20,
                        height = 20,
                        halign = "right",
                        valign = "center",
                        hmargin = 5,
                        classes = {"character-edit-button"},
                        linger = function(element)
                            gui.Tooltip("Open character sheet")(element)
                        end,
                        press = function()
                            local character = dmhub.GetCharacterById(characterId)
                            if character then
                                character:ShowSheet("Downtime")
                            end
                        end
                    }
                }
            }
        }
    }
end

--- Builds a project detail display with tab-specific fields
--- @param projectEntry table The project entry from categorized data
--- @param tabType string The tab type ("attention", "milestones", etc.)
--- @return table panel The project detail panel
function DTDirectorPanel:_buildProjectDetail(projectEntry, tabType)
    local projectTitle = (projectEntry.projectTitle and #projectEntry.projectTitle > 0) and projectEntry.projectTitle or "Untitled Project"
    local progress = projectEntry.progress or 0
    local goal = projectEntry.goal or 1
    local progressText = string.format("%d / %d", progress, goal)

    -- Build detail parts array
    local detailParts = {projectTitle, progressText}

    -- Add tab-specific field
    if tabType == "attention" and projectEntry.pauseRollsReason and projectEntry.pauseRollsReason ~= "" then
        detailParts[#detailParts + 1] = projectEntry.pauseRollsReason
    elseif tabType == "milestones" and projectEntry.milestoneThreshold and projectEntry.milestoneThreshold > 0 then
        detailParts[#detailParts + 1] = string.format("Milestone: %d", projectEntry.milestoneThreshold)
    end

    -- Join with pipes, making title bold
    local displayText = ""
    for i, part in ipairs(detailParts) do
        if i == 1 then
            displayText = string.format("<b>%s</b>", part)
        else
            displayText = displayText .. " | " .. part
        end
    end

    return gui.Panel{
        width = "100%",
        height = 25,
        flow = "horizontal",
        classes = {"project-detail"},
        children = {
            gui.Label{
                text = displayText,
                classes = {"DTLabel", "DTBase"},
                width = "100%",
                height = "100%",
                valign = "center",
                hmargin = 20,
                fontSize = 12,
                wrap = true
            }
        }
    }
end

--- Builds a complete character section with expand/collapse
--- @param characterInfo table Object with {id, name} for the character
--- @param characterProjects table Array of project entries for this character
--- @param tabType string The tab type ("attention", "milestones", etc.)
--- @return table panel The complete character section
function DTDirectorPanel:_buildCharacterSection(characterInfo, characterProjects, tabType)
    -- Build project children
    local projectChildren = {}
    for i, projectEntry in ipairs(characterProjects) do
        -- Add divider before project (except first one)
        if i > 1 then
            projectChildren[#projectChildren + 1] = gui.Divider { width = "90%" }
        end
        projectChildren[#projectChildren + 1] = self:_buildProjectDetail(projectEntry, tabType)
    end

    -- Check collapse state from preferences
    local characterId = characterInfo.id
    local prefKey = string.format("dt_char_expanded:%s:%s:%s", tabType, characterId, dmhub.gameid or "default")
    local isExpanded = dmhub.GetPref(prefKey) or false

    -- Build content panel with conditional collapsed class
    local classes = {"character-content"}
    if not isExpanded then
        table.insert(classes, "collapsed")
    end

    local contentPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        classes = classes,
        children = projectChildren
    }

    -- Build header with reference to content panel
    local headerPanel = self:_buildCharacterHeader(characterInfo, contentPanel, tabType)

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        classes = {"character-section"},
        children = {
            headerPanel,
            contentPanel
        }
    }
end

--- Builds tab content that groups projects by character
--- @param categorizedProjects table Array of project entries for this tab
--- @param tabType string The tab type ("attention", "milestones", etc.)
--- @return table panel The tab content panel
function DTDirectorPanel:_buildTabContent(categorizedProjects, tabType)
    local tabChildren = {}

    if #categorizedProjects == 0 then
        tabChildren[#tabChildren + 1] = gui.Label {
            text = "No projects in this category.",
            classes = {"DTLabel", "DTBase"},
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "top",
            textAlignment = "center",
            fontSize = 14
        }
    else
        -- Group projects by character
        local projectsByCharacter = {}
        for _, projectEntry in ipairs(categorizedProjects) do
            local charId = projectEntry.characterId
            if not projectsByCharacter[charId] then
                projectsByCharacter[charId] = {
                    characterInfo = {
                        id = charId,
                        name = projectEntry.characterName,
                        rolls = projectEntry.characterRolls
                    },
                    projects = {}
                }
            end
            table.insert(projectsByCharacter[charId].projects, projectEntry)
        end

        -- Build character sections
        local hasCharacters = false
        for _, characterData in pairs(projectsByCharacter) do
            if hasCharacters then
                -- Add spacing between characters
                tabChildren[#tabChildren + 1] = gui.Divider { width = "95%" }
            end
            tabChildren[#tabChildren + 1] = self:_buildCharacterSection(
                characterData.characterInfo,
                characterData.projects,
                tabType
            )
            hasCharacters = true
        end
    end

    return gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",
        styles = self:_getTabContentStyles(),
        children = tabChildren
    }
end

--- Builds the main content panel with tabs
--- @return table panel The tabbed content panel
function DTDirectorPanel:_buildContentPanel()
    local directorPanel = self

    -- Get categorized data for tab content
    local categorized = directorPanel:_categorizeDowntimeProjects()

    -- Get preferred selected tab
    local prefKey = string.format("dt_director_selected_tab:%s", dmhub.gameid or "default")
    local selectedTab = dmhub.GetPref(prefKey) or "Attention"

    -- Validate selected tab (fallback to Attention if invalid)
    local validTabs = {"Attention", "Milestones", "Active", "Completed"}
    local isValidTab = false
    for _, validTab in ipairs(validTabs) do
        if selectedTab == validTab then
            isValidTab = true
            break
        end
    end
    if not isValidTab then
        selectedTab = "Attention"
    end

    -- Create content panels for each tab
    local attentionPanel = directorPanel:_buildTabContent(categorized.attention, "attention")
    attentionPanel:SetClass("hidden", selectedTab ~= "Attention")

    local milestonesPanel = directorPanel:_buildTabContent(categorized.milestones, "milestones")
    milestonesPanel:SetClass("hidden", selectedTab ~= "Milestones")

    local activePanel = directorPanel:_buildTabContent(categorized.active, "active")
    activePanel:SetClass("hidden", selectedTab ~= "Active")

    local completedPanel = directorPanel:_buildTabContent(categorized.completed, "completed")
    completedPanel:SetClass("hidden", selectedTab ~= "Completed")

    local tabPanels = {attentionPanel, milestonesPanel, activePanel, completedPanel}

    -- Content panel that holds all tab panels
    local contentPanel = gui.Panel{
        width = "100%",
        height = "100%-75",
        flow = "none",
        valign = "top",
        vmargin = 5,
        children = tabPanels,

        showTab = function(element, tabIndex)
            for i, p in ipairs(tabPanels) do
                if p ~= nil then
                    local hidden = (tabIndex ~= i)
                    p:SetClass("hidden", hidden)
                end
            end
        end,
    }

    local tabsPanel

    -- Tab selection function
    local selectTab = function(tabName)
        local index = tabName == "Attention" and 1 or
                      tabName == "Milestones" and 2 or
                      tabName == "Active" and 3 or 4

        contentPanel:FireEventTree("showTab", index)

        for _, tab in ipairs(tabsPanel.children) do
            if tab.data and tab.data.tabName then
                tab:SetClass("selected", tab.data.tabName == tabName)
            end
        end

        -- Save selected tab preference
        local prefKey = string.format("dt_director_selected_tab:%s", dmhub.gameid or "default")
        dmhub.SetPref(prefKey, tabName)
    end

    -- Use the same categorized data for counts (already calculated above)

    -- Create tabs panel
    tabsPanel = gui.Panel{
        classes = {"dtTabContainer"},
        styles = {DTDirectorPanel.TabsStyles},
        children = {
            gui.Label{
                classes = {
                    "dtTab",
                    selectedTab == "Attention" and "selected" or nil,
                    #categorized.attention > 0 and "important" or nil,
                },
                text = string.format("Attention (%d)", #categorized.attention),
                data = {tabName = "Attention"},
                press = function() selectTab("Attention") end,
            },
            gui.Label{
                classes = {
                    "dtTab",
                    selectedTab == "Milestones" and "selected" or nil,
                    #categorized.milestones > 0 and "important" or nil},
                text = string.format("Milestones (%d)", #categorized.milestones),
                data = {tabName = "Milestones"},
                press = function() selectTab("Milestones") end,
            },
            gui.Label{
                classes = {"dtTab", selectedTab == "Active" and "selected" or nil},
                text = string.format("Active (%d)", #categorized.active),
                data = {tabName = "Active"},
                press = function() selectTab("Active") end,
            },
            gui.Label{
                classes = {"dtTab", selectedTab == "Completed" and "selected" or nil},
                text = string.format("Completed (%d)", #categorized.completed),
                data = {tabName = "Completed"},
                press = function() selectTab("Completed") end,
            }
        }
    }

    return gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",
        styles = {DTDirectorPanel.TabsStyles},
        children = {
            tabsPanel,
            contentPanel
        }
    }
end

--- Refreshes the panel content (used by both refreshGame and show events)
--- @param element table The main panel element to refresh
function DTDirectorPanel:_refreshPanelContent(element)
    local headerPanel = self:_buildHeaderPanel()
    local contentPanel = self:_buildContentPanel()
    element.children = {headerPanel, contentPanel}
end

--- Gets styling for tab content elements
--- @return table styles Array of GUI styles for tab content
function DTDirectorPanel:_getTabContentStyles()
    return {
        -- Character section styling
        gui.Style {
            selectors = {"character-section"},
            width = "100%",
            margin = 2
        },
        gui.Style {
            selectors = {"character-header"},
            bgcolor = Styles.backgroundColor,
            borderWidth = 1,
            borderColor = Styles.textColor,
            height = 30,
            margin = 1
        },
        gui.Style {
            selectors = {"character-header", "hover"},
            bgcolor = Styles.textColor,
            color = Styles.backgroundColor,
            brightness = 0.9
        },
        -- Character content styling
        gui.Style {
            selectors = {"character-content"},
            width = "98%",
            halign = "right",
            transitionTime = 0.2
        },
        gui.Style {
            selectors = {"character-content", "collapsed"},
            height = 0,
            hidden = 1
        },
        -- Project detail styling
        gui.Style {
            selectors = {"project-detail"},
            bgcolor = Styles.backgroundColor,
            borderWidth = 1,
            borderColor = Styles.textColor,
            margin = 1
        },
        gui.Style {
            selectors = {"project-detail", "hover"},
            bgcolor = Styles.textColor,
            color = Styles.backgroundColor,
            brightness = 0.9
        }
    }
end
