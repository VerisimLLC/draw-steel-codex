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
                assignButtons[#assignButtons+1] = gui.Panel{
                    styles = assignButtonStyles,
                    classes = {"assign-button"},
                    width = "auto",
                    height = 40,
                    lmargin = 8,
                    vpad = 4,
                    press = function(element)
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
                            token:ModifyProperties{
                                description = "Grant a Follower",
                                undoable = false,
                                execute = function()
                                    local newFollower = self.follower:ToTable()
                                    if newFollower.type == "retainer" then newFollower.retainerToken = retainerToken.id end
                                    followers[#followers + 1] = newFollower
                                end
                            }
                            local controller = element:FindParentWithClass("documentPanel")
                            if controller then
                                self.follower:AddAssignedTo(token.id)
                                controller:FireEvent("saveDocument")
                            end
                            resultPanel:FireEventTree("refreshTag")
                        end
                    end,
                    children = {
                        gui.CreateTokenImage(token, {
                            width = 40,
                            height = 40,
                            halign = "left",
                            valign = "center",
                            interactable = true,
                            border = 0,
                            refresh = function(element)
                                if token == nil or not token.valid then return end
                                element:FireEvent("token", token)
                            end
                        }),
                        gui.Label{
                            width = "auto",
                            height = 20,
                            fontSize = 12,
                            valign = "bottom",
                            halign = "left",
                            hmargin = 24,
                            bgimage = "panels/square.png",
                            bgcolor = "#333333",
                            border = 1,
                            borderColor = "white",
                            cornerRadius = 4,
                            text = "Assign to " .. (token.name or "Unnamed Hero"),
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
