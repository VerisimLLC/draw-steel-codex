local mod = dmhub.GetModLoading()

---@class RichCheckbox
RichCheckbox = RegisterGameType("RichCheckbox", "RichTag")
RichCheckbox.tag = "checkbox"
RichCheckbox.pattern = "^\\[(?<value>[xX ])\\](?<space> *)(?<name>[a-zA-Z0-9 ]*)$"

-- Resolve a stylesheet color value (hex or theme token). Mirrors the file-local
-- SkinColor in MarkdownDocument, which is not visible here.
local function CheckColor(c)
    if c == nil or c == false or c == "" then return nil end
    return ThemeEngine.ResolveTokens(c)
end

-- Re-skin the checkbox so it reads on the host sheet's page instead of the app
-- theme. Opt-in: returns nil unless the sheet defines its own page background
-- (page.bgcolor), so the default skin and sheets with no custom page keep the
-- engine-default (app-theme) checkbox -- backward-safe. The fill uses the page
-- color (so the box sits on the page, not the theme's dark @bg); the accent
-- (border + checkmark) uses the sheet's bullet color (its established accent),
-- falling back to link then body color. Mirrors RichMacro's button-skin pattern.
local function CheckboxSkinStyles(base)
    base = base or {}
    local fill = CheckColor((base.page or {}).bgcolor)
    if fill == nil then return nil end
    local accent = CheckColor((base.bullet or {}).color)
        or CheckColor((base.link or {}).color)
        or CheckColor((base.body or {}).color)
        or "#241f17"
    local styles = {
        { selectors = {"checkBackground"}, bgcolor = fill, borderColor = accent, borderWidth = 2 },
        { selectors = {"checkMark"}, bgcolor = accent },
    }
    local label = CheckColor((base.body or {}).color)
    if label ~= nil then
        styles[#styles + 1] = { selectors = {"checkboxLabel"}, color = label }
    end
    return styles
end

function RichCheckbox.CreateDisplay(self)
    local resultPanel

    local m_token
    local m_space
    local m_name
    local m_styled = false

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

            -- Apply the host sheet's checkbox skin (page-aware colors). Assign an
            -- empty table only to clear styles this widget previously applied (live
            -- re-theme styled -> unstyled); a checkbox that was never styled is left
            -- untouched so the default-skin case stays a true no-op. refreshTag fires
            -- every render, so live stylesheet edits flow through. Never assign nil.
            local doc = self:GetDocument()
            local styles = nil
            if doc ~= nil then
                styles = CheckboxSkinStyles((doc:GetResolvedStylesheet().base) or {})
            end
            if styles ~= nil then
                element.styles = styles
                m_styled = true
            elseif m_styled then
                element.styles = {}
                m_styled = false
            end
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