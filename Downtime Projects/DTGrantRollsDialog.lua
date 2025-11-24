--- Grant Rolls Dialog - Dialog for granting downtime rolls to selected characters
--- Provides interface for selecting characters and specifying number of rolls to grant
--- @class DTGrantRollsDialog
DTGrantRollsDialog = RegisterGameType("DTGrantRollsDialog")
DTGrantRollsDialog.__index = DTGrantRollsDialog

--- Creates a new Grant Rolls Dialog instance
--- @return DTGrantRollsDialog instance The new dialog instance
function DTGrantRollsDialog:new()
    local instance = setmetatable({}, self)
    return instance
end

--- Shows the grant rolls dialog modal
function DTGrantRollsDialog:ShowDialog()
    local dialog = self

    local grantRollsDialog = gui.Panel{
        classes = {"dtGrantRollsController", "DTDialog"},
        width = 350,
        height = 450,
        styles = DTHelpers.GetDialogStyles(),
        data = {
            currentRollCount = 1,
        },

        create = function(element)
            dmhub.Schedule(0.1, function()
                element:FireEvent("validateForm")
            end)
        end,

        validateForm = function(element)
            local isValid = false
            local selector = element:Get("characterSelector")
            local numRolls = element.data.currentRollCount or 0
            if selector and selector.value then
                isValid = next(selector.value) ~= nil and numRolls ~= 0
            end
            element:FireEventTree("enableConfirm", isValid, numRolls >= 0 and "Grant" or "Revoke")
        end,

        rollCountChanged = function(element, newValue)
            element.data.currentRollCount = newValue
            element:FireEvent("validateForm")
        end,

        saveAndClose = function(element)
            local numRolls = element.data.currentRollCount or 0
            if numRolls ~= 0 then
                local selector = element:Get("characterSelector")
                if selector and selector.value and next(selector.value) then
                    for tokenId, value in pairs(selector.value) do
                        if value.selected or (value.followers and next(value.followers)) then
                            local token = dmhub.GetCharacterById(tokenId)
                            if token and token.properties then
                                token:ModifyProperties{
                                    description = "Grant Downtime Rolls",
                                    execute = function ()
                                        if value.selected then
                                            local downtimeInfo = token.properties:GetDowntimeInfo()
                                            if downtimeInfo then downtimeInfo:GrantRolls(numRolls) end
                                        end

                                        if value.followers and next(value.followers) then
                                            local followers = token.properties:GetDowntimeFollowers()
                                            if followers then
                                                for followerId, _ in pairs(value.followers) do
                                                    local follower = followers:GetFollower(followerId)
                                                    if follower then
                                                        follower:GrantRolls(numRolls)
                                                    end
                                                end
                                            end
                                        end
                                    end,
                                }
                            end
                        end
                    end
                    DTSettings.Touch()
                    gui.CloseModal()
                end
            end
        end,

        children = {
            gui.Panel {
                classes = {"DTPanel", "DTBase"},
                height = "100%",
                width = "98%",
                valign = "top",
                halign = "center",
                flow = "vertical",
                borderColor = "red",
                children = {
                    -- Header
                    gui.Panel {
                        classes = {"DTPanel", "DTBase"},
                        valign = "top",
                        height = 40,
                        width = "98%",
                        flow = "vertical",
                        borderColor = "blue",
                        children = {
                            gui.Label{
                                text = "Grant Downtime Rolls",
                                width = "100%",
                                height = 30,
                                fontSize = "24",
                                classes = {"DTLabel", "DTBase"},
                                textAlignment = "center",
                                halign = "center",
                                valign = "top",
                            },
                            gui.Divider { width = "50%", },
                        }
                    },

                    -- Content
                    gui.Panel {
                        classes = {"DTPanel", "DTBase"},
                        height = "100%-124",
                        width = "98%",
                        valign="top",
                        flow = "vertical",
                        borderColor = "blue",
                        children = {
                            gui.Panel {
                                classes = {"DTPanelRow", "DTPanel", "DTBase"},
                                height = "auto",
                                borderColor = "yellow",
                                children = {dialog:_buildNumberOfRollsField()}
                            },
                            gui.Panel {
                                classes = {"DTPanelRow", "DTPanel", "DTBase"},
                                height = "auto",
                                borderColor = "yellow",
                                children = {dialog:_createCharacterSelector()}
                            }
                        }
                    },

                    -- Footer
                    gui.Panel{
                        classes = {"DTPanel", "DTBase"},
                        width = "98%",
                        height = 60,
                        halign = "center",
                        valign = "bottom",
                        flow = "horizontal",
                        borderColor = "blue",
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
                                text = "Grant",
                                width = 120,
                                valign = "bottom",
                                classes = {"DTButton", "DTBase", "DTDisabled"},
                                interactable = false,
                                enableConfirm = function(element, enabled, label)
                                    if label and #label then
                                        element.text = label
                                        element:SetClass("DTDanger", string.lower(label) == "revoke")
                                    end
                                    element:SetClass("DTDisabled", not enabled)
                                    element.interactable = enabled
                                end,
                                click = function(element)
                                    if not element.interactable then return end
                                    local controller = element:FindParentWithClass("dtGrantRollsController")
                                    if controller then
                                        controller:FireEvent("saveAndClose")
                                    end
                                end
                            }
                        }
                    }
                }
            }
        },

        escape = function(element)
            gui.CloseModal()
        end
    }

    dialog.dialogElement = grantRollsDialog
    gui.ShowModal(grantRollsDialog)
end

--- Builds the number of rolls input field
--- @return table panel The number of rolls input panel
function DTGrantRollsDialog:_buildNumberOfRollsField()
    return gui.Panel{
        classes = {"DTPanel", "DTBase"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        vmargin = 5,
        halign = "left",

        children = {
            -- Label
            gui.Label{
                text = "Number of Rolls:",
                classes = {"DTLabel", "DTBase"},
                width = "100%",
                height = 20
            },
            -- Input field
            gui.Label {
                id = "numberOfRollsInput",
                editable = true,
                numeric = true,
                characterLimit = 2,
                swallowPress = true,
                text = "1",
                width = 90,
                height = 24,
                cornerRadius = 4,
                fontSize = 20,
                bgimage = "panels/square.png",
                border = 1,
                textAlignment = "center",
                valign = "center",
                halign = "left",
                classes = {"DTInput", "DTBase"},

                change = function(element)
                    local numericValue = tonumber(element.text) or tonumber(element.text:match("%-?%d+")) or 0
                    element.text = tostring(numericValue)

                    local controller = element:FindParentWithClass("dtGrantRollsController")
                    if controller then
                        controller:FireEvent("rollCountChanged", numericValue)
                    end
                end
            }
        }
    }
end

--- Creates the character selector using gui.CharacterSelect
--- @return table panel The character selector panel
function DTGrantRollsDialog:_createCharacterSelector()
    -- Get all hero tokens to display
    local allTokens = DTBusinessRules.GetAllHeroTokens()

    -- Get tokens selected on map and build keyed table for initial selection
    local selectedTokens = dmhub.selectedTokens
    local initialSelectionIds = {}
    for _, token in ipairs(selectedTokens) do
        initialSelectionIds[token.id] = {selected = true}
    end

    local function displayName(token)
        local rolls = 0
        if token and token.properties and token.properties:IsHero() then
            local dt = token.properties:GetDowntimeInfo()
            if dt then rolls = dt:GetAvailableRolls() end
        end
        return string.format("<b>%s</b> (<i>%d %s</i>)", token.name, rolls, rolls == 1 and "Roll" or "Rolls")
    end

    local function displayFollowerText(follower)
        local rolls = 0
        if follower and follower.availableRolls then rolls = tonumber(follower.availableRolls) end
        return string.format("<b>%s</b> (<i>%d %s</i>)", follower.name or "(unnamed follower)", rolls, rolls == 1 and "Roll" or "Rolls")
    end

    local function followerFilter(follower)
        if follower and follower.type and type(follower.type) == "string" then
            local type = follower.type:lower()
            return type == "artisan" or type == "sage"
        end
        return false
    end

    -- Return wrapper panel with CharacterSelector
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        vmargin = 10,
        children = {
            gui.Label{
                text = "Select Recipients:",
                classes = {"DTLabel", "DTBase"},
                width = "100%",
            },
            gui.CharacterSelect({
                id = "characterSelector",
                allTokens = allTokens,
                initialSelection = initialSelectionIds,
                halign = "left",
                width = "100%",
                height = "50%",
                layout = "list",
                displayText = displayName,
                includeFollowers = true,
                followerFilter = followerFilter,
                followerText = displayFollowerText,
                change = function(element, selectedTokenIds)
                    local controller = element:FindParentWithClass("dtGrantRollsController")
                    if controller then
                        controller:FireEvent("validateForm")
                    end
                end,
            })
        }
    }
end