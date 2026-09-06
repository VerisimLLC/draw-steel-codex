local mod = dmhub.GetModLoading()

---@class RichReminder: RichTag
RichReminder = RegisterGameType("RichReminder", "RichTag")
RichReminder.tag = "reminder"

function RichReminder.Create()
    return RichReminder.new {}
end

function RichReminder.CreateDisplay(self)
    local m_resultPanel
    local m_domain = nil

    m_resultPanel = gui.Panel{
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        refreshTag = function(element, tag, match, token)
            local text = token.text
            local match = regex.MatchGroups(text, "^reminder:(?<domain>.*)$")
            if match then
                local domain = string.lower(match.domain)
                if domain ~= m_domain then
                    m_domain = domain
                    element.children = {
                        gui.ReminderTextPanel{
                            domain = domain,
                            tokens = dmhub.allTokens,
                            height = "auto",
                            maxHeight = 300,
                        }
                    }
                end
            end

        end,
    }

    return m_resultPanel
end

MarkdownDocument.RegisterRichTag(RichReminder)