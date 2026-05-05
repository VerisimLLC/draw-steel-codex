--- Grant Rolls Dialog - Dialog for granting downtime rolls to selected characters
--- Provides interface for selecting characters and specifying number of rolls to grant
--- @class DTGrantRollsDialog
DTGrantRollsDialog = RegisterGameType("DTGrantRollsDialog")

--- Shows the grant rolls dialog modal
function DTGrantRollsDialog:ShowDialog()
    local dialog = self

    local grantRollsDialog = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        classes = {"dtGrantRollsController", "dialog"},
        width = 600,
        height = 500,
        flow = "vertical",
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

            local isValid = anyHeroSelected or anyFollowerSelected
            if isValid and anyHeroSelected then isValid = heroRolls ~= 0 end
            if isValid and anyFollowerSelected then isValid = followerRolls ~= 0 end

            local buttonLabel = ""
            if isValid then
                if anyHeroSelected then
                    buttonLabel = heroRolls < 0 and "Revoke" or "Grant"
                end
                if anyFollowerSelected then
                    local followerAction = (followerRolls < 0) and "Revoke" or "Grant"
                    if followerAction ~= buttonLabel then
                        if #buttonLabel > 0 then buttonLabel = buttonLabel .. " | " end
                        buttonLabel = buttonLabel .. followerAction
                    end
                end
            else
                buttonLabel = "(invalid)"
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
                for tokenId,value in pairs(selector.value) do
                    local shouldGrantHero = value.selected and heroRolls ~= 0
                    local shouldGrantFollowers = value.followers and next(value.followers) and followerRolls ~= 0

                    if shouldGrantHero or shouldGrantFollowers then
                        local token = dmhub.GetCharacterById(tokenId)
                        if token and token.properties and token.properties:IsHero() then
                            token:ModifyProperties{
                                description = "Grant Downtime Rolls",
                                execute = function ()
                                    local downtimeInfo = token.properties:GetDowntimeInfo()
                                    if downtimeInfo then
                                        -- Grant hero rolls
                                        if shouldGrantHero then
                                            downtimeInfo:GrantRolls(heroRolls)
                                        end

                                        -- Grant follower rolls (now stored on hero's downtimeInfo)
                                        if shouldGrantFollowers then
                                            for followerId,_ in pairs(value.followers) do
                                                downtimeInfo:GrantFollowerRolls(followerId, followerRolls)
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
            gui.Label{
                classes = {"modalTitle"},
                text = "Grant Downtime Rolls",
            },

            -- Content
            gui.Panel {
                width = "98%",
                height = "100%-124",
                valign = "top",
                flow = "vertical",
                children = {
                    gui.Panel {
                        classes = {"formStackedRow"},
                        halign = "center",
                        children = {dialog:_buildRollCountFields()},
                    },
                    gui.Panel {
                        classes = {"formStackedRow"},
                        width = "auto",
                        halign = "center",
                        children = {dialog:_createCharacterSelector()},
                    },
                },
            },

            -- Footer
            gui.Panel{
                width = "98%",
                height = 72,
                halign = "center",
                valign = "bottom",
                flow = "horizontal",
                children = {
                    gui.Button{
                        classes = {"sizeL"},
                        text = "Cancel",
                        valign = "top",
                        click = function(element)
                            gui.CloseModal()
                        end,
                    },
                    gui.Button{
                        classes = {"sizeL", "disabled"},
                        text = "Grant",
                        valign = "top",
                        interactable = false,
                        enableConfirm = function(element, enabled, label)
                            if label and #label > 0 then
                                element.text = label
                                element:SetClass("bgDanger", string.lower(label):find("revoke") ~= nil)
                            end
                            element:SetClass("disabled", not enabled)
                            element.interactable = enabled
                        end,
                        click = function(element)
                            if not element.interactable then return end
                            local controller = element:FindParentWithClass("dtGrantRollsController")
                            if controller then
                                controller:FireEvent("saveAndClose")
                            end
                        end,
                    },
                },
            },
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
        width = "100%",
        height = "auto",
        flow = "horizontal",
        vmargin = 5,
        halign = "left",

        children = {
            -- Grant to Heroes field
            gui.Panel{
                classes = {"formStackedRow"},
                width = "50%",
                children = {
                    gui.Label{
                        classes = {"formStacked"},
                        text = "Grant to Heroes:",
                    },
                    gui.Label {
                        id = "heroRollsInput",
                        classes = {"number", "bordered"},
                        editable = true,
                        numeric = true,
                        characterLimit = 2,
                        swallowPress = true,
                        text = "1",
                        width = 90,
                        height = 24,
                        cornerRadius = 4,
                        fontSize = 20,
                        bgimage = true,
                        border = 1,
                        textAlignment = "center",
                        valign = "center",
                        halign = "left",

                        change = function(element)
                            local numericValue = tonumber(element.text) or tonumber(element.text:match("%-?%d+")) or 0
                            element.text = tostring(numericValue)

                            local controller = element:FindParentWithClass("dtGrantRollsController")
                            if controller then
                                controller:FireEvent("heroRollCountChanged", numericValue)
                            end
                        end,
                    },
                },
            },
            -- Grant to Followers field
            gui.Panel{
                classes = {"formStackedRow"},
                width = "50%",
                children = {
                    gui.Label{
                        classes = {"formStacked"},
                        text = "Grant to Followers:",
                    },
                    gui.Label {
                        id = "followerRollsInput",
                        classes = {"number", "bordered"},
                        editable = true,
                        numeric = true,
                        characterLimit = 2,
                        swallowPress = true,
                        text = "1",
                        width = 90,
                        height = 24,
                        cornerRadius = 4,
                        fontSize = 20,
                        bgimage = true,
                        border = 1,
                        textAlignment = "center",
                        valign = "center",
                        halign = "left",

                        change = function(element)
                            local numericValue = tonumber(element.text) or tonumber(element.text:match("%-?%d+")) or 0
                            element.text = tostring(numericValue)

                            local controller = element:FindParentWithClass("dtGrantRollsController")
                            if controller then
                                controller:FireEvent("followerRollCountChanged", numericValue)
                            end
                        end,
                    },
                },
            },
        },
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

    local function displayName(token, mentor)
        local rolls = 0
        if token and token.properties then
            if token.properties:IsHero() then
                local dt = token.properties:GetDowntimeInfo()
                if dt then rolls = dt:GetAvailableRolls() end
            elseif token.properties:IsFollower() then
                local dt = mentor.properties:GetDowntimeInfo()
                if dt then rolls = dt:GetFollowerRolls(token.id) end
            end
        end
        return string.format("<b>%s</b> (<i>%d %s</i>)", token.name, rolls, rolls == 1 and "Roll" or "Rolls")
    end

    local function displayFollowerText(follower)
        -- Roll count display deferred - not critical for grant dialog
        -- Users select recipients regardless of current count
        return string.format("<b>%s</b>", follower.name or "(unnamed follower)")
    end

    local function followerFilter(token)
        local follower = token.properties
        if follower and follower:try_get("followerType") and type(follower.followerType) == "string" then
            local type = follower.followerType:lower()
            return type == "artisan" or type == "sage"
        end
        return false
    end

    -- Return wrapper panel with CharacterSelector
    return gui.Panel{
        width = 400,
        height = "auto",
        halign = "center",
        valign = "top",
        flow = "vertical",
        vmargin = 10,
        children = {
            gui.Label{
                classes = {"formStacked"},
                text = "Select Recipients:",
            },
            gui.CharacterSelect({
                id = "characterSelector",
                allTokens = allTokens,
                initialSelection = initialSelectionIds,
                width = "98%",
                height = "50%",
                halign = "center",
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