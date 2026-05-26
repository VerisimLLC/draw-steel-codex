local mod = dmhub.GetModLoading()

local visionPerspectivePanel = nil

dmhub.TokenVisionUpdated = function()
    local tokens = dmhub.tokenVision

    local explanationPanel = nil
    local loggedInAsTokens = false

    if tokens == nil then
        tokens = dmhub.tokensLoggedInAs
        loggedInAsTokens = true
    end

    if tokens == nil then
        if visionPerspectivePanel ~= nil then
            if visionPerspectivePanel.valid then
                visionPerspectivePanel:DestroySelf()
            end
            visionPerspectivePanel = nil
        end
        return
    end

    if visionPerspectivePanel == nil or (not visionPerspectivePanel.valid) then

        if loggedInAsTokens then
            explanationPanel = gui.Label{
                width = 184,
                height = "auto",
                halign = "center",
                fontSize = 12,
                vmargin = 8,
                text = "You are logged in as though you were a player. Close this window to return to being GM.",
            }
        end

        visionPerspectivePanel = gui.Panel{
            classes = {"framedPanel"},

            halign = "left",
            valign = "top",

            width = "auto",
            height = "auto",
            vmargin = 64,
            hmargin = 16,

            flow = "vertical",

            styles = {
                Styles.Panel,
            },

            draggable = true,
            drag = function(element)
                element.x = element.xdrag
                element.y = element.ydrag
            end,

            close = function(element)
                dmhub.Debug("CLEAR TOKEN VISION")
                if loggedInAsTokens then
                    dmhub.tokensLoggedInAs = nil
                else
                    dmhub.tokenVision = nil
                end
            end,

            destroy = function(element)
                if visionPerspectivePanel == element then
                    visionPerspectivePanel = nil
                end
            end,

            gui.Button{
                classes = {"closeButton", "sizeXs"},
                halign = "right",
                valign = "top",
                floating = true,
                escapeActivates = not loggedInAsTokens,
                escapePriority = EscapePriority.EXIT_DIALOG,
                click = function(element)
                    visionPerspectivePanel:FireEvent("close")
                end,
            },

            gui.Panel{
                margin = 8,
                halign = "center",
                valign = "center",
                flow = "vertical",
                width = 200,
                height = "auto",
                gui.Label{
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    color = "white",
                    fontSize = 18,
                    text = cond(loggedInAsTokens, "Player Perspective", "Vision Perspective"),
                },
            },

            gui.Panel{
                width = "90%",
                width = "auto",
                height = "auto",
                flow = "horizontal",
                wrap = true,

                refreshVision = function(element)
                    local newChildren = {}
                    for _,tokid in ipairs(dmhub.tokenVision or dmhub.tokensLoggedInAs or {}) do
                        local token = dmhub.GetTokenById(tokid)
                        if token then
                            local child = gui.CreateTokenImage(token)
                            newChildren[#newChildren+1] = child
                        end
                    end



                    element.children = newChildren
                end,
            },

            explanationPanel,
        }

        gamehud.dialogWorldPanel:AddChild(visionPerspectivePanel)
    end

    visionPerspectivePanel:FireEventTree("refreshVision")
end