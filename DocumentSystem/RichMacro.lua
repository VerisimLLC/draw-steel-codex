local mod = dmhub.GetModLoading()

---@class RichMacro
RichMacro = RegisterGameType("RichMacro", "RichTag")
RichMacro.tag = "macro"
RichMacro.pattern = "^/(?<strike>[/~])?(?<command>.+)\\|(?<text>.*)$"

function RichMacro.CreateDisplay(self)
    local resultPanel
    local m_command
    local m_text
    local m_token

    local m_strike = nil

    resultPanel = gui.Button {
        width = "auto",
        height = "auto",
        fontSize = 16,
        refreshTag = function(element, tag, match, token)
            m_strike = match.strike
            m_token = token
            m_command = match.command
            m_text = match.text
            local text = m_text
            element.selfStyle.halign = token.justification or "left"

            if m_strike == "~" then
                text = "<s>" .. text .. "</s>"
                element.selfStyle.brightness = 0.4
            else
                element.selfStyle.brightness = 1
            end

            element.text = text
        end,
        press = function(element)
            if m_strike ~= "~" then
                dmhub.Execute(m_command)
            end

            if m_strike ~= nil and m_token ~= nil and self:GetDocument() ~= nil then
                local doc = self:GetDocument()
                doc:PatchToken(m_token, string.format("[[/%s%s|%s]]", cond(m_strike == "~", "/", "~"), m_command, m_text))
                doc:Upload()
            end
        end,
        rightClick = function(element)
            element.popup = gui.ContextMenu {
                entries = {
                    {
                        text = "Copy Command",
                        click = function()
                            dmhub.CopyToClipboard("/" .. m_command)
                            element.popup = nil
                        end,
                    }
                }
            }
        end
    }

    return resultPanel
end

MarkdownDocument.RegisterRichTag(RichMacro)
