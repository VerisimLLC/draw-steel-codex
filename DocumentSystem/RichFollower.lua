---@class RichFollower
RichFollower = RegisterGameType("RichFollower", "RichTag")
RichFollower.tag = "follower"

function RichFollower.Create()
    return RichFollower.new{
        follower = Follower.Create(),
    }
end

function RichFollower.CreateDisplay(self)
    local resultPanel

    local function isFollowerAssignedToHero(tokenId)
        local assignedTo = self.follower:try_get("assignedTo")
        if assignedTo then
            local followerId = assignedTo[tokenId]
            return followerId and type(followerId) == "string"
        end
        return false
    end

    local function getFollowerAssignedAsGuid(tokenId)
        local assignedTo = self.follower:try_get("assignedTo")
        if assignedTo then return assignedTo[tokenId] end
        return nil
    end

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
        height = "auto",
        fontSize = 12,
        minFontSize = 8,
        pad = 4,
        textAlignment = "topleft",
        flow = "horizontal",
        borderWidth = 1,
        self.follower.portrait and gui.Panel {
            bgimage = self.follower.portrait,
            bgcolor = "white",
            width = 90,
            height = 120,
            refreshTag = function(element)
                element.bgimage = self.follower.portrait
            end,
        } or nil,
        gui.Label {
            width = self.follower.portrait and "100%-90" or "100%",
            height = "auto",
            valign = "top",
            refreshTag = function(element)
                element.text = self.follower:Describe()
            end,
        },
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
                        revokeMode = isFollowerAssignedToHero(token.id),
                    },
                    refreshTag = function(element)
                        element.data.revokeMode = isFollowerAssignedToHero(token.id)
                    end,
                    press = function(element)
                        if element.data.revokeMode then
                            element:FireEvent("revoke")
                        else
                            element:FireEvent("assign")
                        end
                    end,
                    assign = function(element)
                        local followers = token.properties:GetFollowers()
                        if followers then
                            local retainerToken
                            if self.follower.type == "retainer" then
                                local locs = token.properties:AdjacentLocations()
                                local loc = #locs and locs[1] or token.properties.locsOccupying[1]
                                retainerToken = game.SpawnTokenFromBestiaryLocally(self.follower.retainerToken, loc, {fitLocatoin = true})
                                retainerToken.ownerId = token.ownerId
                                retainerToken.name = self.follower.name
                                retainerToken:UploadToken()
                                game.UpdateCharacterTokens()
                            end
                            local newFollower = self.follower:ToTable()
                            token:ModifyProperties{
                                description = "Grant a Follower",
                                undoable = false,
                                execute = function()
                                    if newFollower.type == "retainer" then newFollower.retainerToken = retainerToken.id end
                                    followers[#followers + 1] = newFollower
                                end
                            }
                            self.follower:AddAssignedTo(token.id, newFollower.guid)
                            element:FireEvent("saveDoc")
                            resultPanel:FireEventTree("refreshTag")
                        end
                    end,
                    revoke = function(element)
                        local followers = token.properties:GetFollowers()
                        if followers then
                            local assignedAsGuid = getFollowerAssignedAsGuid(token.id)
                            if assignedAsGuid and #assignedAsGuid > 0 then
                                token:ModifyProperties{
                                    description = "Revoke a Follwer Grant",
                                    undoable = false,
                                    execute = function()
                                        for i = #followers, 1, -1 do
                                            if followers[i].guid == assignedAsGuid then
                                                table.remove(followers, i)
                                                break
                                            end
                                        end
                                    end
                                }
                                self.follower:RemoveAssignedTo(token.id)
                                element:FireEvent("saveDoc")
                                resultPanel:FireEventTree("refreshTag")
                            end
                        end
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
                            interactable = true,
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
                                if parent then
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
        width = "100%",
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
    }

    return resultPanel
end

function RichFollower.CreateEditor(self)
    local resultPanel

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
                self.follower:CreateEditorDialog{save = function ()
                    resultPanel:FireEventTree("refreshEditor")
                end}
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
            element.text = self.follower:Describe()
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
