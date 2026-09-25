local mod = dmhub.GetModLoading()

---@class RichBar: RichTag
RichBar = RegisterGameType("RichBar", "RichTag")
RichBar.tag = "bar"
RichBar.pattern = "^(?<text>#+-*|#*-+)$"
RichBar.fillsCell = true

--Width the two DM buttons take off the track; they collapse in the player view.
local BUTTON_RESERVE = 56

--DefaultStyles gives fillBarFill a fixed #484848 -> #C1C1C1 ramp on top of its bgcolor,
--which multiplies an authored page accent down into a muted, dirty version of itself.
--White shades to nothing, so the accent reads as authored. Same rule the divider follows
--in MarkdownDocument: clear the gradient with the colour, or it washes the colour out.
local FLAT_GRADIENT = gui.Gradient{
    point_a = {x = 0, y = 0},
    point_b = {x = 1, y = 0},
    stops = {
        { position = 0, color = "#FFFFFF" },
        { position = 1, color = "#FFFFFF" },
    },
}

local function BarStyles(pal)
    local styles = {
        { selectors = {"fillBar"}, bgcolor = "@bg" },
        { selectors = {"fillBarSegment"}, borderColor = "@fgStrong" },
        { selectors = {"fillBarFill"}, bgcolor = "@accent" },
    }

    if pal ~= nil then
        styles[#styles + 1] = { selectors = {"fillBar"}, bgcolor = pal.wash }
        styles[#styles + 1] = { selectors = {"fillBarSegment"}, borderColor = pal.border }
        styles[#styles + 1] = { selectors = {"fillBarFill"}, bgcolor = pal.accent, gradient = FLAT_GRADIENT }
        styles[#styles + 1] = { selectors = {"label", "~button"}, color = pal.ink }
    end

    return ThemeEngine.MergeTokens(styles)
end

function RichBar.CreateDisplay(self)
    local m_token
    local m_value = nil
    local m_animValue = nil
    local m_segments = {}
    local m_fill
    local m_count = 0
    --Must stay above fillBar: its refreshTag closes over minusButton.
    local plusButton
    local minusButton
    m_fill = gui.Panel {
        classes = {"fillBarFill"},
        floating = true,
        width = "0%",
        height = 20,
        halign = "left",
        refreshTag = function(element, tag, match, token)
            local tokenColor = self.GetColorFromToken(token)
            if tokenColor ~= nil then
                element.selfStyle.bgcolor = tokenColor
            else
                element.selfStyle.bgcolor = nil
            end
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
    local fillBar = gui.Panel {
        classes = {"fillBar"},
        width = "100%",
        height = 20,
        valign = "center",
        halign = "left",
        flow = "horizontal",
        refreshTag = function(element, tag, match, token)
            m_count = #match.text
            local index = string.find(match.text, "-")

            if index ~= nil then
                m_value = index - 1
            else
                m_value = m_count
            end

            local reserve = (minusButton ~= nil and not token.player) and BUTTON_RESERVE or 0
            element.selfStyle.width = reserve > 0 and string.format("100%%-%d", reserve) or "100%"
            --Capped at 100px per segment; only a cramped cell shrinks it below that.
            element.selfStyle.maxWidth = m_count * 100

            while #m_segments < m_count do
                m_segments[#m_segments + 1] = gui.Panel {
                    classes = { "fillBarSegment" },
                    height = 20,
                }
            end

            while #m_segments > m_count do
                m_segments[#m_segments] = nil
            end

            local children = { m_fill }
            for _, seg in ipairs(m_segments) do
                seg.selfStyle.width = string.format("%f%%", 100 / m_count)
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

        --PatchToken does not re-fire refreshTag, so move the value here or the fill never updates.
        m_value = newValue

        local doc = self:GetDocument()
        doc:PatchToken(m_token, "[[" .. string.rep("#", newValue) .. string.rep("-", m_count - newValue) .. "]]")

        fillBar:SetClass("uploading", true)

        --The only other place this class clears is refreshTag, which needs a render to
        --fire -- and a write that fails produces no echo, so no render. Left set, the
        --segment borders stay dimmed to @fgMuted (DefaultStyles' "parent:uploading"
        --rule) until the journal is reopened. The panel can be gone by the time an
        --async callback lands, hence the validity check.
        local function doneUploading()
            if fillBar ~= nil and fillBar.valid then
                fillBar:SetClass("uploading", false)
            end
        end
        doc:Upload(nil, { success = doneUploading, failure = doneUploading })
    end

    if dmhub.isDM then
        minusButton = gui.Button {
            classes = { "sizeXxs" },
            text = "-",
            press = function(element)
                incrementSuccess(-1)
            end,
            refreshTag = function(element, richTag, patternMatch, token)
                element:SetClass("collapsed", token.player)
            end,
        }

        plusButton = gui.Button {
            classes = { "sizeXxs" },
            text = "+",
            press = function(element)
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
        width = "100%",
        height = "auto",
        halign = "left",
        styles = BarStyles(nil),
        refreshTag = function(element, tag, match, token)
            self = tag or self
            m_token = token
            fillBar:SetClass("uploading", false)

            element.selfStyle.maxWidth = (#match.text * 100) + BUTTON_RESERVE

            --Rebuilt every render: BarStyles resolves @bg/@fgStrong/@accent through
            --ThemeEngine.MergeTokens, which snapshots the ACTIVE scheme, so caching on
            --the palette holds the old scheme's hex values across a theme change.
            element.styles = BarStyles(MarkdownDocument.PageSkinPalette(self:GetDocument()))
        end,

        minusButton,
        fillBar,
        plusButton,

    }

    return resultPanel
end

MarkdownDocument.RegisterRichTag(RichBar)