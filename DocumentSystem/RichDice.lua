local mod = dmhub.GetModLoading()

---@class RichDice
RichDice = RegisterGameType("RichDice", "RichTag")
RichDice.tag = "dice"

function RichDice.Create()
    return RichDice.new {}
end

local diceImage = "ui-icons/dsdice/djordice-d10.png"


function RichDice.CreateDisplay(self)
    local dicePanel
    local dice

    dicePanel = gui.Panel {
        width = 74,
        height = 74,
        bgcolor = "clear",
        flow = "vertical",
        halign = "left",
        tmargin = 4,

        gui.Panel {
            width = "100%",
            height = "100%",
            bgimage = diceImage,
            bgcolor = "white",
            opacity = 0.5,

            valign = "center",
            cornerRadius = 8,

            dehover = function(element)
                element.selfStyle.scale = 1
                element.selfStyle.opacity = 0.5
            end,

            refreshTag = function(element, tag, match, token)
                element.selfStyle.bgcolor = self.GetColorFromToken(token) or "white"
                if tag.identifier == false then
                    tag.identifier = "2d10"
                end
                dice = tag.identifier
            end,

            hover = function(element)
                element.selfStyle.scale = 1.05
                element.selfStyle.opacity = 1

                self.popup = gui.Tooltip("Roll " .. dice)(element)
            end,

            click = function(element)
                Commands.roll(dice)
            end,

        }
    }

    return dicePanel
end

function RichDice.CreateEditor(self)

end

MarkdownDocument.RegisterRichTag(RichDice)
