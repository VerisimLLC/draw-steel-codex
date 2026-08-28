--- In-place project editor for character sheet integration
--- Provides real-time editing of project fields within the character sheet
--- @class DTProjectEditor
--- @field project DTProject The project being edited
DTProjectEditor = RegisterGameType("DTProjectEditor")

local mod = dmhub.GetModLoading()

local function getToken()
    if CharacterSheet.instance and CharacterSheet.instance.data and CharacterSheet.instance.data.info then
        return CharacterSheet.instance.data.info.token
    end
    return nil
end
local function modifyTokenProps(info)
    local token = DTCharSheetTab.GetToken()
    if token then
        token:ModifyProperties{
            description = info.description or "Update Character Downtime Info",
            undoable = false,
            execute = info.execute,
        }
    end
end

--- Gets the fresh project data from the character sheet
--- @return DTProject|nil project The current project or nil if not found
function DTProjectEditor:GetProject()
    return self.project
end

--- Creates the project editor form for a downtime project
--- @return table panel The form panel with input fields
function DTProjectEditor:_createProjectForm()
    local isDM = dmhub.isDM
    local progress = self.project:GetProgress()

    local projectFormStyles = {
        {
            selectors = {"peFormRow"},
            width = "100%",
            height = 50,
            vmargin = 6,
            flow = "horizontal",
        },
    }

    -- Select Item button (only if no progress)
    local selectItem = progress == 0 and gui.Button {
        classes = {"sizeM", "withSuccess"},
        halign = "left",
        rmargin = 6,
        icon = "icons/icon_tool/icon_tool_79.png", --mod.images.downtimeProjects,
        hoverCursor = "pressbutton",
        data = {
            getProject = function(element)
                local projectController = element:FindParentWithClass("projectController")
                if projectController then
                    return projectController.data.project, projectController
                end
                return nil
            end
        },
        linger = function(element)
            gui.Tooltip("Craft an item...")(element)
        end,
        refreshToken = function(element)
            local project = element.data.getProject(element)
            local isEnabled = true
            if project then
                if project:GetProgress() > 0 then
                    isEnabled = false
                end
            end
            element:SetClass("disabled", not isEnabled)
            element.interactable = isEnabled
        end,
        click = function(element)
            if not element.interactable then return end
            CharacterSheet.instance:AddChild(DTSelectItemDialog.CreateAsChild({
                confirm = function(sourceType, selectedId)
                    if not selectedId or #selectedId == 0 then return end
                    local project, controller = element.data.getProject(element)
                    if not project then return end

                    modifyTokenProps{
                        execute = function()
                            DTBusinessRules.ApplySourceToProject(project, sourceType, selectedId)
                        end,
                    }
                    controller:FireEventTree("refreshToken")
                    dmhub.Schedule(0.1, function()
                        DTSettings.Touch()
                        DTShares.Touch()
                    end)
                end,
                cancel = function()
                    -- Placeholder for future cancel logic
                end
            }))
        end
    } or gui.Panel { height = 1, width = 1 }

    -- Title field (input only, no label)
    local titleField = gui.Panel{
        width = "98%",
        height = "auto",
        valign = "center",
        children = {
            gui.Input {
                classes = {"form"},
                width = progress > 0 and "98%" or "98%-36",
                height = 32,
                valign = "center",
                placeholderText = "Press the button to the left to craft an item (fully automated!), or enter project details manually...",
                editlag = 0.5,
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project and element.text ~= project:GetTitle() then
                        element.text = project:GetTitle() or ""
                    end
                end,
                edit = function(element)
                    element:FireEvent("change")
                end,
                change = function(element)
                    local project = element.data.getProject(element)
                    if project and element.text ~= project:GetTitle() then
                        modifyTokenProps{
                            description = "Change Downtime project title",
                            undoable = false,
                            execute = function()
                                project:SetTitle(element.text)
                            end,
                        }
                        dmhub.Schedule(0.1, function()
                            DTSettings.Touch()
                            DTShares.Touch()
                        end)
                    end
                end
            }
        }
    }

    -- Progress field
    local progressField = gui.Panel {
        width = "98%",
        height = "auto",
        flow = "vertical",
        valign = "center",
        children = {
            gui.Label {
                text = "Progress:",
                classes = {"form"},
                width = "98%",
            },
            gui.Label {
                classes = {"form", "bold"},
                width = "100%-8",
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project then
                        local progress = project:GetProgress()
                        local goal = project:GetProjectGoal()
                        local pct = goal > 0 and (progress / goal) or 0
                        element.text = string.format("%d / %d (%d%%)", progress, goal, math.floor(pct * 100))
                    end
                end
            }
        }
    }

    -- Prerequisite field (label + input)
    local prerequisiteField = gui.Panel {
        width = "98%",
        height = "auto",
        flow = "vertical",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Project Prerequisite:",
            },
            gui.Input {
                classes = {"form"},
                width = "94%",
                placeholderText = "Required items or prerequisites...",
                editlag = 0.5,
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project and element.text ~= project:GetItemPrerequisite() then
                        element.text = project:GetItemPrerequisite() or ""
                    end
                end,
                edit = function(element)
                    element:FireEvent("change")
                end,
                change = function(element)
                    local project = element.data.getProject(element)
                    if project and element.text ~= project:GetItemPrerequisite() then
                        modifyTokenProps{
                            execute = function()
                                project:SetItemPrerequisite(element.text)
                            end,
                        }
                        dmhub.Schedule(0.1, function()
                            DTSettings.Touch()
                            DTShares.Touch()
                        end)
                    end
                end
            }
        }
    }

    -- Source field
    local sourceField = gui.Panel {
        width = "98%-4",
        height = "auto",
        flow = "vertical",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Project Source:",
            },
            gui.Input {
                classes = {"form"},
                width = "94%",
                placeholderText = "Book, tutor, or source of project knowledge...",
                editlag = 0.5,
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project and element.text ~= project:GetProjectSource() then
                        element.text = project:GetProjectSource() or ""
                    end
                end,
                edit = function(element)
                    element:FireEvent("change")
                end,
                change = function(element)
                    local project = element.data.getProject(element)
                    if project and element.text ~= project:GetProjectSource() then
                        modifyTokenProps{
                            execute = function()
                                project:SetProjectSource(element.text)
                            end,
                        }
                        dmhub.Schedule(0.1, function()
                            DTSettings.Touch()
                            DTShares.Touch()
                        end)
                    end
                end
            }
        }
    }

    -- Breakthrough Rolls field
    local breakthroughRolls = gui.Panel {
        width = "98%",
        height = "auto",
        flow = "vertical",
        halign = "center",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Breakthroughs:",
            },
            gui.Label {
                classes = {"form", "bold"},
                width = "100%-8",
                valign = "bottom",
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project then
                        local s = string.format("%d rolled", project:GetBreakthroughRollCount())
                        if element.text ~= s then
                            element.text = s
                        end
                    end
                end
            }
        }
    }

    -- Characteristic field (label + dropdown)
    local characteristicField = gui.Panel {
        width = "98%",
        height = "auto",
        flow = "vertical",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Project Roll Characteristic:",
            },
            gui.Multiselect {
                classes = {"form"},
                flow = "horizontal",
                dropdown = {
                    width = "33%",
                },
                chipPanel = {
                    width = "67%",
                },
                options = DTHelpers.ListToDropdownOptions(DTConstants.CHARACTERISTICS),
                sort = true,
                textDefault = "Select...",
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                create = function(element)
                    local project = element.data.getProject(element)
                    if project then
                        local characteristics = project:GetTestCharacteristics() or {}
                        local valueDict = {}
                        for _, id in ipairs(characteristics) do
                            valueDict[id] = true
                        end
                        element.value = valueDict
                    end
                end,
                refreshToken = function(element)
                    local uiDict = element.value
                    local project = element.data.getProject(element)
                    if project then
                        local storageArray = project:GetTestCharacteristics() or {}
                        -- Convert storage array to dict for comparison
                        local storageDict = {}
                        for _, id in ipairs(storageArray) do
                            storageDict[id] = true
                        end
                        element.value = storageDict
                    end
                end,
                change = function(element)
                    local uiDict = element.value
                    local project = element.data.getProject(element)
                    if project then
                        -- Convert dictionary to array for storage
                        local uiArray = {}
                        for id, flag in pairs(uiDict) do
                            if flag then
                                uiArray[#uiArray + 1] = id
                            end
                        end
                        local storageArray = project:GetTestCharacteristics()
                        if not dmhub.DeepEqual(uiArray, storageArray) then
                            modifyTokenProps{
                                execute = function()
                                    project:SetTestCharacteristics(uiArray)
                                end
                            }
                            local projectController = element:FindParentWithClass("projectController")
                            if projectController then
                                projectController:FireEventTree("refreshToken")
                            end
                            dmhub.Schedule(0.1, function()
                                DTSettings.Touch()
                                DTShares.Touch()
                            end)
                        end
                    end
                end
            }
        }
    }

    -- Language field
    local langTable = dmhub.GetTableVisible(Language.tableName) or {}
    -- Languages we'll show in the list are all languages except selected one
    local candidateLangs = {}
    for k, v in pairs(langTable) do
        candidateLangs[#candidateLangs + 1] = {
            id = k,
            text = v.name
        }
    end
    local languageField = gui.Panel {
        width = "98%",
        height = "auto",
        flow = "vertical",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Languages:",
            },
            gui.Multiselect {
                classes = {"form"},
                dropdown = {
                    width = "33%",
                },
                chipPanel = {
                    width = "67%",
                },
                options = candidateLangs,
                flow = "horizontal",
                textDefault = "Select languages...",
                sort = true,
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                create = function(element)
                    local project = element.data.getProject(element)
                    if project then
                        local languages = project:GetProjectSourceLanguages() or {}
                        local valueDict = {}
                        for _, id in ipairs(languages) do
                            valueDict[id] = true
                        end
                        element.value = valueDict
                    end
                end,
                refreshToken = function(element)
                    local uiDict = element.value
                    local project = element.data.getProject(element)
                    if project then
                        local storageArray = project:GetProjectSourceLanguages() or {}
                        local storageDict = {}
                        for _, id in ipairs(storageArray) do
                            storageDict[id] = true
                        end
                        element.value = storageDict
                    end
                end,
                change = function(element)
                    local uiDict = element.value
                    local project = element.data.getProject(element)
                    if project then
                        -- Convert dictionary to array for storage
                        local uiArray = {}
                        for id, flag in pairs(uiDict) do
                            if flag then
                                uiArray[#uiArray + 1] = id
                            end
                        end
                        local storageArray = project:GetProjectSourceLanguages()
                        if not dmhub.DeepEqual(uiArray, storageArray) then
                            modifyTokenProps{
                                description = "Change Downtime Project Languages",
                                editable = false,
                                execute = function()
                                    project:SetProjectSourceLanguages(uiArray)
                                end,
                            }
                            local projectController = element:FindParentWithClass("projectController")
                            if projectController then
                                projectController:FireEventTree("refreshToken")
                            end
                            dmhub.Schedule(0.1, function()
                                DTSettings.Touch()
                                DTShares.Touch()
                            end)
                        end
                    end
                end
            }
        }
    }

    -- Goal field (label + input)
    local goalField = gui.Panel {
        width = "98%",
        height = "auto",
        flow = "vertical",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Project Goal:",
            },
            gui.Input {
                classes = {"form"},
                width = "80%",
                textAlignment = "center",
                editlag = 0.5,
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project and element.text ~= tostring(project:GetProjectGoal()) then
                        element.text = tostring(project:GetProjectGoal())
                    end
                end,
                edit = function(element)
                    element:FireEvent("change")
                end,
                change = function(element)
                    local project = element.data.getProject(element)
                    if project and tonumber(element.text) ~= project:GetProjectGoal() then
                        local value = tonumber(element.text) or 1
                        modifyTokenProps{
                            execute = function()
                                project:SetProjectGoal(math.max(1, math.floor(value)))
                            end,
                        }
                        dmhub.Schedule(0.1, function()
                            DTSettings.Touch()
                            DTShares.Touch()
                        end)
                    end
                end
            }
        }
    }

    -- Status field (label + dropdown for DM, display for players)
    local statusField = gui.Panel {
        width = "98%",
        height = "auto",
        flow = "vertical",
        data = {
            getProject = function(element)
                local projectController = element:FindParentWithClass("projectController")
                if projectController then
                    return projectController.data.project
                end
                return nil
            end
        },
        children = {
            gui.Label {
                classes = {"form"},
                text = "Status:",
            },
            isDM and gui.Dropdown {
                classes = {"form"},
                width = "100%-4",
                options = DTHelpers.ListToDropdownOptions(DTConstants.STATUS),
                refreshToken = function(element)
                    local project = element.parent.data.getProject(element)
                    if project and element.idChosen ~= project:GetStatus() then
                        element.idChosen = project:GetStatus()
                    end
                end,
                change = function(element)
                    local project = element.parent.data.getProject(element)
                    if project and element.idChosen ~= project:GetStatus() then
                        modifyTokenProps{
                            execute = function()
                                project:SetStatus(element.idChosen)
                            end,
                        }
                        dmhub.Schedule(0.1, function()
                            DTSettings.Touch()
                            DTShares.Touch()
                        end)
                    end
                end
            } or gui.Label {
                classes = {"form", "bold"},
                width = "auto",
                valign = "center",
                linger = function(element)
                    gui.Tooltip{
                        maxWidth = 300,
                        fontSize = 16,
                        text = "Your Director must activate this project by editing this form.",
                    }(element)
                end,
                refreshToken = function(element)
                    local project = element.parent.data.getProject(element)
                    if project then
                        local status = project:GetStatus()
                        element.text = DTConstants.GetDisplayText(DTConstants.STATUS, status)
                        element:SetClass("success", status == "ACTIVE")
                        element:SetClass("warning", status ~= "ACTIVE")
                    end
                end
            },
        }
    }

    -- Status Reason field (label + textbox for DM, display for players)
    local statusReasonField = gui.Panel {
        width = "98%",
        height = "auto",
        flow = "vertical",
        children = {
            gui.Label {
                classes = {"form"},
                width = "98%",
                text = "",
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    local status = project and project:GetStatus()
                    if isDM or status == DTConstants.STATUS.PAUSED.key or status == DTConstants.STATUS.MILESTONE.key then
                        element.text = "Status Reason:"
                    else
                        element.text = ""
                    end
                end
            },
            isDM and gui.Input {
                classes = {"form"},
                width = "94%",
                editlag = 0.5,
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project and element.text ~= project:GetStatusReason() then
                        element.text = project:GetStatusReason()
                    end
                end,
                edit = function(element)
                    element:FireEvent("change")
                end,
                change = function(element)
                    local project = element.data.getProject(element)
                    if project and element.text ~= project:GetStatusReason() then
                        modifyTokenProps{
                            description = "Change Downtime Project Status Reason",
                            undoable = false,
                            execute = function()
                                project:SetStatusReason(element.text)
                            end,
                        }
                        dmhub.Schedule(0.1, function()
                            DTSettings.Touch()
                            DTShares.Touch()
                        end)
                    end
                end
            }or gui.Label {
                classes = {"form", "bold"},
                text = "",
                width = "98%",
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project and not project:IsActive() then
                        element.text = project:GetStatusReason()
                    else
                        element.text = ""
                    end
                end
            }
        }
    }

    -- Milestone field (label + input, DM only)
    local milestoneField = isDM and gui.Panel {
        width = "98%",
        height = "auto",
        flow = "vertical",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Milestone Stop:",
            },
            gui.Input {
                classes = {"form"},
                width = "80%",
                textAlignment = "center",
                placeholderText = "0",
                editlag = 0.5,
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project and element.text ~= tostring(project:GetMilestoneThreshold()) then
                        local threshold = project:GetMilestoneThreshold()
                        element.text = threshold and tostring(threshold) or ""
                    end
                end,
                edit = function(element)
                    element:FireEvent("change")
                end,
                change = function(element)
                    local project = element.data.getProject(element)
                    if project and element.text ~= tostring(project:GetMilestoneThreshold()) then
                        modifyTokenProps{
                            execute = function()
                                if element.text == "" then
                                    project:SetMilestoneThreshold(nil)
                                else
                                    local value = tonumber(element.text) or 0
                                    project:SetMilestoneThreshold(math.max(0, math.floor(value)))
                                end
                            end,
                        }
                        dmhub.Schedule(0.1, function()
                            DTSettings.Touch()
                            DTShares.Touch()
                        end)
                    end
                end
            }
        }
    } or gui.Panel{height = 1}

    -- Main form panel
    return gui.Panel {
        styles = projectFormStyles,
        width = "100%",
        height = "auto",
        flow = "vertical",
        vmargin = 10,
        children = {
            -- Row 1
            gui.Panel {
                classes = {"peFormRow"},
                children = {
                    gui.Panel {
                        width = "84%",
                        height = "auto",
                        flow = "horizontal",
                        children = {selectItem, titleField}
                    },
                    gui.Panel {
                        width = "15%-4",
                        height = "auto",
                        children = {progressField,},
                    },
                }
            },

            -- Row 2
            gui.Panel {
                classes = {"peFormRow"},
                children = {
                    gui.Panel {
                        width = "42%-2",
                        height = "auto",
                        children = {prerequisiteField,}
                    },
                    gui.Panel {
                        width = "42%-2",
                        height = "auto",
                        children = {sourceField,}
                    },
                    gui.Panel {
                        width = "15%-4",
                        height = "auto",
                        valign = "bottom",
                        children = {breakthroughRolls,},
                    },
                }
            },

            -- Row 3
            gui.Panel {
                classes = {"peFormRow"},
                children = {
                    gui.Panel {
                        width = "42%-2",
                        height = "auto",
                        children = {characteristicField,}
                    },
                    gui.Panel {
                        width = "42%-2",
                        height = "auto",
                        children = {languageField,}
                    },
                    gui.Panel {
                        width = "15%-4",
                        height = "auto",
                        children = {goalField,}
                    },
                },
            },

            -- Row 4
            gui.Panel {
                classes = {"peFormRow"},
                children = {
                    gui.Panel {
                        width = "42%-2",
                        height = "auto",
                        children = {statusField,}
                    },
                    gui.Panel {
                        width = "42%-2",
                        height = "auto",
                        children = {statusReasonField,}
                    },
                    gui.Panel {
                        width = "15%-4",
                        height = "auto",
                        children = {milestoneField,}
                    },
                }
            },
        }
    }
end

--- Creates read-only form panel for shared projects
--- @param ownerName string The display name of the character who owns this project
--- @param ownerColor string|nil The player color for the owner (optional)
--- @return table panel The read-only form panel
function DTProjectEditor:_createSharedProjectForm(ownerName, ownerColor)
    local projectFormStyles = {
        {
            selectors = {"peFormRow"},
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            vmargin = 8,
            flow = "horizontal",
        },
    }

    -- Title field (modified to include owner name)
    local titleField = gui.Panel {
        width = "98%",
        height = "auto",
        flow = "horizontal",
        valign = "center",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Title:",
                hmargin = 10,
                textAlignment = "right",
                width = "auto",
            },
            gui.Label {
                classes = {"form"},
                width = "100%-160",
                hmargin = 4,
                data = {
                    ownerName = ownerName,
                    ownerColor = ownerColor,
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                create = function(element)
                    element:FireEvent("refreshToken")
                end,
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project then
                        local ownerDisplay = element.data.ownerName
                        -- Apply color if available
                        if element.data.ownerColor then
                            ownerDisplay = string.format("<color=%s>%s</color>", element.data.ownerColor, element.data.ownerName)
                        end
                        element.text = string.format("%s (from %s)", project:GetTitle(), ownerDisplay)
                    end
                end
            }
        }
    }

    -- Progress field
    local progressField = gui.Panel {
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Progress:",
                hmargin = 4,
                width = "auto",
                minWidth = 0,
            },
            gui.Label {
                classes = {"form"},
                width = "auto",
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                create = function(element)
                    element:FireEvent("refreshToken")
                end,
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project then
                        local progress = project:GetProgress()
                        local goal = project:GetProjectGoal()
                        local pct = goal > 0 and (progress / goal) or 0
                        element.text = string.format("%d / %d (%d%%)", progress, goal, math.floor(pct * 100))
                    end
                end
            }
        }
    }

    -- Source field
    local sourceField = gui.Panel {
        width = "98%",
        height = "auto",
        flow = "horizontal",
        valign = "center",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Project Source:",
                hmargin = 10,
                textAlignment = "right",
                width = "auto",
            },
            gui.Label {
                classes = {"form"},
                width = "100%-60",
                hmargin = 4,
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                create = function(element)
                    element:FireEvent("refreshToken")
                end,
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project then
                        element.text = project:GetProjectSource() or ""
                    end
                end
            }
        }
    }

    -- Characteristic field (read-only, displays comma-separated list)
    local characteristicField = gui.Panel {
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Project Roll Characteristic:",
                hmargin = 4,
                width = "auto",
                minWidth = 0,
            },
            gui.Label {
                classes = {"form"},
                width = "auto",
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project then
                        local characteristics = project:GetTestCharacteristics()
                        if characteristics and #characteristics > 0 then
                            local displayTexts = {}
                            for _, charKey in ipairs(characteristics) do
                                displayTexts[#displayTexts + 1] = DTConstants.GetDisplayText(DTConstants.CHARACTERISTICS, charKey)
                            end
                            element.text = table.concat(displayTexts, ", ")
                        else
                            element.text = "(none)"
                        end
                    end
                end
            }
        }
    }

    -- Language field
    local languageField = gui.Panel {
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Language Penalty:",
                hmargin = 4,
                width = "auto",
                minWidth = 0,
            },
            gui.Label {
                classes = {"form"},
                width = "auto",
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                create = function(element)
                    element:FireEvent("refreshToken")
                end,
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project then
                        local creature = CharacterSheet.instance.data.info.token.properties
                        local projectLangs = project:GetProjectSourceLanguages()
                        local penalty = DTBusinessRules.CalcLangPenalty(projectLangs, creature:LanguagesKnown())
                        element.text = DTConstants.GetDisplayText(DTConstants.LANGUAGE_PENALTY, penalty)
                    end
                end
            }
        }
    }

    -- Status field
    local statusField = gui.Panel {
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Status:",
                hmargin = 4,
                width = "auto",
                minWidth = 0,
            },
            gui.Label {
                classes = {"form"},
                width = "auto",
                data = {
                    getProject = function(element)
                        local projectController = element:FindParentWithClass("projectController")
                        if projectController then
                            return projectController.data.project
                        end
                        return nil
                    end
                },
                create = function(element)
                    element:FireEvent("refreshToken")
                end,
                refreshToken = function(element)
                    local project = element.data.getProject(element)
                    if project then
                        local status = project:GetStatus()
                        element.text = DTConstants.GetDisplayText(DTConstants.STATUS, status)
                        element:SetClass("success", status == "ACTIVE")
                        element:SetClass("warning", status ~= "ACTIVE")
                    end
                end
            }
        }
    }

    -- Shared project panel
    return gui.Panel {
        styles = projectFormStyles,
        width = "100%",
        height = "auto",
        flow = "vertical",
        create = function(element)
            dmhub.Schedule(0.2, function()
                element.monitorGame = DTShares.GetDocumentPath()
            end)
        end,
        refreshGame = function(element)
            element:FireEventTree("refreshToken")
        end,
        children = {
            -- Row 1: Title, Status, Progress
            gui.Panel {
                classes = {"peFormRow"},
                height = "auto",
                children = {
                    gui.Panel {
                        width = "50%",
                        height = "auto",
                        children = {titleField}
                    },
                    gui.Panel {
                        width = "25%",
                        height = "auto",
                        children = {statusField}
                    },
                    gui.Panel {
                        width = "25%",
                        height = "auto",
                        children = {progressField}
                    }
                }
            },

            -- Row 2: Source, Language Penalty, Characteristic
            gui.Panel {
                classes = {"peFormRow"},
                children = {
                    gui.Panel {
                        width = "50%",
                        height = "auto",
                        children = {sourceField}
                    },
                    gui.Panel {
                        width = "25%",
                        height = "auto",
                        children = {languageField}
                    },
                    gui.Panel {
                        width = "25%",
                        height = "auto",
                        children = {characteristicField}
                    }
                }
            }
        }
    }
end

--- Creates the adjustments list for a downtime project
--- @return table panel The adjustments table / panel
function DTProjectEditor:_createAdjustmentsPanel()
    return gui.Panel {
        classes = {"featureCard"},
        width = "98%",
        height = "100%",
        valign = "center",
        flow = "vertical",
        children = {
            -- Header
            gui.Panel {
                classes = {"featureCardHeader", "expanded"},
                width = "100%",
                height = "auto",
                margin = 0,
                vpad = 6,
                children = {
                    gui.Panel {
                        width = "80%",
                        halign = "left",
                        valign = "center",
                        height = "auto",
                        children = {
                            gui.Label {
                                classes = {"form", "sizeS"},
                                text = "Adjustments",
                                width = "90%",
                                hmargin = 10,
                            },
                        }
                    },
                    gui.Panel {
                        width = "12%",
                        height = "auto",
                        halign = "right",
                        linger = function(element)
                            gui.Tooltip("Add an adjustment")(element)
                        end,
                        children = {
                            gui.Button{
                                classes = {"addButton"},
                                halign = "center",
                                click = function(element)
                                    local controller = element:FindParentWithClass("projectController")
                                    if controller then
                                        local newAdjustment = DTAdjustment.CreateNew()
                                        CharacterSheet.instance:AddChild(DTAdjustmentDialog.CreateAsChild(newAdjustment, {
                                            confirm = function()
                                                controller:FireEvent("addAdjustment", newAdjustment)
                                            end,
                                            cancel = function()
                                                -- Cancel handling if needed
                                            end
                                        }))
                                    end
                                end,
                            }
                        }
                    },
                }
            },

            -- Body - Scrollable adjustments list
            gui.Panel {
                classes = {"featureCardBody"},
                width = "100%",
                height = "85%",
                valign = "top",
                vscroll = true,
                children = {
                    gui.Panel {
                        id = "adjustmentScrollArea",
                        width = "100%",
                        height = "100%",
                        flow = "vertical",
                        valign = "top",
                        data = {
                            getProject = function(element)
                                local projectController = element:FindParentWithClass("projectController")
                                if projectController then
                                    return projectController.data.project
                                end
                                return nil
                            end,
                        },
                        refreshToken = function(element)
                            local project = element.data.getProject(element)
                            if project then
                                local adjustments = project:GetAdjustments()
                                element.children = DTProjectEditor._reconcileProgressItemsList(element.children, adjustments, "deleteAdjustment")
                            end
                        end,
                        children = {}
                    }
                }
            }
        }
    }
end

--- Creates the adjustments list for a downtime project
--- @return table panel The adjustments table / panel
function DTProjectEditor:_createRollsPanel()
    return gui.Panel {
        classes = {"featureCard"},
        width = "98%",
        height = "100%",
        valign = "center",
        flow = "vertical",
        children = {
            -- Header
            gui.Panel {
                classes = {"featureCardHeader", "expanded"},
                width = "100%",
                height = "auto",
                margin = 0,
                vpad = 6,
                children = {
                    gui.Panel {
                        width = "80%",
                        halign = "left",
                        valign = "center",
                        height = "auto",
                        children = {
                            gui.Label {
                                classes = {"form", "sizeS"},
                                text = "Rolls",
                                width = "90%",
                                hmargin = 10,
                            },
                        }
                    },
                    --Rolling on a project no longer happens here. The column is
                    --kept so the header keeps its shape.
                    gui.Panel {
                        width = "12%",
                        height = "auto",
                        halign = "right",
                    },
                }
            },

            -- Body - Scrollable rolls list
            gui.Panel {
                classes = {"featureCardBody"},
                width = "100%",
                height = "85%",
                valign = "top",
                vscroll = true,
                children = {
                    gui.Panel {
                        id = "rollScrollArea",
                        classes = {"rollListController"},
                        width = "100%",
                        height = "auto",
                        flow = "vertical",
                        valign = "top",
                        data = {
                            getProject = function(element)
                                local projectController = element:FindParentWithClass("projectController")
                                if projectController then
                                    return projectController.data.project
                                end
                                return nil
                            end,
                        },
                        refreshToken = function(element)
                            local project = element.data.getProject(element)
                            if project then
                                local rolls = project:GetRolls()
                                element.children = DTProjectEditor._reconcileProgressItemsList(element.children, rolls, "deleteRoll")
                            end
                        end,
                        children = {}
                    }
                }
            }
        }
    }
end

--- Creates a roll button for making downtime project rolls
--- @param options table|nil Options table with styling and callback properties
---   - confirm: function(rolls, controller, roller) - Callback when rolls are confirmed, receives array of DTRoll objects and the roller
---   - width: number - Button width (default: 24)
---   - height: number - Button height (default: 24)
---   - margin: number - Button margin (default: 0)
---   - borderWidth/border: number - Border width (default: 0)
---   - halign: string - Horizontal alignment (default: nil)
---   - hmargin: number - Horizontal margin (default: nil)
---   - vmargin: number - Vertical margin (default: nil)
--- @return table button The roll button element
--- Picks which characteristic a project roll is made with
--- A project may allow several and nobody would choose anything but their best,
--- so it is derived rather than asked for. The baseline roll dialog carries one
--- characteristic per check, so this has to be settled before the ask.
--- @param roller DTRoller The entity making the roll
--- @param allowed table Characteristic keys the project permits
--- @return string attrid The characteristic to roll
function DTProjectEditor._bestCharacteristic(roller, allowed)
    local bestId, bestValue = nil, nil

    for _, attrId in ipairs(allowed or {}) do
        local value = roller:GetCharacteristic(attrId)
        if bestValue == nil or value > bestValue then
            bestId, bestValue = attrId, value
        end
    end

    return bestId or DTConstants.CHARACTERISTICS[1].key
end

--- Turns one completed roll into the project's record of it
--- @param info table The harvested roll
--- @param roller DTRoller The entity that rolled
--- @param token any The hero whose project this is
--- @param attrid string The characteristic rolled
--- @param isBreakthrough boolean Whether this roll came of a breakthrough
--- @return DTRoll roll The record
function DTProjectEditor._buildProjectRoll(info, roller, token, attrid, isBreakthrough)
    --The dialog applies edges and banes to the total itself, flat, at every
    --count -- verified against recorded rolls: "2d10+2 2 banes" on faces 7+4
    --landed a total of 9. There is nothing to correct, and taking the total as
    --given is what keeps every modifier the dialog applied intact.
    local label = cond(isBreakthrough, "Breakthrough:", "Project roll:")

    --The roll's own formula is the truest audit available and costs nothing to
    --read back: it names every modifier that actually applied, which a count of
    --edges and banes cannot. Falls back to the counts if the roll has aged out
    --of chat.
    local rollInfo = nil
    if info.rollid ~= nil and info.rollid ~= "" then
        rollInfo = chat.GetRollInfo(info.rollid)
    end

    --Named rather than left implicit: a plustwo modifier like Skilled folds into
    --the formula's number, so "2d10+4" cannot be told apart from a bigger
    --characteristic without this.
    local applied = ""
    if #(info.modifiersUsed or {}) > 0 then
        applied = string.format("; <b>Applied:</b> %s",
            table.concat(info.modifiersUsed, ", "))
    end

    local rollString = string.format("2d10 + %s", attrid)
    local audit
    if rollInfo ~= nil and rollInfo.rollStr ~= nil then
        rollString = rollInfo.rollStr
        audit = string.format("<b>%s</b> %s%s; <b>Natural:</b> %d",
            label, rollInfo.rollStr, applied, info.naturalRoll or 0)
    else
        audit = string.format("<b>%s</b> %s; <b>Edges:</b> %d; <b>Banes:</b> %d%s; <b>Natural:</b> %d",
            label, DTConstants.GetDisplayText(DTConstants.CHARACTERISTICS, attrid),
            info.boons or 0, info.banes or 0, applied, info.naturalRoll or 0)
    end

    return DTRoll.CreateNew()
        :SetAudit(audit)
        :SetRollGuid(info.rollid or "")
        :SetRollString(rollString)
        :SetRolledBy(roller:GetName())
        :SetRolledByID(token.id or "")
        :SetRolledByFollowerID(roller:GetFollowerID())
        :SetNaturalRoll(info.naturalRoll or 0)
        :SetBreakthrough(isBreakthrough)
        :SetAmount(info.total or 0)
end

--- Creates action buttons for owned project panels (delete + share)
--- @return table buttons Array containing delete button and share button elements
function DTProjectEditor:_createOwnedProjectButtons()
    local deleteButton = gui.Button {
        classes = {"deleteButton", "sizeS"},
        halign = "left",
        valign = "top",
        hmargin = 5,
        vmargin = 5,
        click = function(element)
            local downtimeController = element:FindParentWithClass("downtimeController")
            local projectController = element:FindParentWithClass("projectController")
            if projectController and downtimeController then
                local project = projectController.data and projectController.data.project
                if project then
                    CharacterSheet.instance:AddChild(DTConfirmationDialog.ShowDeleteAsChild("Project: ".. project:GetTitle(), {
                        confirm = function()
                            downtimeController:FireEvent("deleteProject", project:GetID())
                        end,
                        cancel = function()
                            -- Optional cancel logic
                        end
                    }))
                end
            end
        end
    }

    local shareButton = gui.Button {
        classes = {"withWarning", "sizeS"},
        icon = mod.images.share,
        halign = "left",
        hmargin = 5,
        vmargin = 5,
        data = {
            getProject = function(element)
                local projectController = element:FindParentWithClass("projectController")
                if projectController then
                    return projectController.data.project
                end
                return nil
            end,
        },
        click = function(element)
            if not element.interactable then return end

            local project = element.data.getProject(element)
            local controller = element:FindParentWithClass("projectController")
            local shareData = DTShares.CreateNew()
            if project and controller and shareData then

                -- Build the list of characters to show
                local me = getToken()
                local function inPartyAndNotMe(t)
                    return t.id ~= me.id and t.partyId == me.partyId
                end
                local showList = DTBusinessRules.GetAllHeroTokens(inPartyAndNotMe)

                -- Build the list of characters already shared with
                local sharedWith = shareData:GetProjectSharedWith(me.id, project:GetID())
                local initialSelectionIds = {}
                for _, tokenId in ipairs(sharedWith) do
                    initialSelectionIds[tokenId] = {id = tokenId, selected = true}
                end

                local options = {
                    showList = showList,
                    initialSelection = initialSelectionIds,
                    callbacks = {
                        confirm = function(selectedTokens)
                            shareData:Share(me.id, project:GetID(), selectedTokens)
                        end,
                        cancel = function()
                            -- cancel handler
                        end
                    }
                }
                CharacterSheet.instance:AddChild(DTShareDialog.CreateAsChild(options))
            end
        end,
        linger = function(element)
            gui.Tooltip("Share this project with other characters to request rolls.")(element)
        end,
    }

    return {deleteButton, shareButton}
end

--- Creates action buttons for shared project panels
--- @param ownerName string The display name of the character who owns this project
--- @param ownerId string The token ID of the character who owns this project
--- @return table buttons Array containing the unshare button
function DTProjectEditor:_createSharedProjectButtons(ownerName, ownerId)
    local unshareButton = gui.Button {
        classes = {"deleteButton", "sizeS"},
        halign = "left",
        valign = "top",
        hmargin = 5,
        vmargin = 5,
        data = {
            ownerName = ownerName,
            ownerId = ownerId,
            getProject = function(element)
                local projectController = element:FindParentWithClass("projectController")
                if projectController then
                    return projectController.data.project
                end
                return nil
            end
        },
        click = function(element)
            local project = element.data.getProject(element)
                CharacterSheet.instance:AddChild(DTConfirmationDialog.CreateAsChild(
                    "Withdraw From Project?",
                    string.format("Are you sure you want to withdraw your ability to roll on %s's project?", ownerName),
                    "Confirm",
                    "Cancel",
                    {
                        confirm = function()
                            local shares = DTShares.CreateNew()
                            if shares then
                                shares:Revoke(ownerId, CharacterSheet.instance.data.info.token.id, project:GetID())
                            end
                        end,
                        cancel = function()
                            -- Optional cancel logic
                        end
                    }
                ))
        end,
        linger = function(element)
            gui.Tooltip("Remove yourself from this shared project")(element)
        end
    }

    return {unshareButton}
end

--- Creates the action buttons panel container
--- @param buttons table Array of button elements to display vertically
--- @return table panel Vertical panel containing the buttons
function DTProjectEditor:_createActionButtonsPanel(buttons)
    return gui.Panel {
        width = 60,
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",
        children = buttons,
    }
end

--- Creates the outer project panel container with consistent styling
--- @param additionalClasses table|nil Array of additional CSS classes beyond "projectController"
--- @param contentPanels table Array of panels to layout horizontally (form, adjustments, rolls)
--- @param actionButtonsPanel table The action buttons panel to position top-right
--- @param eventHandlers table|nil Table of event handler functions (addAdjustment, deleteAdjustment, etc.)
--- @return table panel The outer container panel
function DTProjectEditor:_createProjectPanelContainer(additionalClasses, contentPanels, actionButtonsPanel, eventHandlers)
    local classes = {"projectController"}
    if additionalClasses then
        for _, cls in ipairs(additionalClasses) do
            classes[#classes + 1] = cls
        end
    end

    local panelDef = {
        id = self:GetProject():GetID(),
        classes = classes,
        width = "98%",
        height = "auto",
        flow = "horizontal",
        hmargin = 5,
        vmargin = 7,
        borderColor = "#cc00cc",
        data = {
            project = self:GetProject(),
        },
        children = {
            gui.Panel{
                classes = {"bordered"},
                width = "98%",
                height = "auto",
                halign = "left",
                flow = "horizontal",
                valign = "top",
                children = contentPanels
            },
            actionButtonsPanel
        }
    }

    -- Add event handlers if provided
    if eventHandlers then
        for eventName, handler in pairs(eventHandlers) do
            panelDef[eventName] = handler
        end
    end

    return gui.Panel(panelDef)
end

--- Creates an inline editor panel for real-time project editing
--- @return table panel The editor panel with input fields
function DTProjectEditor:CreateEditorPanel()
    -- Create content panels
    local formPanel = self:_createProjectForm()
    local rollsPanel = self:_createRollsPanel()
    local adjustmentsPanel = self:_createAdjustmentsPanel()

    -- Create buttons using extracted method
    local buttons = self:_createOwnedProjectButtons()
    local actionButtonsPanel = self:_createActionButtonsPanel(buttons)

    -- Build content panels array for horizontal layout
    local contentPanels = {
        gui.Panel {
            width = "60%-8",
            height = "auto",
            halign = "left",
            valign = "top",
            hmargin = 8,
            children = { formPanel }
        },
        gui.Panel {
            width = "20%-8",
            height = "260",
            halign = "left",
            valign = "center",
            children = { adjustmentsPanel }
        },
        gui.Panel {
            width = "20%-8",
            height = "260",
            halign = "left",
            valign = "center",
            children = { rollsPanel }
        }
    }

    -- Event handlers for owned projects
    local eventHandlers = {
        addAdjustment = function(element, newAdjustment)
            modifyTokenProps{
                execute = function()
                    element.data.project:AddAdjustment(newAdjustment)
                end,
            }
            element:FireEvent("refreshProject")
            dmhub.Schedule(0.1, function()
                DTSettings.Touch()
                DTShares.Touch()
            end)
        end,

        deleteAdjustment = function(element, adjustmentId)
            modifyTokenProps{
                execute = function()
                    element.data.project:RemoveAdjustment(adjustmentId)
                end,
            }
            element:FireEvent("refreshProject")
            dmhub.Schedule(0.1, function()
                DTSettings.Touch()
                DTShares.Touch()
            end)
        end,

        deleteRoll = function(element, rollId)
            local downtimeController = element:FindParentWithClass("downtimeController")
            if downtimeController then
                local roll = element.data.project:GetRoll(rollId)
                if roll then
                    local roller = DTRoller.CreateNew(roll)
                    if roller then
                        modifyTokenProps{
                            execute = function()
                                element.data.project:RemoveRoll(rollId)
                            end,
                        }
                        downtimeController:FireEvent("adjustRolls", 1, roller)
                        dmhub.Schedule(0.1, function()
                            DTSettings.Touch()
                            DTShares.Touch()
                        end)
                    end
                end
            end
        end,

        refreshProject = function(element)
            element:FireEventTree("refreshToken")
        end,

        setProject = function(element, project)
            element.data.project = project
        end,
    }

    -- Use extracted container method
    return self:_createProjectPanelContainer(nil, contentPanels, actionButtonsPanel, eventHandlers)
end

--- Creates a read-only panel for shared projects
--- @param ownerName string The display name of the character who owns this project
--- @param ownerId string The token ID of the character who owns this project
--- @param ownerColor string|nil The player color for the owner (optional)
--- @return table panel The read-only shared project panel
function DTProjectEditor:CreateSharedProjectPanel(ownerName, ownerId, ownerColor)
    -- Create read-only form with owner name and color
    local sharedFormPanel = self:_createSharedProjectForm(ownerName, ownerColor)

    -- Create different buttons (unshare + roll)
    local buttons = self:_createSharedProjectButtons(ownerName, ownerId)
    local actionButtonsPanel = self:_createActionButtonsPanel(buttons)

    -- Simpler layout - just form, no adjustments/rolls panels
    local contentPanels = {
        gui.Panel {
            width = "95%",
            height = "auto",
            halign = "left",
            valign = "top",
            hmargin = 8,
            children = { sharedFormPanel }
        }
    }

    -- No event handlers for read-only panel
    local eventHandlers = nil

    -- Use container method with "sharedProject" class for styling distinction
    return self:_createProjectPanelContainer({"sharedProject"}, contentPanels, actionButtonsPanel, eventHandlers)
end

--- Reconciles progress item list panels with current data using efficient 3-step process
--- @param panels table Existing array of item panels
--- @param items table Array of DTProgressItem descendants
--- @param deleteEvent string The event name to fire when deleting
--- @return table panels The reconciled panel array
function DTProjectEditor._reconcileProgressItemsList(panels, items, deleteEvent)
    panels = panels or {}
    if type(panels) ~= "table" then
        panels = {}
    end

    items = items or {}

    -- Handle empty items case
    if not next(items) then
        return {
            gui.Panel {
                width = "100%",
                height = "90%",
                halign = "center",
                valign = "top",
                children = {
                    gui.Label {
                        classes = {"info"},
                        text = "There are no items yet.",
                        width = "96%",
                        height = "96%",
                        halign = "center",
                        valign = "top",
                    }
                }
            }
        }
    end

    -- Step 1: Remove panels that don't have corresponding items
    for i = #panels, 1, -1 do
        local panel = panels[i]
        local foundItem = false
        for _, item in ipairs(items) do
            if item:GetID() == panel.id then
                foundItem = true
                break
            end
        end
        if not foundItem then
            table.remove(panels, i)
        end
    end

    -- Step 2: Add panels for items that don't have panels
    for _, item in ipairs(items) do
        local foundPanel = false
        for _, panel in ipairs(panels) do
            if panel.id == item:GetID() then
                foundPanel = true
                break
            end
        end
        if not foundPanel then
            panels[#panels + 1] = DTProjectEditor._createProgressListItem(item, deleteEvent)
        end
    end

    -- Step 3: Sort panels by reverse chronological order
    local serverTimeLookup = {}
    for _, item in ipairs(items) do
        serverTimeLookup[item:GetID()] = item:GetServerTime()
    end

    table.sort(panels, function(a, b)
        local aTime = serverTimeLookup[a.id] or 0
        local bTime = serverTimeLookup[b.id] or 0
        return aTime > bTime
    end)

    -- Zebra-stripe the sorted rows. The {row, evenRow} / {row, oddRow}
    -- theme rules paint @bg / @bgAlt respectively.
    for i, panel in ipairs(panels) do
        local even = i % 2 == 0
        panel:SetClass("evenRow", even)
        panel:SetClass("oddRow", not even)
    end

    return panels
end

--- Creates a single progress item panel for list display
--- @param item DTProgressItem The item data to display
--- @return table panel The complete panel
function DTProjectEditor._createProgressListItem(item, deleteEvent)
    if not item then return gui.Panel{} end

    -- Format timestamp for display (remove seconds and timezone)
    local displayTime = item:GetCommitDate()

    -- Format amount with color coding
    local amount = item:GetAmount()
    local amountText = string.format("%+d", amount)
    local amountClass = amount >= 0 and "success" or "danger"

    -- Get user display name with color
    local commitBy, rollBy = item:GetCommitBy()
    local userDisplay = DTHelpers.GetPlayerDisplayName(commitBy)
    local rollText = nil
    if rollBy and #rollBy > 0 then
        local rollDisplay = DTHelpers.FormatNameWithUserColor(rollBy, commitBy)
        userDisplay = string.format("%s (%s)", rollDisplay, userDisplay)
        rollText = string.format("<b>Roll:</b> %s; ", item:GetRollString())
    end

    local description = item:GetDescription():gsub("/n", "; ")
    if rollText then
        description = rollText .. description
    end

    return gui.Panel{
        id = item:GetID(),
        classes = {"row"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        halign = "left",
        bmargin = 4,
        data = {
            serverTime = item:GetServerTime(),
        },
        children = {
            -- Top row
            gui.Panel {
                flow = "horizontal",
                valign = "top",
                height = "auto",
                width = "100%",
                children = {
                    gui.Panel{
                        flow = "horizontal",
                        width = "100%",
                        height = "auto",
                        children = {
                            gui.Label{
                                classes = {"sizeXxs"},
                                text = displayTime,
                                width = 120,
                                hmargin = 2,
                            },
                            gui.Label{
                                classes = {"sizeXxs", "bold", amountClass},
                                text = amountText,
                                width = 25,
                                hmargin = 2,
                            },
                            gui.Label{
                                classes = {"sizeXxs"},
                                text = userDisplay,
                            },
                        },
                    },
                    dmhub.isDM and gui.Button {
                        classes = {"deleteButton", "sizeXs"},
                        floating = true,
                        halign = "right",
                        valign = "center",
                        hmargin = 2,
                        click = function(element)
                            local projectController = element:FindParentWithClass("projectController")
                            if projectController then
                                CharacterSheet.instance:AddChild(DTConfirmationDialog.ShowDeleteAsChild("this item", {
                                    confirm = function()
                                        projectController:FireEvent(deleteEvent, item:GetID())
                                    end,
                                    cancel = function()
                                        -- Optional cancel logic
                                    end
                                }))
                            end
                        end,
                    } or nil
                }
            },
            -- Bottom row
            gui.Panel {
                flow = "horizontal",
                valign = "top",
                height = "auto",
                width = "100%",
                children = {
                    gui.Label{
                        classes = {"sizeXxs"},
                        text = description,
                        height = "auto",
                        width = "98%",
                        valign = "top",
                    }
                }
            }
        }
    }
end

--- Rolls a project for a roller that has already been decided
--- The character sheet asks who is rolling; the Respite already knows, because
--- the player picked a hero or a follower in its own list. Both routes end up
--- here so the roll itself, the crit chain and the modifier sweep stay in one
--- place.
--- @param args table project, roller, heroToken, and onRolls(rolls, roller)
function DTProjectEditor.PerformProjectRoll(args)
    local project = args.project
    local roller = args.roller
    local heroToken = args.heroToken
    if project == nil or roller == nil or heroToken == nil then
        return
    end

    --A follower rolling is the follower rolling: the request is addressed to
    --them, so the formula and the modifier sweep both resolve against their
    --characteristics rather than the hero's. GetCharacterById, never
    --GetTokenById -- the latter is map-only, and an unplaced follower would
    --quietly roll as the hero and produce a plausible wrong number rather than
    --an error.
    local followerId = roller:GetFollowerID()
    local rollingToken = heroToken
    if followerId ~= nil and #followerId > 0 then
        rollingToken = dmhub.GetCharacterById(followerId) or heroToken
    end

    local projectTitle = project:GetTitle()

    --Built once and reused for every breakthrough, so the chain is rolled on
    --exactly the setup the first roll used.
    local attrid = DTProjectEditor._bestCharacteristic(
        roller, project:GetTestCharacteristics())

    --skills is left empty deliberately. A project does not declare which
    --skills apply, so there is nothing to hint from; the Skilled modifier is
    --offered and the roller ticks it if it applies.
    local options = {
        attrid = attrid,
        explanation = string.format("Project roll - %s", projectTitle),
        title = string.format("Project roll - %s", projectTitle),
        skills = {},
        languages = project:GetProjectSourceLanguages(),
        modifiers = {},
        --Awaited headlessly rather than through the roll summary window, which
        --would open behind the surface that launched it.
        silent = true,
    }

    dmhub.Coroutine(function()
        local rolls = {}
        local isFirstRoll = true

        while true do
            local info = rollingToken.properties:RequestProjectRoll(rollingToken, options)
            --Cancelled or timed out. Whatever was already rolled stands: those
            --dice were really thrown.
            if info == nil then
                break
            end

            rolls[#rolls + 1] = DTProjectEditor._buildProjectRoll(
                info, roller, heroToken, attrid, not isFirstRoll)
            isFirstRoll = false

            if not info.isCrit then
                break
            end
        end

        if #rolls > 0 and args.onRolls ~= nil then
            args.onRolls(rolls, roller)
        end
    end)
end

--- Adds finished rolls to a project, on whichever hero holds that project
--- @param projectToken any The token owning the project
--- @param projectId string
--- @param rolls table DTRoll objects
--- @return boolean added
function DTProjectEditor.AddRollsToProject(projectToken, projectId, rolls)
    if projectToken == nil or projectToken.properties == nil then
        return false
    end

    local downtimeInfo = projectToken.properties:GetDowntimeInfo()
    if downtimeInfo == nil then
        return false
    end

    -- Re-read the project off the token rather than trusting a held
    -- reference, which may be stale by the time a roll finishes.
    local project = downtimeInfo:GetProject(projectId)
    if project == nil then
        return false
    end

    projectToken:ModifyProperties{
        description = "Downtime project roll",
        execute = function()
            project:AddRolls(rolls)
        end,
    }

    return true
end

--- Moves a hero's or a follower's downtime roll counter
--- A follower's rolls are held on the hero they follow, keyed by follower id,
--- so the roller's own id decides which counter moves.
--- @param rollHolderToken any The hero holding the counters
--- @param rollerCharid string The hero or follower spending
--- @param amount number Negative to spend
function DTProjectEditor.AdjustDowntimeRolls(rollHolderToken, rollerCharid, amount)
    if rollHolderToken == nil or rollHolderToken.properties == nil then
        return
    end
    if rollerCharid == nil or rollerCharid == "" then
        return
    end

    rollHolderToken:ModifyProperties{
        description = "Adjust downtime rolls",
        execute = function()
            local downtimeInfo = rollHolderToken.properties:GetDowntimeInfo()
            if downtimeInfo == nil then
                return
            end

            if rollerCharid == rollHolderToken.id then
                downtimeInfo:GrantRolls(amount)
            else
                downtimeInfo:GrantFollowerRolls(rollerCharid, amount)
            end
        end,
    }
end

--- Records finished project rolls, and spends the roll that paid for them
--- Two different heroes whenever the project is shared: the progress belongs
--- to whoever owns the project, while the roll comes off the roller's own
--- hero.
--- @param args table projectToken, projectId, rolls, rollHolderToken, rollerCharid
function DTProjectEditor.RecordProjectRolls(args)
    DTProjectEditor.AddRollsToProject(args.projectToken, args.projectId, args.rolls)
    DTProjectEditor.AdjustDowntimeRolls(args.rollHolderToken, args.rollerCharid, -1)

    dmhub.Schedule(0.2, function()
        DTSettings.Touch()
        DTShares.Touch()
    end)
end

--- Comma-separated display names for a project's test characteristics
--- @param project DTProject
--- @return string
function DTProjectEditor._characteristicNames(project)
    local names = {}
    for _, key in ipairs(project:GetTestCharacteristics() or {}) do
        names[#names + 1] = DTConstants.GetDisplayText(DTConstants.CHARACTERISTICS, key)
    end
    if #names == 0 then
        return "None"
    end
    return table.concat(names, ", ")
end

--- Comma-separated display names for a project's source languages
--- @param project DTProject
--- @return string
function DTProjectEditor._languageNames(project)
    local langTable = dmhub.GetTableVisible(Language.tableName) or {}
    local names = {}
    for _, id in ipairs(project:GetProjectSourceLanguages() or {}) do
        local entry = langTable[id]
        if entry ~= nil then
            names[#names + 1] = entry.name
        end
    end
    if #names == 0 then
        return "None"
    end
    return table.concat(names, ", ")
end

--- A project's characteristics, languages and status as one unlabelled line
--- @param project DTProject
--- @return string
function DTProjectEditor._respiteSummaryLine(project)
    return string.format("%s | %s | %s",
        DTProjectEditor._characteristicNames(project),
        DTProjectEditor._languageNames(project),
        DTConstants.GetDisplayText(DTConstants.STATUS, project:GetStatus()))
end

--- A progress bar reading X/Y, sized by its container rather than by the goal
--- Built the way the tactical panel's stamina bar is: a bordered track, an
--- inner fill whose width is driven through selfStyle, and a floating label
--- over the top.
--- @param project DTProject
--- @return Panel
function DTProjectEditor._respiteProgressBar(project)
    local function Ratio()
        local goal = project:GetProjectGoal() or 0
        if goal <= 0 then
            return 0
        end
        return math.max(0, math.min(1, project:GetProgress() / goal))
    end

    local fill = gui.Panel{
        classes = {"fillBarFill"},
        width = string.format("%f%%-2", Ratio() * 100),
        height = "100%-2",
        halign = "left",
        valign = "center",
        lmargin = 1,
        bgimage = true,
        interactable = false,
        refreshProject = function(element)
            element.selfStyle.width = string.format("%f%%-2", Ratio() * 100)
        end,
    }

    local label = gui.Label{
        classes = {"fg", "sizeXs", "number", "bold"},
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        floating = true,
        interactable = false,
        text = string.format("%d/%d", project:GetProgress(), project:GetProjectGoal() or 0),
        refreshProject = function(element)
            element.text = string.format("%d/%d", project:GetProgress(), project:GetProjectGoal() or 0)
        end,
    }

    return gui.Panel{
        classes = {"bordered"},
        width = "70%",
        height = 16,
        flow = "horizontal",
        halign = "left",
        cornerRadius = 0,
        bgcolor = "clear",

        fill,
        label,
    }
end

--- One project as the Respite shows it: read only, plus a roll button for the
--- entity the player has selected.
--- @param args table project, ownerToken, heroToken, roller and rollsLeft()
--- @return Panel
function DTProjectEditor._respiteProjectCard(args)
    local project = args.project
    local rollButton

    rollButton = gui.Button{
        classes = {"withInfo"},
        icon = "panels/initiative/initiative-dice.png",
        width = 28,
        height = 28,
        halign = "right",
        valign = "center",
        refreshProject = function(element)
            local valid, reasons = project:IsValidStateToRoll()
            local rolls = args.rollsLeft()
            local enabled = valid and rolls > 0

            element:SetClass("disabled", not enabled)
            element.interactable = enabled

            if rolls <= 0 then
                element.tooltip = gui.Tooltip(string.format(
                    "%s has no downtime rolls left.", args.roller:GetName()))
            elseif not valid then
                element.tooltip = gui.Tooltip(table.concat(reasons or {}, "\n"))
            else
                element.tooltip = gui.Tooltip(string.format(
                    "Roll for %s", args.roller:GetName()))
            end
        end,
        press = function(element)
            if not element.interactable then
                return
            end

            -- heroToken is the roller's own hero, not the project's owner:
            -- it is what the roll is recorded against and where a follower is
            -- resolved from. On a shared project those are different people.
            DTProjectEditor.PerformProjectRoll{
                project = project,
                roller = args.roller,
                heroToken = args.rollHolderToken,
                onRolls = function(rolls)
                    DTProjectEditor.RecordProjectRolls{
                        projectToken = args.ownerToken,
                        projectId = project:GetID(),
                        rolls = rolls,
                        rollHolderToken = args.rollHolderToken,
                        rollerCharid = args.rollerCharid,
                    }
                end,
            }
        end,
    }

    -- Short of the full width, and left-aligned, so the list's scroll bar does
    -- not sit over the card's right border.
    return gui.Panel{
        classes = {"bordered"},
        width = "100%-12",
        height = "auto",
        flow = "vertical",
        halign = "left",
        vmargin = 4,

        gui.Panel{
            width = "96%",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            vmargin = 6,

            gui.CreateTokenImage(args.ownerToken, {
                width = 34,
                height = 34,
                halign = "left",
                valign = "center",
            }),

            gui.Label{
                classes = {"sizeM", "bold"},
                width = "70%-34",
                height = "auto",
                halign = "left",
                valign = "center",
                hmargin = 8,
                textWrap = false,
                text = project:GetTitle(),
            },

            rollButton,
        },

        gui.Panel{
            width = "96%",
            height = "auto",
            flow = "vertical",
            halign = "center",
            bmargin = 6,

            DTProjectEditor._respiteProgressBar(project),

            -- One line, no labels: the Respite is tight for room and these
            -- three read fine as a run-on.
            gui.Label{
                classes = {"sizeS", "noBold"},
                width = "100%",
                height = "auto",
                halign = "left",
                tmargin = 2,
                textWrap = true,
                text = DTProjectEditor._respiteSummaryLine(project),
                refreshProject = function(element)
                    element.text = DTProjectEditor._respiteSummaryLine(project)
                end,
            },
        },
    }
end

--- Builds the cards for one selection. Called again whenever the set of
--- projects could have changed, since a share arriving or leaving changes the
--- list itself rather than any one card.
--- @param args table charid of the selection, and owner when it is a follower
--- @return Panel[] cards
function DTProjectEditor._respiteProjectCards(args)
    local heroId = args.owner or args.charid
    local heroToken = dmhub.GetCharacterById(heroId)

    local cards = {}
    local rollerToken = dmhub.GetCharacterById(args.charid)

    if heroToken ~= nil and heroToken.properties ~= nil and rollerToken ~= nil then
        local roller
        local rollsLeft

        if args.owner == nil then
            roller = DTRoller.CreateNew(heroToken.properties)
            rollsLeft = function()
                local info = heroToken.properties:GetDowntimeInfo()
                return info ~= nil and info:GetAvailableRolls() or 0
            end
        else
            roller = DTRoller.CreateNew(rollerToken.properties, heroId)
            rollsLeft = function()
                local info = heroToken.properties:GetDowntimeInfo()
                return info ~= nil and info:GetFollowerRolls(args.charid) or 0
            end
        end

        local entries = {}
        local downtimeInfo = heroToken.properties:GetDowntimeInfo()
        if downtimeInfo ~= nil then
            for _, project in ipairs(downtimeInfo:GetSortedProjects() or {}) do
                entries[#entries + 1] = {project = project, ownerToken = heroToken}
            end
        end

        for _, shared in ipairs(DTBusinessRules.GetSharedProjectsForRecipient(heroId) or {}) do
            local ownerToken = dmhub.GetCharacterById(shared.ownerId)
            if shared.project ~= nil and ownerToken ~= nil then
                entries[#entries + 1] = {project = shared.project, ownerToken = ownerToken}
            end
        end

        for _, entry in ipairs(entries) do
            if entry.project:GetStatus() ~= DTConstants.STATUS.COMPLETE.key and roller ~= nil then
                cards[#cards + 1] = DTProjectEditor._respiteProjectCard{
                    project = entry.project,
                    ownerToken = entry.ownerToken,
                    rollHolderToken = heroToken,
                    rollerCharid = args.charid,
                    roller = roller,
                    rollsLeft = rollsLeft,
                }
            end
        end
    end

    if #cards == 0 then
        cards[1] = gui.Label{
            classes = {"sizeM", "noBold", "fgMuted"},
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            tmargin = 24,
            text = "No projects under way.",
        }
    end

    return cards
end

--- A zero-size panel that watches one document and reports back
--- A panel carries a single monitorGame, and this list has to answer to three
--- separate signals, so each gets its own watcher. Assigned on a delay the way
--- the character sheet does it.
--- @param path string|nil document path to watch
--- @param onChange fun() what to do when it moves
--- @return Panel
function DTProjectEditor._respiteWatcher(path, onChange)
    return gui.Panel{
        width = 0,
        height = 0,
        create = function(element)
            dmhub.Schedule(0.2, function()
                if element.valid and path ~= nil then
                    element.monitorGame = path
                end
            end)
        end,
        refreshGame = function()
            onChange()
        end,
    }
end

--- Every unfinished project the selected entity can roll on, read only.
--- A follower has no projects of their own, so they work the hero's list; the
--- hero's own list is what they own plus anything shared with them.
---
--- Anyone can change these while they sit on screen: another hero can share a
--- project in or out, and other players roll on shared projects. Shares and
--- the downtime settings ping rebuild the list, since either can change which
--- projects belong on it; the hero's own token only repaints the cards.
--- @param args table charid of the selection, and owner when it is a follower
--- @return Panel
function DTProjectEditor.PaintRespiteProjects(args)
    local heroId = args.owner or args.charid
    local heroToken = dmhub.GetCharacterById(heroId)

    local list
    local function Rebuild()
        if list ~= nil and list.valid then
            list.children = DTProjectEditor._respiteProjectCards(args)
            list:FireEventTree("refreshProject")
        end
    end

    list = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",

        create = function(element)
            element:FireEventTree("refreshProject")
        end,

        children = DTProjectEditor._respiteProjectCards(args),
    }

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "left",
        valign = "top",
        vscroll = true,

        DTProjectEditor._respiteWatcher(DTShares.GetDocumentPath(), Rebuild),
        DTProjectEditor._respiteWatcher(DTSettings.GetDocumentPath(), Rebuild),
        DTProjectEditor._respiteWatcher(
            heroToken ~= nil and heroToken.monitorPath or nil,
            function()
                if list ~= nil and list.valid then
                    list:FireEventTree("refreshProject")
                end
            end),

        list,
    }
end

--- Everything that moved a project, in the order it happened
--- Rolls and adjustments share a base that stamps serverTime on commit, so the
--- two interleave into one true sequence.
--- @param project DTProject
--- @return table[] items
function DTProjectEditor._projectTimeline(project)
    local items = {}

    for _, roll in ipairs(project:GetRolls() or {}) do
        items[#items + 1] = roll
    end
    for _, adjustment in ipairs(project:GetAdjustments() or {}) do
        items[#items + 1] = adjustment
    end

    table.sort(items, function(a, b)
        return (a.serverTime or 0) < (b.serverTime or 0)
    end)

    return items
end

--- The server time a Respite feed reports from
--- The Respite hands this over as an accessor rather than a number, because a
--- panel can be built before the Respite starts and a captured zero reads as
--- "report everything ever". A plain number is still accepted.
--- @param since number|fun(): number|nil
--- @return number
local function ResolveSince(since)
    if type(since) == "function" then
        return since() or 0
    end
    return since or 0
end

--- What happened on one project inside a window
--- The milestone and the completion are not recorded anywhere: they are the
--- moments the running total crossed a threshold, so the timeline is replayed
--- to find them. Nothing is stored, and nothing can disagree with the project.
--- @param project DTProject
--- @param since number server time to report from
--- @return table[] events {kind, item, total, project}
function DTProjectEditor._projectEvents(project, since)
    local events = {}
    local goal = project:GetProjectGoal() or 0
    local milestone = project:GetMilestoneThreshold() or 0
    local total = 0

    for _, item in ipairs(DTProjectEditor._projectTimeline(project)) do
        local before = total
        total = total + item:GetAmount()

        local recent = (item.serverTime or 0) >= since

        if recent then
            events[#events + 1] = {
                kind = "roll",
                item = item,
                total = total,
                project = project,
            }
        end

        if milestone > 0 and before < milestone and total >= milestone and recent then
            events[#events + 1] = {
                kind = "milestone",
                item = item,
                total = total,
                project = project,
            }
        end

        if goal > 0 and before < goal and total >= goal and recent then
            events[#events + 1] = {
                kind = "complete",
                item = item,
                total = total,
                project = project,
            }
        end
    end

    return events
end

--- The projects a hero owns
--- @param heroToken any
--- @return DTProject[]
function DTProjectEditor._ownedProjects(heroToken)
    if heroToken == nil or heroToken.properties == nil then
        return {}
    end

    local downtimeInfo = heroToken.properties:GetDowntimeInfo()
    if downtimeInfo == nil then
        return {}
    end

    return downtimeInfo:GetSortedProjects() or {}
end

--- Has anything happened on this hero's projects that the Director must act on?
--- Only a milestone or a completion counts, and only on projects this hero
--- owns: those are the conversations the Director has to have.
--- @param args table charid and since
--- @return boolean
function DTProjectEditor.RespiteNeedsAttention(args)
    local heroToken = dmhub.GetCharacterById(args.charid)

    for _, project in ipairs(DTProjectEditor._ownedProjects(heroToken)) do
        for _, event in ipairs(DTProjectEditor._projectEvents(project, ResolveSince(args.since))) do
            if event.kind ~= "roll" then
                return true
            end
        end
    end

    return false
end

--- Trims a name or title so a feed line stays on one row
--- @param text string
--- @param limit number
--- @return string
function DTProjectEditor._respiteShorten(text, limit)
    if text == nil or text == "" then
        return ""
    end
    if #text <= limit then
        return text
    end
    return string.sub(text, 1, limit - 3) .. "..."
end

--- One line in the Director's feed
--- @param event table from _projectEvents
--- @return Panel
function DTProjectEditor._respiteEventRow(event)
    local project = event.project
    local item = event.item
    local goal = project:GetProjectGoal() or 0

    local icon = nil
    local textClass = "fg"
    local text

    -- Kept terse: the pane is narrow and the feed is scanned, not read.
    local title = DTProjectEditor._respiteShorten(project:GetTitle(), 22)

    if event.kind == "milestone" then
        icon = RSPConstants.iconAttention
        textClass = "warning"
        text = string.format("<b>%s</b> milestone %d/%d", title, event.total, goal)
    elseif event.kind == "complete" then
        icon = RSPConstants.iconComplete
        textClass = "success"
        text = string.format("<b>%s</b> complete", title)
    else
        local who = item:try_get("rolledBy")
        if who == nil or who == "" then
            who = "Director"
        end
        text = string.format("%s <b>+%d</b> %s %d/%d",
            DTProjectEditor._respiteShorten(who, 16),
            item:GetAmount(), title, event.total, goal)
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        vmargin = 2,

        gui.Panel{
            classes = {icon == nil and "hidden" or nil,
                event.kind == "complete" and "rspEventGood" or "rspEventAlert"},
            bgimage = icon or RSPConstants.iconAttention,
            width = RSPConstants.eventIconSize,
            height = RSPConstants.eventIconSize,
            halign = "left",
            valign = "center",
            rmargin = 6,
        },

        gui.Label{
            classes = {"sizeS", "noBold", textClass},
            width = "100%-" .. tostring(RSPConstants.eventIconSize + 6),
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = true,
            text = text,
        },
    }
end

--- What this hero got up to during the Respite, newest first
--- Rolls the hero or their followers made anywhere they can reach, plus the
--- milestones and completions on the projects they own. Shared by the
--- Director's feed and the Respite's write-up, so the two can never disagree
--- about what happened.
--- @param args table charid, and since as a server time or a function
--- @return table[] events
function DTProjectEditor._respiteEvents(args)
    local heroToken = dmhub.GetCharacterById(args.charid)
    local since = ResolveSince(args.since)
    local events = {}

    local followers = {}
    if heroToken ~= nil and heroToken.properties ~= nil then
        local constants = rawget(_G, "DTConstants")
        local held = constants ~= nil
            and heroToken.properties:try_get(constants.FOLLOWERS_STORAGE_KEY) or nil
        for followerId, _ in pairs(held or {}) do
            followers[followerId] = true
        end
    end

    --- @param item any a roll or adjustment
    --- @return boolean
    local function RolledByThisHousehold(item)
        local rolledBy = item:try_get("rolledById")
        if rolledBy == args.charid then
            return true
        end
        local follower = item:try_get("rolledByFollowerId")
        return follower ~= nil and followers[follower] == true
    end

    local seen = {}
    local function Gather(project, ownedByHero)
        for _, event in ipairs(DTProjectEditor._projectEvents(project, since)) do
            local keep = false
            if event.kind == "roll" then
                keep = RolledByThisHousehold(event.item)
            else
                -- A milestone belongs to whoever owns the project, whoever
                -- happened to roll it.
                keep = ownedByHero
            end

            local key = string.format("%s:%s", event.kind, event.item:GetID())
            if keep and not seen[key] then
                seen[key] = true
                events[#events + 1] = event
            end
        end
    end

    for _, project in ipairs(DTProjectEditor._ownedProjects(heroToken)) do
        Gather(project, true)
    end

    for _, shared in ipairs(DTBusinessRules.GetSharedProjectsForRecipient(args.charid) or {}) do
        if shared.project ~= nil then
            Gather(shared.project, false)
        end
    end

    table.sort(events, function(a, b)
        return (a.item.serverTime or 0) > (b.item.serverTime or 0)
    end)

    return events
end

--- The Director's feed rows for one hero
--- @param args table charid, and since as a server time or a function
--- @return Panel[] rows
function DTProjectEditor._respiteFeedRows(args)
    local rows = {}
    for _, event in ipairs(DTProjectEditor._respiteEvents(args)) do
        rows[#rows + 1] = DTProjectEditor._respiteEventRow(event)
    end

    if #rows == 0 then
        rows[1] = gui.Label{
            classes = {"sizeS", "noBold", "fgMuted"},
            width = "100%",
            height = "auto",
            halign = "left",
            tmargin = 4,
            text = "Nothing yet this Respite.",
        }
    end

    return rows
end

--- What this household did with its projects, for the Respite's write-up
--- Counted rather than listed: a hero who rolled seven times wants one line
--- saying so, and the milestones and completions are the part worth naming.
--- @param args table charid, and since as a server time or a function
--- @return string[]|nil lines nil when they did nothing
function DTProjectEditor.RespiteJournalSummary(args)
    local rolls = 0
    local named = {}

    for _, event in ipairs(DTProjectEditor._respiteEvents(args) or {}) do
        if event.kind == "roll" then
            rolls = rolls + 1
        elseif event.kind == "milestone" then
            named[#named + 1] = string.format("reached a milestone on %s",
                event.project:GetTitle())
        elseif event.kind == "complete" then
            named[#named + 1] = string.format("completed %s",
                event.project:GetTitle())
        end
    end

    if rolls == 0 and #named == 0 then
        return nil
    end

    local lines = {}
    if rolls > 0 then
        lines[#lines + 1] = string.format("Rolled on downtime projects %d %s",
            rolls, cond(rolls == 1, "time", "times"))
    end
    for _, line in ipairs(named) do
        lines[#lines + 1] = line:gsub("^%l", string.upper)
    end

    return lines
end

--- The Director's view of this hero's downtime projects
--- @param args table charid, and since as a server time
--- @return Panel
function DTProjectEditor.PaintRespiteDirectorFeed(args)
    local list

    local function Rebuild()
        if list ~= nil and list.valid then
            list.children = DTProjectEditor._respiteFeedRows(args)
        end
    end

    list = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        children = DTProjectEditor._respiteFeedRows(args),
    }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",

        DTProjectEditor._respiteWatcher(DTSettings.GetDocumentPath(), Rebuild),
        DTProjectEditor._respiteWatcher(DTShares.GetDocumentPath(), Rebuild),

        list,
    }
end
