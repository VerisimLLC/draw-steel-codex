local mod = dmhub.GetModLoading()

---@type Panel?
local visionPerspectivePanel = nil

--Brings the live map window's Vision Perspective chip (Tabletop.lua) up to
--date; true while it shows the perspective, so this dialog stays out of the
--way. The dialog is still needed with no map window on screen (e.g. the live
--window minimized), and outside a game.
local function ShownInMapWindow()
    return Tabletop ~= nil and Tabletop.IsActive() and Tabletop.RefreshVision()
end

dmhub.TokenVisionUpdated = function()
    local inWindow = ShownInMapWindow()

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
        local closeButton

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
            styles = ThemeEngine.GetStyles(),
            classes = {"framedPanel"},

            halign = "left",
            valign = "top",

            width = "auto",
            height = "auto",
            vmargin = 64,
            hmargin = 16,

            flow = "vertical",

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
                create = function(element)
                    closeButton = element
                end,
                halign = "right",
                valign = "top",
                floating = true,
                escapeActivates = (not loggedInAsTokens) and not inWindow,
                escapePriority = EscapePriority.EXIT_DIALOG,
                click = function(element)
                    --this button lives inside visionPerspectivePanel, which is only cleared once destroyed.
                    ---@cast visionPerspectivePanel -nil
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

        --a holder that keeps thinking while the dialog is collapsed (a
        --collapsed panel does not think): the dialog shows only while no map
        --window shows the chip, e.g. the live window minimized.
        local dialog = visionPerspectivePanel
        local holder = gui.Panel{
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            thinkTime = 0.25,
            think = function(element)
                if dialog.valid then
                    local nowInWindow = ShownInMapWindow()
                    dialog:SetClass("collapsed", nowInWindow)
                    if closeButton ~= nil and closeButton.valid then
                        closeButton.escapeActivates = (not loggedInAsTokens) and not nowInWindow
                    end
                else
                    element:DestroySelf()
                end
            end,
            dialog,
        }
        dialog:SetClass("collapsed", inWindow)

        gamehud.dialogWorldPanel:AddChild(holder)
    end

    visionPerspectivePanel:FireEventTree("refreshVision")
end