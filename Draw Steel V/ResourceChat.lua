local mod = dmhub.GetModLoading()

function ResourceChatMessage.Render(selfInput, message)
    local self = selfInput
    local m_message = message
    local m_undone = self.undone

    local token = self:GetToken()
    local resource = self:GetResource()

    if token == nil or resource == nil then
        return nil
    end

    local resourceIconPanel = gui.Panel{
        refreshUndo = function(element)
            element.selfStyle.bgcolor = cond(self.undone, "grey", "white")
        end,
        bgimage = resource.iconid,
        bgcolor = "white",
        height = 20,
        width = 20,
        valign = "center",
    }

    local resourceLabel = gui.Label{
        classes = {"action-log-detail"},
        refreshUndo = function(element)
            element.selfStyle.strikethrough = cond(self.undone, true, false)
            element.selfStyle.color = cond(self.undone, "grey", "#cccccc")
        end,
        text = string.format("%s: %s %d", token.properties:GetResourceName(resource.id), cond(self.mode == "replenish", tr("gain"), tr("consume")), self.quantity),
    }

    local reasonLabel = nil
    if self.reason ~= "" then
        reasonLabel = gui.Label{
            classes = {"action-log-subtext"},
            text = self.reason,
        }
    end

    local undoButton = gui.Panel{
        bgimage = "panels/hud/anticlockwise-rotation.png",
        bgcolor = "white",
        height = 16,
        width = 16,
        halign = "right",
        valign = "top",
        floating = true,
        refreshUndo = function(element)
            element.selfStyle.bgcolor = cond(self.undone, "grey", "white")
        end,
        click = function()
            self:Undo(m_message)
        end,
    }

    local resourceRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        resourceIconPanel,
        gui.Panel{
            width = 4,
            height = 1,
        },
        resourceLabel,
    }

    local card = CreateActionLogCard{
        token = token,
        content = {resourceRow, reasonLabel, undoButton},
    }

    return gui.Panel{
        classes = {"chat-message-panel"},
        flow = "vertical",
        width = "100%",
        height = "auto",

        refreshMessage = function(element, message)
            m_message = message
            self = message.properties
            if m_undone ~= self.undone then
                m_undone = self.undone
                element:FireEventTree("refreshUndo")
            end
        end,

        card,
    }
end
