---@class RichFollower
RichFollower = RegisterGameType("RichFollower", "RichTag")
RichFollower.tag = "follower"

function RichFollower.Create()
    return RichFollower.new{
        follower = RichFollower._fresh()
    }
end

function RichFollower._fresh()
    return {
        guid = dmhub.GenerateGuid(),
        ancestry = Race.DefaultRace(),
        portrait = "DEFAULT_MONSTER_AVATAR",
        characteristic = "mgt",
        name = "New Follower",
        type = "retainer",
        languages = {},
        skills = {},
        followerToken = "none",
        availableRolls = 0,
        assignedTo = "",
    }
end

function RichFollower:_validate()

    -- Some followers are converting as retainers when they should be artisan or sage
    local function calcFollowerType(follower)
        if follower.type == "retainer" and follower.skills and next(follower.skills) then
            local skillId,_ = next(follower.skills)
            if skillId then
                local skillItem = dmhub.GetTable(Skill.tableName)[skillId]
                if skillItem then
                    if skillItem.category == "lore" then
                        follower.type = "sage"
                    elseif skillItem.category == "crafting" then
                        follower.type = "artisan"
                    end
                end
            end
        end
        return follower.type
    end

    if self.follower == nil then
        self.follower = RichFollower._fresh()
    elseif type(self.follower.try_get) == "function" then
        local newFollower = RichFollower._fresh()
        self.follower = {
            guid = self.follower:try_get("guid", newFollower.guid),
            ancestry = self.follower:try_get("ancestry", newFollower.ancestry),
            portrait = self.follower:try_get("portrait", newFollower.portrait),
            characteristic = self.follower:try_get("characteristic", newFollower.characteristic),
            name = self.follower:try_get("name", newFollower.name),
            type = self.follower:try_get("type", newFollower.type),
            languages = self.follower:try_get("languages", newFollower.languages),
            skills = self.follower:try_get("skills", newFollower.skills),
            followerToken = self.follower:try_get("followerToken", newFollower.followerToken),
            availableRolls = self.follower:try_get("availableRolls", newFollower.availableRolls),
            assignedTo = self.follower:try_get("assignedTo", newFollower.assignedTo),
            retainerToken = self.follower:try_get("retainerToken", "")
        }
        self.follower.type = calcFollowerType(self.follower)
    end
end

function RichFollower.CreateDisplay(self)
    local resultPanel
    self:_validate()

    local assignButtonStyles = {
        {
            priority = 10,
            selectors = {"assign-button"},
            bgimage = "panels/square.png",
            borderWidth = 0,
            cornerRadius = 6,
            pad = 4,
        },
        {
            priority = 10,
            selectors = {"assign-button", "hover"},
            bgcolor = "#333333",
            borderColor = "#666666",
            borderWidth = 1,
            transitionTime = 0.2
        },
        {
            priority = 10,
            selectors = {"assign-button", "press"},
            bgcolor = "#808080",
            borderColor = "#F0F0F0",
            borderWidth = 1,
            transitionTime = 0.2
        },
        {
            priority = 10,
            selectors = {"assign-button-label"},
            bgimage = "panels/square.png",
            bgcolor = "#333333",
            border = 1,
            borderColor = "white",
            cornerRadius = 4,
            fontSize = 12,
            hmargin = 32,
            vmargin = 8,
        },
        {
            priority = 10,
            selectors = {"assign-button-label", "revoke"},
            borderWidth = 1,
            borderColor = "#660000",
            bgcolor = "#330000",
        },
        {
            priority = 10,
            selectors = {"assign-button-label", "press", "revoke"},
            bgcolor = "#660000",
            borderColor = "#990000",
        },
        {
            selectors = {"token-image-frame"},
            borderWidth = 0,
        }
    }

    local titleLabel = gui.Label{
        width = "100%",
        height = 20,
        lmargin = 2,
        hpad = 2,
        halign = "left",
        fontSize = 14,
        refreshTag = function(element)
            element.text = string.format("<b>Follower:</b> %s", self.follower.name)
        end,
    }

    local headerPanel = gui.Panel{
        width = "100%",
        flow = "horizontal",
        height = 20,
        bgimage = true,
        bgcolor = "black",
        borderColor = "white",
        border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},
        titleLabel,
    }

    local detailPanel = gui.Panel{
        width = "100%",
        height = 140,
        fontSize = 12,
        minFontSize = 8,
        pad = 4,
        textAlignment = "topleft",
        flow = "horizontal",
        borderWidth = 1,
        gui.Panel {
            bgimage = "DEFAULT_MONSTER_AVATAR",
            bgcolor = "white",
            halign = "left",
            valign = "top",
            width = 90,
            height = 120,
            refreshTag = function(element)
                element.bgimage = self.follower.portrait
            end,
        },
        gui.Label {
            width = "auto",
            height = "auto",
            valign = "top",
            halign = "left",
            refreshTag = function(element)
                element.text = DescribeFollower(self.follower)
            end,
        },

        refreshEditor = function(element)
            for _, child in ipairs(element.children) do
                child:FireEvent("refreshTag")
            end
        end,
    }

    local assignButtons = {}
    if dmhub.isDM then
        for _, token in ipairs(dmhub.GetTokens{playerControlled = true}) do
            if token.properties and token.properties:IsHero() then

                -- local revokeMode = isFollowerAssignedToHero(token.id)
                -- local label = revokeMode and "Revoke from " or "Assign to "
                -- label = label .. (token.name or "Unnamed Hero")

                assignButtons[#assignButtons+1] = gui.Panel{
                    styles = assignButtonStyles,
                    classes = {"assign-button"},
                    width = "auto",
                    height = 68,
                    lmargin = 8,
                    vpad = 4,
                    data = {
                        revokeMode = false,
                    },
                    refreshTag = function(element)
                        element.data.revokeMode = self.follower.assignedTo == token.id
                    end,
                    press = function(element)
                        if element.data.revokeMode then
                            element:FireEvent("revoke")
                        else
                            element:FireEvent("assign")
                        end
                    end,
                    assign = function(element)
                        self.follower.assignedTo = token.id
                        element:FireEvent("saveDoc")
                        resultPanel:FireEventTree("refreshTag")
                    end,
                    revoke = function(element)
                        self.follower.assignedTo = ""
                        element:FireEvent("saveDoc")
                        resultPanel:FireEventTree("refreshTag")
                    end,
                    saveDoc = function(element)
                        local controller = element:FindParentWithClass("documentPanel")
                        if controller then controller:FireEvent("saveDocument") end
                    end,
                    children = {
                        gui.CreateTokenImage(token, {
                            classes = {"token-image-frame"},
                            width = 64,
                            height = 64,
                            halign = "left",
                            valign = "center",
                            interactable = false,
                            border = 0,
                            borderWidth = 0,
                            refresh = function(element)
                                if token == nil or not token.valid then return end
                                element:FireEvent("token", token)
                            end
                        }),
                        gui.Label{
                            classes = {"assign-button-label"},
                            width = "auto",
                            height = 20,
                            valign = "bottom",
                            halign = "left",
                            text = "calculating...",
                            refreshTag = function(element)
                                local parent = element:FindParentWithClass("assign-button")
                                if parent and token ~= nil and token.valid then
                                    local label = parent.data.revokeMode and "Revoke from " or "Assign to "
                                    element.text = label .. (token.name or "Unnamed Hero")
                                    element:SetClass("revoke", parent.data.revokeMode)
                                end
                            end
                        }
                    },
                }
            end
        end
    end

    local footerPanel = gui.Panel{
        width = "100%",
        height = "auto",
        vpad = 8,
        flow = "horizontal",
        wrap = true,
        children = assignButtons,
    }

    resultPanel = gui.Panel{
        styles = {
            {
                selectors = {"follower-panel"},
                borderWidth = 1,
                borderColor = "#ffffff88",
            },
            {
                selectors = {"hover"},
                borderColor = "white",
                borderWidth = 2,
            },
            {
                selectors = {"focus"},
                borderColor = "yellow",
            }
        },
        classes = {"follower-panel"},
        flow = "vertical",
        width = "98%",
        height = "auto",
        pad = 2,
        halign = "left",
        bgimage = true,
        create = function(element)
            element:FireEventTree("refreshTag")
        end,
        headerPanel,
        detailPanel,
        footerPanel,

        gui.Button {
            text = "Commit Follower to Hero",
            width = "auto",
            height = 30,
            halign = "Center",
            valign = "Bottom",
            interactable = false,
            refreshTag = function(element)
                element.interactable = self.follower.assignedTo ~= ""
            end,

            press = function(element)
                local assignedTo = self.follower.assignedTo
                if assignedTo and type(assignedTo) == "string" then
                    local selectedToken = dmhub.GetTokenById(self.follower.assignedTo)
                    if not selectedToken then return end
                    local followers = selectedToken.properties:GetFollowers()
                    if followers then
                        CreateFollowerMonster(self.follower, self.follower.type, selectedToken, {pregenid = self.follower.retainerType, open = false})    
                    end
                end
            end,
        },
    }

    return resultPanel
end

function RichFollower.CreateEditor(self)
    local resultPanel
    self:_validate()

    local titleLabel = gui.Label {
        width = "100%-14",
        height = 18,
        lmargin = 2,
        halign = "left",
        bold = true,
        fontSize = 14,
        minFontSize = 8,
        refreshEditor = function(element)
            element.text = self.follower.name
        end,
    }
    
    local headerPanel = gui.Panel {
        width = "100%",
        flow = "horizontal",
        height = 18,
        bgimage = true,
        bgcolor = "black",
        borderColor = "white",
        borderWidth = 1,
        titleLabel,
        gui.SettingsButton {
            width = 12,
            height = 12,
            valign = "center",
            halign = "right",
            click = function(element)
                CreateFollowerEditorDialog(self.follower, {save = function ()
                    resultPanel:FireEventTree("refreshEditor")
                end})
            end,
        }
    }

    local detailPanel = gui.Label {
        width = "100%",
        height = "100% available",
        fontSize = 12,
        minFontSize = 8,
        pad = 4,
        textAlignment = "topLeft",
        bgimage = true,
        bgcolor = "clear",
        borderColor = "#ffffff88",
        borderWidth = 1,
        refreshEditor = function(element)
            element.text = DescribeFollower(self.follower)
        end,
    }

    resultPanel = gui.Panel {
        flow = "vertical",
        width = 160,
        height = "100%",
        refreshEditor = function(element, tag)
            self = tag or self
        end,
        headerPanel,
        detailPanel,
    }

    return resultPanel
end

MarkdownDocument.RegisterRichTag(RichFollower)
