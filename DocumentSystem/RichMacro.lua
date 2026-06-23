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

-- Resolve a stylesheet color value (hex or theme token) to a concrete color.
-- Mirrors MarkdownDocument's file-local SkinColor, which is not visible here.
local function MacroColor(c)
    if c == nil or c == false or c == "" then return nil end
    return ThemeEngine.ResolveTokens(c)
end

-- True when a table has at least one key.
local function MacroHasKeys(t)
    return type(t) == "table" and next(t) ~= nil
end

-- Build a gui instance `styles` array for a macro button from the skin's
-- `button` section. The macro button's chrome (bg/border) and label color live
-- on the {"label","button"} selector (confirmed by the Task 2 spike); the
-- "hover"/"press" variants carry ONLY the overrides -- the selector cascade
-- fills the rest from the base entry. Returns nil when the button skin is
-- unset/empty so the button keeps its engine-default look.
-- box  fields: bgcolor, border, borderColor, cornerRadius, pad
-- text fields: color, size (absolute px), weight ("bold"/"black" -> bold)
local function MacroButtonStyles(b)
    b = b or {}
    local hover, pressed = b.hover or {}, b.pressed or {}
    if not (MacroHasKeys(b.box) or MacroHasKeys(b.text)
            or MacroHasKeys(hover.box) or MacroHasKeys(hover.text)
            or MacroHasKeys(pressed.box) or MacroHasKeys(pressed.text)) then
        return nil
    end
    local styles = {}
    local function add(stateSelector, box, text)
        box, text = box or {}, text or {}
        local sel = { "label", "button" }
        if stateSelector then sel[#sel + 1] = stateSelector end
        local e = { selectors = sel }
        if box.bgcolor then e.bgimage = "panels/square.png"; e.bgcolor = MacroColor(box.bgcolor) end
        if box.border then e.border = box.border end
        if box.borderColor then e.borderColor = MacroColor(box.borderColor) end
        if box.cornerRadius then e.cornerRadius = box.cornerRadius end
        if box.pad ~= nil then e.pad = box.pad end
        if text.color then e.color = MacroColor(text.color) end
        if text.size then e.fontSize = text.size end
        if text.weight == "bold" or text.weight == "black" then e.fontWeight = "bold" end
        styles[#styles + 1] = e
    end
    add(nil, b.box, b.text)                                  -- resting
    if MacroHasKeys(hover.box) or MacroHasKeys(hover.text) then
        add("hover", hover.box, hover.text)
    end
    if MacroHasKeys(pressed.box) or MacroHasKeys(pressed.text) then
        add("press", pressed.box, pressed.text)
    end
    return styles
end
RichMacro.__MacroButtonStyles = MacroButtonStyles


function RichMacro.CreateDisplay(self)
    local resultPanel
    local m_command
    local m_text
    local m_token

    local m_strike = nil
    local m_buttonStyled = false

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

            -- Apply the stylesheet's button skin (resting + hover/pressed) from
            -- the host document. Unset/no-document -> nil styles -> the button
            -- keeps its engine-default look (backward-safe). refreshTag fires
            -- every render, so live stylesheet edits flow through.
            local doc = self:GetDocument()
            local buttonSkin = nil
            if doc ~= nil then
                buttonSkin = (doc:GetResolvedStylesheet().base or {}).button
            end
            -- Apply the resolved button skin. Assign an empty table ONLY to clear
            -- styles previously applied by this widget (live re-theme styled ->
            -- unstyled); a button that was never styled is left untouched so the
            -- common default-skin case stays a true no-op (no phantom style entry,
            -- no per-render overhead). Never assign nil: set_styles rejects it.
            local buttonStyles = MacroButtonStyles(buttonSkin)
            if buttonStyles ~= nil then
                element.styles = buttonStyles
                m_buttonStyled = true
            elseif m_buttonStyled then
                element.styles = {}
                m_buttonStyled = false
            end
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
