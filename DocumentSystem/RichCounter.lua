local mod = dmhub.GetModLoading()

---@class RichCounter
RichCounter = RegisterGameType("RichCounter", "RichTag")
RichCounter.tag = "counter"
RichCounter.pattern = "^(?<number>[0-9]+)$"

function RichCounter.CreateDisplay(self)
    local resultPanel

    local m_token
    local m_styled = false

    resultPanel = gui.Panel{
        classes = {"richCounterFrame", "bg", "fgStrong"},
        width = 64,
        height = 30,
        halign = "left",

        --match the host sheet's page instead of the app theme (opt-in:
        --PageSkinPalette returns nil for default-skin docs, and clearing
        --styles only when we previously applied them keeps the default
        --case a true no-op). refreshTag fires every render, so live
        --stylesheet edits flow through.
        refreshTag = function(element, tag, match, token)
            local pal = MarkdownDocument.PageSkinPalette((tag or self):GetDocument())
            if pal ~= nil then
                element.styles = {
                    { selectors = {"richCounterFrame"}, bgcolor = pal.page },
                    { selectors = {"label"}, color = pal.ink, borderColor = pal.border },
                }
                m_styled = true
            elseif m_styled then
                element.styles = {}
                m_styled = false
            end
        end,

        gui.Label{
            styles = {
                {
                    selectors = {"uploading"},
                    opacity = 0.4,
                }
            },
            classes = {"sizeXl", "bold", "bordered"},
            width = "100%",
            height = "100%",
            textAlignment = "center",
            numeric = true,
            characterLimit = 3,
            editable = dmhub.isDM,
            refreshTag = function(element, tag, match, token)
                self = tag or self
                element.text = match.number
                m_token = token
                element:SetClass("uploading", false)
            end,
            change = function(element)
                local n = tonumber(element.text)
                if n ~= nil then
                    n = round(n)
                end

                n = n or tonumber(element.text) or 0

                if m_token ~= nil and self:GetDocument() ~= nil then
                    local doc = self:GetDocument()
                    doc:PatchToken(m_token, string.format("[[%d]]", n))
                    doc:Upload()
                    element:SetClass("uploading", true)
                end
            end,
        },
    }

    return resultPanel
end


MarkdownDocument.RegisterRichTag(RichCounter)