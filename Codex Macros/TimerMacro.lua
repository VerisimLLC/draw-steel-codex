local mod = dmhub.GetModLoading()

--- @class TimerChatMessage
TimerChatMessage = RegisterGameType("TimerChatMessage")

function TimerChatMessage.Render(self, message)

    local startingAge = dmhub.serverTime - self.timestamp
    local startingTime = dmhub.Time()

    local durationDescription
    if math.floor(self.duration) == self.duration then
        durationDescription = string.format("%d seconds", self.duration)
    else
        durationDescription = string.format("%.2f seconds", self.duration)
    end

    local m_init = false

    local resultPanel

    resultPanel = gui.Panel{
        width = "100%",
        flow = "horizontal",
        gui.Panel{
            flow = "vertical",
            width = 160,
            height = 64,
            halign = "left",
            gui.Label{
                fontSize = 18,
                bold = true,
                text = "Timer",
                width = "auto",
                height = "auto",
                color = Styles.textColor,
                halign = "left",
                valign = "center",
            },
            gui.Label{
                fontSize = 18,
                text = durationDescription,
                color = Styles.textColor,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
            },

            gui.Label{
                fontSize = 18,
                text = string.format("Set by <color=%s>%s</color>", message.nickColor.tostring, message.nick),
                maxWidth = 160,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
            },
        },
        gui.ProgressDice{
            width = 64,
            height = 64,
            halign = "right",
            valign = "bottom",
            cancelalert = function(element)
                element.selfStyle.bgcolor = "white"
                element:FireEventTree("progress", 0)
            end,
            think = function(element)
                local t = startingAge + (dmhub.Time() - startingTime)
                local r = t/self.duration
                if r >= 1 then
                    element.thinkTime = nil

                    if m_init then
                        --it has just expired, so make it red for a moment.
                        element:FireEventTree("progress", 1)
                        element.selfStyle.bgcolor = "red"
                        element:ScheduleEvent("cancelalert", 0.5)
                        return
                    end
                else
                    element.thinkTime = 0.01
                end

                element:FireEventTree("progress", 1 - r)
                m_init = true
            end,
        }
    }

    resultPanel:FireEventTree("think")

    return resultPanel
end

Commands.RegisterMacro{
    name = "timer",
    summary = "start a timer",
    doc = "Usage: /timer [seconds]\nCreates a visible countdown timer in chat. Defaults to 5 seconds.",
    command = function(str)
        local duration = tonumber(str) or 5
        local message = TimerChatMessage.new{
            channel = "chat",
            duration = duration,
            timestamp = dmhub.serverTime,
        }

        chat.SendCustom(message)
    end,
}