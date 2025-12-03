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
            heroRollCount = 1,
            followerRollCount = 1,
        },

        create = function(element)
            dmhub.Schedule(0.1, function()
                element:FireEvent("validateForm")
            end)
        end,

        validateForm = function(element)
            local selector = element:Get("characterSelector")
            local heroRolls = element.data.heroRollCount or 0
            local followerRolls = element.data.followerRollCount or 0

            -- Determine what's selected
            local anyHeroSelected = false
            local anyFollowerSelected = false

            if selector and selector.value then
                for tokenId, value in pairs(selector.value) do
                    if value.selected then
                        anyHeroSelected = true
                    end
                    if value.followers and next(value.followers) then
                        anyFollowerSelected = true
                    end
                end
            end

            -- Apply validation rules
            local isValid = true
            local buttonLabel = "Grant"

            -- Rule 1: If both numeric fields are 0, disabled
            if heroRolls == 0 and followerRolls == 0 then
                isValid = false
            -- Rule 2: If nothing selected, disabled
            elseif not anyHeroSelected and not anyFollowerSelected then
                isValid = false
            -- Rule 3: If heroes field is 0 and any heroes selected, disabled
            elseif heroRolls == 0 and anyHeroSelected then
                isValid = false
            -- Rule 4: If followers field is 0 and any followers selected, disabled
            elseif followerRolls == 0 and anyFollowerSelected then
                isValid = false
            -- Rule 5: If heroes field non-zero and NO heroes selected, disabled
            elseif heroRolls ~= 0 and not anyHeroSelected then
                isValid = false
            -- Rule 6: If followers field non-zero and NO followers selected, disabled
            elseif followerRolls ~= 0 and not anyFollowerSelected then
                isValid = false
            end

            -- Determine label (Revoke if either value is negative)
            if heroRolls < 0 or followerRolls < 0 then
                buttonLabel = "Revoke"
            end

            element:FireEventTree("enableConfirm", isValid, buttonLabel)
        end,

        heroRollCountChanged = function(element, newValue)
            element.data.heroRollCount = newValue
            element:FireEvent("validateForm")
        end,

        followerRollCountChanged = function(element, newValue)
            element.data.followerRollCount = newValue
            element:FireEvent("validateForm")
        end,

        saveAndClose = function(element)
            local heroRolls = element.data.heroRollCount or 0
            local followerRolls = element.data.followerRollCount or 0

            -- At least one must be non-zero (validation already ensures this)
            if heroRolls == 0 and followerRolls == 0 then return end

            local selector = element:Get("characterSelector")
            if selector and selector.value and next(selector.value) then
                for tokenId, value in pairs(selector.value) do
                    if value.selected or (value.followers and next(value.followers)) then
                        local token = dmhub.GetCharacterById(tokenId)
                        if token and token.properties then
                            token:ModifyProperties{
                                description = "Grant Downtime Rolls",
                                execute = function ()
                                    -- Grant to hero with heroRolls value
                                    if value.selected and heroRolls ~= 0 then
                                        local downtimeInfo = token.properties:GetDowntimeInfo()
                                        if downtimeInfo then downtimeInfo:GrantRolls(heroRolls) end
                                    end

                                    -- Grant to followers with followerRolls value
                                    if value.followers and next(value.followers) and followerRolls ~= 0 then
                                        local followers = token.properties:GetDowntimeFollowers()
                                        if followers then
                                            for followerId, _ in pairs(value.followers) do
                                                local follower = followers:GetFollower(followerId)
                                                if follower then
                                                    follower:GrantRolls(followerRolls)
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
                            gui.Divider { width = "80%", layout = "dot", height = 12 },
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
                                children = {dialog:_buildRollCountFields()}
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

--- Builds the roll count input fields for heroes and followers
--- @return table panel The roll count input panel with two fields
function DTGrantRollsDialog:_buildRollCountFields()
    return gui.Panel{
        classes = {"DTPanel", "DTBase"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        vmargin = 5,
        halign = "left",

        children = {
            -- Grant to Heroes field
            gui.Panel{
                classes = {"DTPanel", "DTBase"},
                width = "50%",
                height = "auto",
                flow = "vertical",
                children = {
                    gui.Label{
                        text = "Grant to Heroes:",
                        classes = {"DTLabel", "DTBase"},
                        width = "100%",
                        height = 20
                    },
                    gui.Label {
                        id = "heroRollsInput",
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
                                controller:FireEvent("heroRollCountChanged", numericValue)
                            end
                        end
                    }
                }
            },
            -- Grant to Followers field
            gui.Panel{
                classes = {"DTPanel", "DTBase"},
                width = "50%",
                height = "auto",
                flow = "vertical",
                children = {
                    gui.Label{
                        text = "Grant to Followers:",
                        classes = {"DTLabel", "DTBase"},
                        width = "100%",
                        height = 20
                    },
                    gui.Label {
                        id = "followerRollsInput",
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
                                controller:FireEvent("followerRollCountChanged", numericValue)
                            end
                        end
                    }
                }
            },
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