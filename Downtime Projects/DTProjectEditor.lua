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
        icon = mod.images.downtimeProjects,
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
                confirm = function(itemId)
                    if itemId and #itemId > 0 then
                        local project, controller = element.data.getProject(element)
                        if project then
                            local item = dmhub.GetTable(equipment.tableName)[itemId]
                            if item then
                                modifyTokenProps{
                                    execute = function()
                                        project:SetTitle(item.name)
                                            :SetItemID(itemId)
                                            :SetItemPrerequisite(item.itemPrerequisite)
                                            :SetProjectSource(item.projectSource)
                                            :SetProjectGoal(tonumber(item.projectGoal:match("^%d+")))
                                            :SetTestCharacteristics(DTHelpers.FlagListToList(item.projectRollCharacteristic))
                                            :SetProjectSourceLanguages(DTBusinessRules.ExtractLanguagesToIds(item.projectSource))
                                    end,
                                }
                                controller:FireEventTree("refreshToken")
                                dmhub.Schedule(0.1, function()
                                    DTSettings.Touch()
                                    DTShares.Touch()
                                end)
                            end
                        end
                    end
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
                hmargin = 4,
            },
            gui.Label {
                classes = {"form"},
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
        width = "98%",
        height = "auto",
        flow = "horizontal",
        valign = "center",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Progress:",
                hmargin = 4,
            },
            gui.Label {
                classes = {"form"},
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
                hmargin = 4,
            },
            gui.Label {
                classes = {"form"},
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
        width = "98%",
        height = "auto",
        flow = "horizontal",
        valign = "center",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Project Roll Characteristic:",
                hmargin = 4,
            },
            gui.Label {
                classes = {"form"},
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
        width = "98%",
        height = "auto",
        flow = "horizontal",
        valign = "center",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Language Penalty:",
                hmargin = 4,
            },
            gui.Label {
                classes = {"form"},
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
        width = "98%",
        height = "auto",
        flow = "horizontal",
        valign = "center",
        children = {
            gui.Label {
                classes = {"form"},
                text = "Status:",
                hmargin = 4,
            },
            gui.Label {
                classes = {"form"},
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
                        width = "33%",
                        height = "auto",
                        children = {titleField}
                    },
                    gui.Panel {
                        width = "34%",
                        height = "auto",
                        children = {statusField}
                    },
                    gui.Panel {
                        width = "33%",
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
                        width = "33%",
                        height = "auto",
                        children = {sourceField}
                    },
                    gui.Panel {
                        width = "34%",
                        height = "auto",
                        children = {languageField}
                    },
                    gui.Panel {
                        width = "33%",
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
                classes = {"featureCardHeader"},
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
                classes = {"featureCardHeader"},
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
                    gui.Panel {
                        width = "12%",
                        height = "auto",
                        halign = "right",
                        children = {
                            self:_createRollButton({
                                confirm = function(rolls, controller, roller)
                                    controller:FireEvent("addRolls", rolls, roller)
                                end
                            }),
                        }
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
function DTProjectEditor:_createRollButton(options)
    options = options or {}
    local confirmCallback = options.confirm
    local width = options.width or 24
    local height = options.height or 24
    local margin = options.margin or 0
    local halign = options.halign or nil
    local hmargin = options.hmargin or nil
    local vmargin = options.vmargin or nil

    return gui.Button{
        classes = {"withInfo"},
        icon = "panels/initiative/initiative-dice.png",
        width = width,
        height = height,
        margin = margin,
        halign = halign,
        hmargin = hmargin,
        vmargin = vmargin,
        data = {
            enabled = false,
            tooltipText = "",
            getDowntimeFollowers = function(element)
                local downtimeController = element:FindParentWithClass("downtimeController")
                if downtimeController then
                    return downtimeController.data.getDowntimeFollowers()
                end
                return nil
            end,
            getDowntimeInfo = function(element)
                local downtimeController = element:FindParentWithClass("downtimeController")
                if downtimeController then
                    return downtimeController.data.getDowntimeInfo()
                end
                return nil
            end,
            getProject = function(element)
                local projectController = element:FindParentWithClass("projectController")
                if projectController then
                    return projectController.data.project
                end
                return nil
            end,
            characterRolls = function(element)
                local downtimeInfo = element.data.getDowntimeInfo(element)
                if downtimeInfo then return downtimeInfo:GetAvailableRolls() end
                return 0
            end,
            followerRolls = function(element)
                local downtimeInfo = element.data.getDowntimeInfo(element)
                if downtimeInfo then return downtimeInfo:AggregateFollowerRolls() end
                return 0
            end,
        },
        create = function(element)
            element:FireEvent("refreshToken")
            dmhub.Schedule(0.2, function()
                element.monitorGame = DTSettings.GetDocumentPath()
            end)
        end,
        refreshGame = function(element)
            element:FireEvent("refreshToken")
        end,
        refreshToken = function(element)
            local isEnabled = false
            element.data.tooltipText = "Project not found?"
            local project = element.data.getProject(element)
            if project then
                local validState, issueList = project:IsValidStateToRoll()
                if validState then
                    local followerRolls = element.data.followerRolls(element)
                    local characterRolls = element.data.characterRolls(element)
                    if followerRolls + characterRolls > 0 then
                        local settings = DTSettings.CreateNew()
                        if settings then
                            if settings:GetPauseRolls() then
                                element.data.tooltipText = "Rolling is currently paused"
                            else
                                element.data.tooltipText = "Make a roll"
                                isEnabled = true
                            end
                        end
                    else
                        element.data.tooltipText = "You have no available rolls"
                    end
                else
                    element.data.tooltipText = table.concat(issueList, " ")
                end
            end
            element.data.enabled = isEnabled
        end,
        linger = function(element)
            if element.data.tooltipText and #element.data.tooltipText then
                gui.Tooltip(element.data.tooltipText)(element)
            end
        end,
        press = function(element)
            if not element.data.enabled then return end
            local project = element.data.getProject(element)
            local controller = element:FindParentWithClass("projectController")
            if project and controller then
                local token = CharacterSheet.instance.data.info.token

                local followersWithRolls = {}
                if token.properties and token.properties.GetDowntimeFollowers then
                    local dtFollowers = token.properties:GetDowntimeFollowers()
                    if dtFollowers then
                        followersWithRolls = dtFollowers:GetFollowersWithAvailbleRolls() or {}
                    end
                end

                local function XshowRollDialog(roller)
                    local options = {
                        attrId = "agl",
                        explanation = "Project roll",
                        title = "Make a project roll",
                        skills = {},
                        languages = {},
                        modifiers = {},
                        silent = true,
                        callback = function(result, boons, banes)
                            print("THC:: RESULT::", result, boons, banes)
                        end,
                    }
                    local followerId = roller:GetFollowerID()
                    local rollingToken = followerId and dmhub.GetTokenById(followerId) or token
                    dmhub.Coroutine(function()
                        rollingToken.properties:RequestProjectRoll(rollingToken, options)
                    end)
                end

                -- Helper function to create and show roll dialog
                local function showRollDialog(roller)
                    local options = {
                        roller = roller,
                        projectTitle = project:GetTitle(),
                        data = {
                            project = project
                        },
                        callbacks = {
                            confirm = function(rolls)
                                if confirmCallback then
                                    confirmCallback(rolls, controller, roller)
                                end
                            end,
                            cancel = function()
                                -- cancel handler
                            end
                        }
                    }
                    CharacterSheet.instance:AddChild(DTProjectRollDialog.CreateAsChild(options))
                end

                -- Check if any followers have rolls (keyed table, so use next())
                local hasFollowersWithRolls = next(followersWithRolls) ~= nil

                -- If no followers with rolls, go straight to roll dialog with character
                if not hasFollowersWithRolls then
                    local roller = DTRoller.CreateNew(token.properties)
                    showRollDialog(roller)
                else
                    -- Build context menu with character + followers
                    local menuItems = {}
                    local parentElement = element

                    -- Add character as first menu item
                    if element.data.characterRolls(element) > 0 then
                        local characterRoller = DTRoller.CreateNew(token.properties)
                        menuItems[#menuItems + 1] = {
                            text = characterRoller:GetName(),
                            click = function(menuElement)
                                showRollDialog(characterRoller)
                                if parentElement.popup then
                                    parentElement.popup = nil
                                end
                            end,
                        }
                    end

                    -- Add each follower with rolls (iterate keyed table with pairs)
                    for _,follower in pairs(followersWithRolls) do
                        local followerRoller = DTRoller.CreateNew(follower.properties, token.id)
                        if followerRoller ~= nil then
                            menuItems[#menuItems + 1] = {
                                text = followerRoller:GetName(),
                                click = function(menuElement)
                                    showRollDialog(followerRoller)
                                    if parentElement.popup then
                                        parentElement.popup = nil
                                    end
                                end,
                            }
                        end
                    end

                    -- Show context menu
                    element.popup = gui.ContextMenu {
                        entries = menuItems,
                    }
                end
            end
        end,
    }
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

--- Creates action buttons for shared project panels (unshare + roll)
--- @param ownerName string The display name of the character who owns this project
--- @param ownerId string The token ID of the character who owns this project
--- @return table buttons Array containing unshare button and roll button elements
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

    local rollButton = self:_createRollButton({
        width = 20,
        height = 20,
        halign = "left",
        hmargin = 5,
        vmargin = 5,
        border = 0,
        confirm = function(rolls, controller, roller)
            local token = dmhub.GetCharacterById(ownerId)
            local project = controller.data.project
            if token and project then
                -- Protect against stale project references
                local downtimeInfo = token.properties:GetDowntimeInfo()
                if downtimeInfo then
                    local p2 = downtimeInfo:GetProject(project:GetID())
                    if p2 then
                        token:ModifyProperties{
                            description = "Downtime project update",
                            execute = function ()
                                p2:AddRolls(rolls)
                            end
                        }
                        local downtimeController = controller:FindParentWithClass("downtimeController")
                        if downtimeController then
                            downtimeController:FireEvent("adjustRolls", -1, roller)
                        end
                    end
                end
                dmhub.Schedule(0.1, function()
                    controller:FireEventTree("refreshToken")
                end)
            end
        end
    })

    return {unshareButton, rollButton}
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

        addRolls = function(element, rolls, roller)
            local downtimeController = element:FindParentWithClass("downtimeController")
            if downtimeController then
                local token = getToken()
                if token then
                    local downtimeInfo = token.properties:GetDowntimeInfo()
                    if downtimeInfo then
                        local project = downtimeInfo:GetProject(element.data.project:GetID())
                        if project then
                            token:ModifyProperties{
                                execute = function()
                                    project:AddRolls(rolls)
                                end,
                            }
                            downtimeController:FireEvent("adjustRolls", -1, roller)
                            dmhub.Schedule(0.2, function()
                                DTSettings.Touch()
                                DTShares.Touch()
                            end)
                        end
                    end
                end
            end
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
