local mod = dmhub.GetModLoading()

---@class RichBar
RichBar = RegisterGameType("RichBar", "RichTag")
RichBar.tag = "bar"
RichBar.pattern = "^(?<text>#+-*|#*-+)$"

function RichBar.CreateDisplay(self)
    local m_token
    local m_value = nil
    local m_animValue = nil
    local m_segments = {}
    local m_fill
    local m_count = 0
    m_fill = gui.Panel {
        floating = true,
        width = "0%",
        height = 20,
        bgcolor = "#00EEFF",
        gradient = Styles.grayscaleGradient,
        bgimage = true,
        halign = "left",
        refreshTag = function(element, tag, match, token)
            element.selfStyle.bgcolor = self.GetColorFromToken(token) or "#00EEFF"
        end,

        thinkTime = 0.01,
        think = function(element)
            if m_animValue ~= nil and m_animValue ~= m_value then
                if m_animValue < m_value then
                    m_animValue = math.min(m_animValue + 0.05, m_value)
                else
                    m_animValue = math.max(m_animValue - 0.05, m_value)
                end
                m_fill.selfStyle.width = string.format("%f%%", (m_animValue / m_count) * 100)
            end
        end,
    }
    local successBar = gui.Panel {
        width = 100,
        height = 20,
        valign = "center",
        halign = "left",
        flow = "horizontal",
        bgimage = true,
        bgcolor = "black",
        styles = {
            {
                selectors = { "segment" },
                borderColor = "white",
            },
            {
                selectors = { "segment", "parent:uploading" },
                borderColor = "grey",
            },
        },
        refreshTag = function(element, tag, match, token)
            m_count = #match.text
            local index = string.find(match.text, "-")

            if index ~= nil then
                m_value = index - 1
            else
                m_value = m_count
            end

            element.selfStyle.width = m_count * 100
            while #m_segments < m_count do
                m_segments[#m_segments + 1] = gui.Panel {
                    classes = { "segment" },
                    borderWidth = 1,
                    bgimage = true,
                    bgcolor = "clear",
                    width = 100,
                    height = 20,
                }
            end

            while #m_segments > m_count do
                m_segments[#m_segments] = nil
            end

            local children = { m_fill }
            for _, seg in ipairs(m_segments) do
                children[#children + 1] = seg
            end

            element.children = children

            if m_animValue == nil then
                m_animValue = m_value
                m_fill.selfStyle.width = string.format("%f%%", (m_value / m_count) * 100)
            end
        end,

        m_fill
    }

    local incrementSuccess = function(delta)
        local newValue = math.max(0, math.min(m_value + delta, m_count))
        if m_value == newValue then
            return
        end

        if m_token == nil or self:GetDocument() == nil then
            return
        end

        local doc = self:GetDocument()
        doc:PatchToken(m_token, "[[" .. string.rep("#", newValue) .. string.rep("-", m_count - newValue) .. "]]")
        doc:Upload()
        successBar:SetClass("uploading", true)
    end

    local plusButton
    local minusButton
    if dmhub.isDM then
        minusButton = gui.Label {
            classes = { "plusButton", "dmonly" },
            text = "-",
            bgimage = true,
            click = function(element)
                incrementSuccess(-1)
            end,
            refreshTag = function(element, richTag, patternMatch, token)
                element:SetClass("collapsed", token.player)
            end,
        }

        plusButton = gui.Label {
            classes = { "plusButton", "dmonly" },
            text = "+",
            bgimage = true,
            click = function(element)
                incrementSuccess(1)
            end,
            refreshTag = function(element, richTag, patternMatch, token)
                element:SetClass("collapsed", token.player)
            end,
        }
    end



    local resultPanel

    resultPanel = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
        refreshTag = function(element, tag, match, token)
            self = tag or self
            m_token = token
            successBar:SetClass("uploading", false)
        end,
        styles = {
            {
                selectors = { "plusButton" },
                width = 20,
                height = 20,
                borderWidth = 1,
                borderColor = "white",
                color = "white",
                bgcolor = "black",
                bold = true,
                fontSize = 20,
                textAlignment = "center",
            },
            {
                selectors = { "plusButton", "hover" },
                color = "black",
                bgcolor = "white",
            },
        },

        minusButton,
        successBar,
        plusButton,

    }

    return resultPanel
end

MarkdownDocument.RegisterRichTag(RichBar)