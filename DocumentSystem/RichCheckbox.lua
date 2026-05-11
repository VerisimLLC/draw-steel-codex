local mod = dmhub.GetModLoading()

---@class RichCheckbox
RichCheckbox = RegisterGameType("RichCheckbox", "RichTag")
RichCheckbox.tag = "checkbox"
RichCheckbox.pattern = "^\\[(?<value>[xX ])\\](?<space> *)(?<name>[a-zA-Z0-9 ]*)$"

function RichCheckbox.CreateDisplay(self)
    local resultPanel

    local m_token
    local m_space
    local m_name

    resultPanel = gui.Check{
        value = false,
        text = "",
        width = "auto",
        halign = "left",
        refreshTag = function(element, tag, match, token)
            self = tag or self
            m_token = token
            m_space = match.space or ""
            m_name = match.name or ""
            element.data.SetText(match.name)
            element:SetValue(match.value == "x" or match.value == "X", false)
            element:SetClass("uploading", false)
            element:SetClassTree("disabled", token.player)
        end,
        change = function(element)
            local value = element.value
            if m_token ~= nil and self:GetDocument() ~= nil then
                local doc = self:GetDocument()
                doc:PatchToken(m_token, string.format("[%s]%s%s", cond(element.value, "X", " "), m_space, m_name))
                doc:Upload()
                element:SetClass("uploading", true)
            end
        end,
    }

    return resultPanel
end

MarkdownDocument.RegisterRichTag(RichCheckbox)