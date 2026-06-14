local mod = dmhub.GetModLoading()

---@class RichMacro
RichMacro = RegisterGameType("RichMacro", "RichTag")
RichMacro.tag = "macro"
RichMacro.pattern = "^/(?<strike>[/~])?(?<command>.+)\\|(?<text>.*)$"

-- Entity escapes for interpolating untrusted text (e.g. a player's name) into a
-- [[/command|display]] macro. The markdown rich-tag tokenizer terminates tag
-- content on ']' and the command/display split is on '|', so a literal [ ] or |
-- in interpolated text corrupts the surrounding macro syntax. Callers building a
-- macro from such text run it through RichMacro.Escape; RichMacro.Unescape
-- decodes it again immediately before executing the command or showing the
-- label. The entities contain none of [ ] | so they survive tokenization. '&' is
-- escaped too so the transform round-trips. Order matters: '&' first when
-- escaping, last when unescaping.
local g_macroEscapes = {
    {raw = "&", pat = "&",  entity = "&amp;"},
    {raw = "[", pat = "%[", entity = "&lsqb;"},
    {raw = "]", pat = "%]", entity = "&rsqb;"},
    {raw = "|", pat = "|",  entity = "&vert;"},
}

function RichMacro.Escape(s)
    if s == nil then return s end
    for _, e in ipairs(g_macroEscapes) do
        s = s:gsub(e.pat, e.entity)
    end
    return s
end

function RichMacro.Unescape(s)
    if s == nil then return s end
    for i = #g_macroEscapes, 1, -1 do
        s = s:gsub(g_macroEscapes[i].entity, g_macroEscapes[i].raw)
    end
    return s
end

function RichMacro.CreateDisplay(self)
    local resultPanel
    local m_command
    local m_text
    local m_token

    local m_strike = nil

    resultPanel = gui.Button {
        width = "auto",
        height = "auto",
        pad = 8,
        refreshTag = function(element, tag, match, token)
            m_strike = match.strike
            m_token = token
            -- Keep m_command/m_text in their raw (escaped) form so the strike
            -- write-back in press preserves any escapes; decode only for display.
            m_command = match.command
            m_text = match.text
            local text = RichMacro.Unescape(m_text)
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
                dmhub.Execute(RichMacro.Unescape(m_command))
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
                            dmhub.CopyToClipboard("/" .. RichMacro.Unescape(m_command))
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
