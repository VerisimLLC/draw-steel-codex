local mod = dmhub.GetModLoading()

---@class RichReminder: RichTag
--- @field new fun(o?: table): RichReminder
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
            --no indexes option, so every group is a plain string.
            local match = regex.MatchGroups(text, "^reminder:(?<domain>.*)$") --[[@as table<string, string>?]]
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