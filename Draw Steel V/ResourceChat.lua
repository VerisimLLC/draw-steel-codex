local mod = dmhub.GetModLoading()

function ResourceChatMessage.Render(selfInput, message)
    local self = selfInput
    local m_message = message
    local m_undone = self.undone

    local token = self:GetToken()

    if token == nil then
        return nil
    end

    local tokenPanel = gui.CreateTokenImage(token,{

        scale = 0.9,
        valign = "center",
        halign = "left",

        interactable = true,
        hover = gui.Tooltip(token.name),

    })

    local resourceIconPanel = gui.Panel{

        refreshUndo = function(element)
            element.selfStyle.bgcolor = cond(self.undone, "grey", "white")
        end,


        bgimage = self:GetResource().iconid,
        bgcolor = "white",
        height = "32",
        width = "32",
        valign = "center",





    }

    local movementLabel = gui.Label{

        fontSize = 18,
        minFontSize = 12,
        width = "auto",
        height = 20,
        maxWidth = 220,
        halign = "center",
        valign = "bottom",
        text = string.format(" %s", self.reason),

    }

    local resourceLabel = gui.Label{

        refreshUndo = function(element)
            element.selfStyle.strikethrough = cond(self.undone, true, false)
            element.selfStyle.color = cond(self.undone, "grey", "white")
        end,

        fontSize = 18,
        width = "auto",
        height = "auto",
        halign = "left",
        text = string.format("%s: %s %d", token.properties:GetResourceName(self:GetResource().id), cond(self.mode == "replenish", tr("gain"), tr("consume")), self.quantity),
        valign = "center",

    }

    local button = gui.Panel{

        bgimage = "panels/hud/anticlockwise-rotation.png",
        bgcolor = "white",
        height = 20,
        width = 20,
        halign = "right",
        floating = true,

        refreshUndo = function(element)
            element.selfStyle.bgcolor = cond(self.undone, "grey", "white")
        end,
        click = function()
            self:Undo(m_message)
        end,

    }

    return gui.Panel{

        classes = {"chat-message-panel"},

        refreshMessage = function(element, message)
            m_message = message
            self = message.properties
            if m_undone ~= self.undone then
                m_undone = self.undone
                element:FireEventTree("refreshUndo")
            end
        end,
        
        flow = "vertical",
        width = "100%",
        height = "auto",

        gui.Panel{
			classes = {'separator'},
		},

        gui.Panel{

            width = "100%",
            height = 65,
            flow = "horizontal",

            tokenPanel,
            gui.Panel{

                width = "auto",
                flow = "vertical",

                gui.Panel{

                    width = 270,
                    height = 25,
                    halign = "center",
                    flow = "horizontal",

                    movementLabel,
                    button,

                },



                gui.Panel{

                    width = "auto",
                    height = 35,

                    flow = "horizontal",

                    resourceIconPanel,
                    resourceLabel,



                },

        



            }


        },

        



    }
end