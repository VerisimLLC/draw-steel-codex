local mod = dmhub.GetModLoading()

--- Standard analytics helper; no-ops when telemetry is disabled, otherwise
--- stamps the common id/version fields onto `fields` and fires the event.
--- @param eventType string
--- @param fields table Event-specific fields (mutated with id fields)
local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

local PLACEHOLDER_TOKEN = "game-icons/griffin-symbol.png"
local TEMP_PLACEHOLDER = "*"
local TRANSPARENT_BG = false

local g_refreshChecklistName = {
    encounter = "encounter",
    round = "round",
}

TacPanel = {}
TacPanelStyles = {}

local TacPanelSizes = {}

TacPanelSizes.Panels = {
    fullWidth = 340,        -- Main panel, full right side width
    summaryNames = 140,     -- Center name panel right of portrait
    stamBoxHeight = 40,
    stamBoxNarrow = 28,
    stamBoxStam = 68,
    stamBoxRecoveries = 128,
    condChipHeight = 16,
}
TacPanelSizes.Fonts = {
    panelTitle = 16,
    charName = 28,          -- Summary info panel
    charLevel = 18,
    charClass = 26,
    charSubclass = 20,

    stamBoxTitle = 10,      -- Stamina panel
    stamBoxInput = 22,
    currentStamina = 24,
    maxStamina = 16,
    recoveryValue = 24,
    recoveryCount = 16,

    tempStamValue = 12,     -- Health bar: temp stam number
    tempStamLabel = 10,     -- Health bar: "TEMP" label
    tempStamClear = 8,      -- Health bar: clear button X

    movePanelTitle = 12,
    movePanelValue = 24,

    charTitle = 12,
    charValue = 30,

    hrChipValue = 12,
    hrChipEvent = 11,
    hrChipFreq = 10,
    growHRTitle = 12,
    grValue = 14,
    grText = 12,

    skillsLangs = 14,

    condName = 11,              -- Conditions panel
    condSetCaster = 10,
    condRemove = 8,
    condAdd = 14,
    condInput = 14,

    menuTitle = 14,             -- Add Condition menu
    menuOption = 14,
    menuSuboption = 11,
    menuSearch = 14,

    resHeading = 12,            -- Weakness/Immunity headings
    resEntry = 12,              -- Weakness/Immunity entries
}
TacPanelSizes.VisionBtn = {
    size = 20,
}
TacPanelSizes.HealthBar = {
    segmentHeight = 10,
    diamondSize = 12,
    separatorWidth = 1,
    statusBoxHeight = 16,
    statusBoxMargin = 4,
    clearBtnSize = 12,
}
TacPanelSizes.HealthIndicator = {
    outerSize = 24,     -- Temp stam backing icon size
    innerSize = 12,     -- Health state icon size
}
TacPanelSizes.TokenIcon = {
    height = 20,
    width = 20,
}
TacPanelSizes.Portrait = {
    height = 120,
}

local g_edsSetting = setting{
    id = "eds",
    default = 50,
    min = 10,
    max = 1000,
    storage = "game",
}

-- All TacPanelStyles.* tables live inside BuildStyles so they can be re-resolved
-- against the active theme/color scheme on an OnThemeChanged event. Called once
-- at load (below) to populate the tables, and again whenever the theme changes.
function TacPanel.BuildStyles()
TacPanelStyles.TacPanel = ThemeEngine.MergeTokens{
    {   -- Outline-button wrapper: themed surface + border (icon button outline).
        selectors = {"tpOutline"},
        bgcolor = "@bgAlt",
        borderColor = "@fgMuted",
    },
    {   -- Outer tac panel. Applies margin, padding, alignment, bottom border.
        selectors = {"panel", "tacpanel"},
        width = "98%",
        height = "auto",
        halign = "left",
        valign = "top",
        hpad = 4,
        vpad = 8,
        flow = "vertical",
        bgimage = true,
        bgcolor = TRANSPARENT_BG and "clear" or "@bg",
        borderColor = "@border",
        border = { x1 = 0, y1 = 1, x2 = 0, y2 = 0 },
    },
    {
        selectors = {"panel", "tacpanel", "alt-bg"},
        bgcolor = TRANSPARENT_BG and "clear" or "@bgAlt",
    },
    {
        selectors = {"panel", "container"},
        width = "auto",
        height = "auto",
        valign = "top",
        halign = "left",
    },
    {
        selectors = {"label", "panel-title"},
        width = "100%-8",
        height = "auto",
        halign = "left",
        valign = "top",
        fontSize = TacPanelSizes.Fonts.panelTitle,
        color = "@fgMuted",
    },
    -- Collapsible title bar
    {
        selectors = {"panel", "tp-title-bar"},
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "horizontal",
        vpad = 0,
    },
    -- Collapse arrow
    {
        selectors = {"tp-expando"},
        hmargin = 8,
        halign = "right",
        valign = "center",
        color = "@fgMuted",
    },
    -- Drag handle
    {
        selectors = {"tp-drag-handle"},
        bgimage = "icons/icon_common/icon_common_4.png",
        bgcolor = "@fgMuted",
        width = 14,
        height = 14,
        halign = "left",
        valign = "center",
        hmargin = 4,
    },
    {
        selectors = {"panel", "tp-title-bar", "drag-target-hover"},
        tmargin = 4,
        vpad = 4,
        border = { x1 = 0, x2 = 0, y1 = 0, y2 = 4 },
        borderColor = "@fg",
        bgimage = true,
    },
}
TacPanelStyles.Tooltip = ThemeEngine.MergeTokens{
    {
        selectors = {"tacpanel-tooltip"},
        bgimage = true,
        bgcolor = "@bgAlt",
        width = 360,
        height = "auto",
        pad = 4,
        flow = "vertical",
    },
    {
        selectors = {"tacpanel-tooltip-text"},
        width = "100%",
        height = "auto",
        fontSize = 16,
    },
}
TacPanelStyles.Portrait = ThemeEngine.MergeTokens{
    {
        selectors = {"panel", "portrait-frame"},
        bgimage = true,
        height = TacPanelSizes.Portrait.height,
        width = string.format("%f%% height", Styles.portraitWidthPercentOfHeight),
        valign = "top",
        halign = "left",
        lmargin = 4,
        bgcolor = "white",
        borderColor = "@border",
        borderWidth = 2,
        cornerRadius = 10,
    },
    {
        selectors = {"panel", "portrait-body"},
        width = "100%-2",
        height = "100%-2",
        valign = "center",
        halign = "center",
        bgcolor = "white",
        cornerRadius = 10,
    },
}
TacPanelStyles.SummaryInfo = ThemeEngine.MergeTokens{
    {
        selectors = {"panel", "summary-info"},
        height = "auto",
        width = TacPanelSizes.Panels.fullWidth,
        valign = "top",
        halign = "center",
        flow = "vertical",
        pad = 6,
    },
    {
        selectors = {"label", "summary-info"},
        fontFace = "@number",
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        textWrap = false,
        minFontSize = 10,
    },
    {
        selectors = {"label", "summary-info", "char-name"},
        fontSize = TacPanelSizes.Fonts.charName,
        color = "@fgStrong",
    },
    {
        selectors = {"label", "summary-info", "level"},
        fontFace = "@label",
        fontSize = TacPanelSizes.Fonts.charLevel,
        color = "@fg",
    },
    {
        selectors = {"label", "summary-info", "class"},
        fontSize = TacPanelSizes.Fonts.charClass,
        color = "@fgMuted",
    },
    {
        selectors = {"label", "summary-info", "subclass"},
        fontSize = TacPanelSizes.Fonts.charSubclass,
        color = "@fgMuted",
    },
    {
        selectors = {"label", "summary-info", "monster-keywords"},
        fontSize = TacPanelSizes.Fonts.charLevel,
        color = "@fgMuted",
    },

}
TacPanelStyles.ControlButtons = ThemeEngine.MergeTokens{
    {   -- bgcolor-only @danger tint (e.g. the "add to combat" icon button).
        -- Unlike bgDanger this does NOT set bgimage, so the icon survives.
        selectors = {"combatTint"},
        bgcolor = "@danger",
    },
    {
        selectors = {"toggle-btn"},
        halign = "left",
        valign = "top",
    },
    {
        selectors = {"toggle-btn", "hover"},
        brightness = 1.5,
        soundEvent = "Mouse.Hover",
    },
    {
        selectors = {"toggle-btn", "press"},
        brightness = 0.5,
        soundEvent = "Mouse.Click",
    },
    {
        selectors = {"light-btn"},
        bgimage = "drawsteel/light-off.png",
        bgcolor = "@fgMuted",
    },
    {
        selectors = {"light-btn", "light-on"},
        bgcolor = "@accent",
    },
    {
        selectors = {"character-sheet-btn"},
        bgimage = "ui-icons/character-sheet.png",
        bgcolor = "@fgPending",
    },
}
TacPanelStyles.TokenBox = ThemeEngine.MergeTokens{
    {
        selectors = {"panel", "tokenbox"},
        height = (TacPanelSizes.Portrait.height / 2) - 2,
        width = 100,
        valign = "top",
        halign = "left",
        bmargin = 4,
        bgimage = true,
        bgcolor = "clear",
        borderColor = "@border",
        borderWidth = 1,
        cornerRadius = 6,
        flow = "vertical",
    },
    {
        selectors = {"label", "tokenbox"},
        color = "@fg",
    },
    {
        selectors = {"label", "tokenbox", "title"},
        width = "98%",
        height = "auto",
        valign = "top",
        halign = "center",
        tmargin = 4,
        fontSize = 12,
        textAlignment = "center",
    },
    {
        selectors = {"panel", "icon"},
        width = TacPanelSizes.TokenIcon.width,
        height = TacPanelSizes.TokenIcon.height,
        valign = "center",
        border = 0,
        bgcolor = "white",
    },
    {
        selectors = {"panel", "icon", "hero-tokens"},
        bgimage = "drawsteel/hero-token.png",
    },
    {
        selectors = {"panel", "icon", "victories"},
        bgimage = "drawsteel/HeroicResources/T_UI_ICON_FLAT_HR_VICTORY.png",
    },
    {
        selectors = {"panel", "icon", "heroic-resources"},
        bgimage = PLACEHOLDER_TOKEN,
    },
    {
        selectors = {"input", "tokenbox", "value"},
        width = "auto",
        height = "auto",
        valign = "top",
        tmargin = -4,
        hmargin = 6,
        pad = 0,
        margin = 0,
        border = 0,
        bgcolor = "clear",
        fontFace = "@number",
        fontSize = 30,
        textAlignment = "center",
        color = "@fg",
    },
    {
        selectors = {"refresh-icon"},
        halign = "right",
        valign = "bottom",
        hmargin = 4,
        vmargin = 4,
    }
}
TacPanelStyles.Stamina = ThemeEngine.MergeTokens{
    {
        selectors = {"panel", "stamina-controls"},
        height = "auto",
        width = "auto", --TacPanelSizes.Panels.fullWidth,
        valign = "top",
        halign = "left",
        flow = "horizontal",
        vpad = 6,
    },
    {
        selectors = {"panel", "stamina-box"},
        height = TacPanelSizes.Panels.stamBoxHeight,
        width = TacPanelSizes.Panels.stamBoxNarrow,
        halign = "left",
        flow = "vertical",
        lmargin = 4,
        rmargin = 2,
        pad = 4,
        bgimage = true,
        bgcolor = "clear",
        borderWidth = 1,
        cornerRadius = 6,
    },
    {
        selectors = {"panel", "stamina-box", "harm"},
        borderColor = "@danger",
    },
    {
        selectors = {"panel", "stamina-box", "stamina"},
        width = TacPanelSizes.Panels.stamBoxStam,
        borderColor = "@success",
    },
    {
        selectors = {"panel", "stamina-box", "heal"},
        borderColor = "@success",
    },
    {
        selectors = {"panel", "stamina-box", "recoveries"},
        width = TacPanelSizes.Panels.stamBoxRecoveries,
        borderColor = "@success",
    },
    {
        selectors = {"panel", "stamina-box", "recoveries", "hover"},
        brightness = 1.5,
        soundEvent = "Mouse.Hover",
    },
    {
        selectors = {"panel", "stamina-box", "recoveries", "press"},
        soundEvent = "Mouse.Click",
    },
    {
        selectors = {"panel", "stamina-box", "temp"},
        borderColor = "@accent",
    },
    {
        selectors = {"label", "stambox-title"},
        width = "98%",
        height = "auto",
        valign = "top",
        halign = "center",
        textAlignment = "center",
        fontSize = TacPanelSizes.Fonts.stamBoxTitle,
        color = "@fg",
    },
    {
        selectors = {"label", "stambox-title", "temp"},
        fontSize = TacPanelSizes.Fonts.stamBoxTitle - 1,
    },
    {
        selectors = {"input", "stambox-input"},
        width = "98%",
        height = "auto",
        halign = "center",
        valign = "center",
        pad = 0,
        margin = 0,
        border = 0,
        bgcolor = "clear",
        fontFace = "@number",
        textAlignment = "center",
        fontSize = TacPanelSizes.Fonts.stamBoxInput,
    },
    {
        selectors = {"stambox-input", "harm"},
        color = "@danger",
    },
    {
        selectors = {"stambox-input", "heal"},
        color = "@success",
    },
    {
        selectors = {"stambox-input", "temp"},
        color = "@fg",
        fontFace = "@number",
        fontSize = 20,
    },
    {
        selectors = {"input", "stambox-stam", "current"},
        height = "auto",
        width = "auto",
        valign = "center",
        halign = "left",
        pad = 0,
        margin = 0,
        border = 0,
        bgcolor = "clear",
        fontFace = "@number",
        fontSize = TacPanelSizes.Fonts.currentStamina,
        color = "@fg",
        textAlignment = "center",
    },
    {
        selectors = {"label", "stambox-stam", "max"},
        height = "auto",
        width = "auto",
        valign = "center",
        lmargin = 4,
        fontFace = "@number",
        fontSize = TacPanelSizes.Fonts.maxStamina,
        color = "@fgPending",
    },
    {
        selectors = {"label", "recovery-value"},
        width = "auto",
        height = "auto",
        valign = "center",
        halign = "center",
        textAlignment = "center",
        fontFace = "@number",
        fontSize = TacPanelSizes.Fonts.recoveryValue,
        color = "@fg",
    },
    {
        selectors = {"label", "recovery-value", "hover"},
        brightness = 1.5,
    },
    {
        selectors = {"input", "recovery-count"},
        width = "33%",
        height = "auto",
        valign = "top",
        halign = "left",
        pad = 0,
        margin = 0,
        border = 0,
        bgcolor = "clear",
        textAlignment = "center",
        fontFace = "@number",
        fontSize = TacPanelSizes.Fonts.recoveryCount,
        color = "@fg",
    },
    {
        selectors = {"label", "recovery-max"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        lmargin = 4,
        textAlignment = "left",
        fontFace = "@number",
        fontSize = TacPanelSizes.Fonts.recoveryCount,
        color = "@fgPending",
    },
    {
        selectors = {"recovery-pip-row"},
        flow = "horizontal",
        width = "auto",
        height = "auto",
        valign = "center",
        halign = "top",
        vmargin = 1,
    },
    {
        selectors = {"recovery-pip"},
        width = 4,
        height = 4,
        hmargin = 1,
        valign = "center",
        bgimage = true,
        borderWidth = 1,
        borderColor = "@success",
    },
    {
        selectors = {"recovery-pip", "filled"},
        bgcolor = "@success",
    },
    -- Health bar styles
    {   -- The outer bar row container
        selectors = {"panel", "health-bar"},
        width = "98%",
        vpad = 8,
        height = "auto",
        flow = "horizontal",
    },
    {   -- Vertical column pairing a segment with its status box
        selectors = {"panel", "health-column"},
        height = "auto",
        flow = "vertical",
        valign = "top",
    },
    {   -- Each segment: outlined box, transparent interior
        selectors = {"panel", "health-segment"},
        width = "100%",
        height = TacPanelSizes.HealthBar.segmentHeight,
        bgimage = true,
        bgcolor = "clear",
        borderWidth = 1,
        flow = "none",
    },
    {
        selectors = {"panel", "health-segment", "dying"},
        borderColor = "@danger",
    },
    {
        selectors = {"panel", "health-segment", "winded"},
        borderColor = "@warning",
    },
    {
        selectors = {"panel", "health-segment", "healthy"},
        borderColor = "@success",
    },
    {   -- The fill panel inside each segment (left-aligned, height 100%)
        selectors = {"panel", "health-fill"},
        height = "100%",
        halign = "left",
        bgimage = true,
    },
    {
        selectors = {"panel", "health-fill", "dying"},
        bgcolor = "@danger",
    },
    {
        selectors = {"panel", "health-fill", "winded"},
        bgcolor = "@warning",
    },
    {
        selectors = {"panel", "health-fill", "healthy"},
        bgcolor = "@success",
    },
    {   -- White separator on right edge of dying and winded segments
        selectors = {"panel", "health-separator"},
        width = TacPanelSizes.HealthBar.separatorWidth,
        height = "100%",
        halign = "right",
        bgimage = true,
        bgcolor = "@border",
    },
    {   -- Health indicator positioner: floating panel whose width% positions the indicator
        selectors = {"panel", "health-indicator-positioner"},
        height = TacPanelSizes.HealthBar.segmentHeight,
        halign = "left",
        valign = "top",
        flow = "none",
    },
    {   -- Bottom layer: temp stam backing icon, visible only with temp HP
        selectors = {"panel", "health-indicator-temp"},
        width = TacPanelSizes.HealthIndicator.outerSize,
        height = TacPanelSizes.HealthIndicator.outerSize,
        halign = "right",
        valign = "center",
        bgimage = "drawsteel/Icon_STA_TempBoost.png",
        bgcolor = "@accent",
        x = TacPanelSizes.HealthIndicator.outerSize / 2,
    },
    {   -- Top layer: health state icon (base, always white)
        selectors = {"panel", "health-indicator-state"},
        width = TacPanelSizes.HealthIndicator.innerSize,
        height = TacPanelSizes.HealthIndicator.innerSize,
        halign = "right",
        valign = "center",
        bgcolor = "white",
        x = TacPanelSizes.HealthIndicator.innerSize / 2,
    },
    {
        selectors = {"panel", "health-indicator-state", "healthy"},
        bgimage = "drawsteel/Icon_STA_Healthy.png",
    },
    {
        selectors = {"panel", "health-indicator-state", "winded"},
        bgimage = "drawsteel/Icon_STA_Winded.png",
    },
    {
        selectors = {"panel", "health-indicator-state", "dying"},
        bgimage = "drawsteel/Icon_STA_Dying.png",
    },
    {   -- Status box base: outlined box with transparent fill, centered label
        selectors = {"panel", "health-status"},
        width = "100%",
        height = TacPanelSizes.HealthBar.statusBoxHeight,
        tmargin = TacPanelSizes.HealthBar.statusBoxMargin,
        bgimage = true,
        borderWidth = 1,
        halign = "left",
        valign = "top",
    },
    {
        selectors = {"panel", "health-status", "winded"},
        borderColor = "@warning",
    },
    {
        selectors = {"panel", "health-status", "dying"},
        borderColor = "@danger",
    },
    {   -- Status label inside the box
        selectors = {"label", "health-status-label"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontSize = TacPanelSizes.Fonts.stamBoxTitle,
    },
    {
        selectors = {"label", "health-status-label", "winded"},
        color = "@warning",
    },
    {
        selectors = {"label", "health-status-label", "dying"},
        color = "@danger",
    },
    {   -- Temp stam box: horizontal layout, TEMP_STAM colors
        selectors = {"panel", "health-status", "temp"},
        borderColor = "@accent",
        flow = "horizontal",
    },
    {
        selectors = {"label", "temp-stam-value"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 6,
        fontFace = "@number",
        fontSize = TacPanelSizes.Fonts.tempStamValue,
        color = "@fg",
    },
    {
        selectors = {"label", "temp-stam-label"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 4,
        fontSize = TacPanelSizes.Fonts.tempStamLabel,
        color = "@accent",
    },
    {   -- Clear button: small square, black bg, purple border
        selectors = {"panel", "temp-stam-clear"},
        width = TacPanelSizes.HealthBar.clearBtnSize,
        height = TacPanelSizes.HealthBar.clearBtnSize,
        halign = "right",
        valign = "center",
        hmargin = 2,
        bgimage = true,
        bgcolor = "clear",
        borderWidth = 1,
        borderColor = "@accent",
    },
    {
        selectors = {"panel", "temp-stam-clear", "parent:hover"},
        collapsed = false,
    },
    {   -- X label inside clear button
        selectors = {"label", "temp-stam-clear-label"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontSize = TacPanelSizes.Fonts.tempStamClear,
        color = "@accent",
    },
}
TacPanelStyles.CharacteristicsPanel = ThemeEngine.MergeTokens{
    {
        selectors = {"panel", "characteristics-panel"},
        height = "auto",
        width = "100%",
        valign = "top",
        halign = "left",
        flow = "horizontal",
        vpad = 6,
    },
    {
        selectors = {"panel", "characteristic-box"},
        width = "16%",
        height = "100% width",
        halign = "left",
        valign = "top",
        pad = 2,
        hmargin = 4,
        flow = "vertical",
        bgimage = true,
        bgcolor = "@bgAlt",
        borderColor = "@border",
        border = 1,
        cornerRadius = 4,
    },
    {
        selectors = {"panel", "characteristic-box", "hover"},
        brightness = 1.5,
        soundEvent = "Mouse.Hover",
    },
    {
        selectors = {"panel", "characteristic-box", "press"},
        soundEvent = "Mouse.Click",
    },
    {
        selectors = {"label", "char-title"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 2,
        color = "@fgMuted",
        fontSize = TacPanelSizes.Fonts.charTitle,
    },
    {
        selectors = {"label", "char-title", "first"},
        fontFace = "DrawSteelPotencies",
        fontSize = TacPanelSizes.Fonts.charTitle + 2,
    },
    {
        selectors = {"label", "char-value"},
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "top",
        color = "@fg",
        fontFace = "@number",
        fontSize = TacPanelSizes.Fonts.charValue,
    },
    {
        selectors = {"label", "char-value", "positive"},
        color = "@fg",
    },
    {
        selectors = {"label", "char-value", "negative"},
        color = "@fg",
    }
}
TacPanelStyles.MovementPanel = ThemeEngine.MergeTokens{
    {
        selectors = {"panel", "movement-panel"},
        height = "auto",
        width = "100%",
        valign = "top",
        halign = "left",
        flow = "horizontal",
        vpad = 0,
    },
    {
        selectors = {"panel", "movement-box"},
        height = 38,
        width = "20%",
        valign = "top",
        halign = "left",
        tmargin = 4,
        rmargin = 6,
        pad = 4,
        flow = "vertical",
    },
    {
        selectors = {"label", "movebox-title"},
        width = "100%",
        height = "auto",
        valign = "top",
        halign = "center",
        color = "@fgMuted",
        fontSize = TacPanelSizes.Fonts.movePanelTitle,
        textAlignment = "center",
    },
    {
        selectors = {"label", "movebox-value"},
        width = "auto",
        height = "auto",
        valign = "center",
        halign = "center",
        fontFace = "@number",
        color = "@fg",
        tmargin = -4,
        fontSize = TacPanelSizes.Fonts.movePanelValue,
    },
    {
        selectors = {"label", "movebox-value", "restricted"},
        color = "@fgMuted",
        strikethrough = true,
    },
    {
        selectors = {"label", "movebox-value", "hindered"},
        lmargin = 4,
        color = "@danger",
    },
    {
        selectors = {"panel", "altitude-row"},
        flow = "horizontal",
        width = "100%",
        height = "auto",
    },
    {
        selectors = {"panel", "altitude-btn-stack"},
        flow = "vertical",
        width = "auto",
        height = "auto",
        valign = "center",
    },
    {
        selectors = {"label", "altitude-btn"},
        bgimage = true,
        width = 20,
        height = 14,
        fontSize = 12,
        bold = true,
        textAlignment = "center",
        cornerRadius = 2,
        borderWidth = 1,
        bgcolor = "@bgInverse",
        borderColor = "@borderInverse",
        color = "@fgInverse",
    },
    {
        selectors = {"label", "altitude-btn", "hover"},
        brightness = 1.5,
        transitionTime = 0.2,
    },
    {
        selectors = {"label", "altitude-btn", "press"},
        brightness = 0.5,
    },
}
TacPanelStyles.HeroicResources = ThemeEngine.MergeTokens{
    {
        selectors = {"panel", "hr-gains"},
        width = "100%-8",
        height = "auto",
        lmargin = 6,
        flow = "vertical",
    },
    {
        selectors = {"panel", "hr-row"},
        width = "100%",
        height = "auto",
        bmargin = 4,
        flow = "horizontal",
    },
    {
        selectors = {"panel", "hr-chip"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        vpad = 1,
        hpad = 6,
        flow = "horizontal",
        bgimage = true,
        border = 1,
        borderColor = "@border",
        cornerRadius = 4,
        bgcolor = "@bgAlt",
    },
    {
        selectors = {"panel", "hr-chip", "completed"},
        bgcolor = "@bgAlt",
        borderColor = "@fgPending",
    },
    {
        selectors = {"label", "hr-chip-value"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        fontFace = "@number",
        fontSize = TacPanelSizes.Fonts.hrChipValue,
        color = "@fg",
    },
    {
        selectors = {"label", "hr-chip-value", "parent:completed"},
        strikethrough = true,
        color = "@fgMuted",
    },
    {
        selectors = {"label", "hr-chip-event"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        hmargin = 4,
        fontSize = TacPanelSizes.Fonts.hrChipEvent,
        color = "@fgStrong",
    },
    {
        selectors = {"label", "hr-chip-event", "parent:completed"},
        strikethrough = true,
        color = "@fgMuted",
    },
    {
        selectors = {"label", "hr-chip-freq"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        hmargin = 4,
        fontSize = TacPanelSizes.Fonts.hrChipFreq,
        color = "@fgPending",
    },
    {
        selectors = {"panel", "growing-resources"},
        width = "100%-8",
        height = "auto",
        halign = "center",
        valign = "top",
        flow = "vertical",
        bgimage = true,
        border = 1,
        borderColor = "@border",
        cornerRadius = 2,
    },
    {
        selectors = {"panel", "gr-title"},
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        vpad = 4,
        flow = "horizontal",
        bgimage = true,
        bgcolor = "clear",
        borderColor = "@border",
        border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},
    },
    {
        selectors = {"label", "gr-title"},
        width = "auto",
        height = "auto",
        halign = "left",
        lmargin = 8,
        fontSize = TacPanelSizes.Fonts.growHRTitle,
        color = "@fgStrong",
        bold = true,
    },
    {
        selectors = {"gr-expando"},
        hmargin = 8,
        halign = "right",
        valign = "center",
        bgcolor = "@fgMuted",
    },
    {
        selectors = {"panel", "gr-row"},
        height = "auto",
        width = "100%",
        valign = "top",
        halign = "left",
        vpad = 4,
        flow = "horizontal",
        bgimage = true,
        borderColor = "@borderInverse",
        border = {x1 = 0, x2 = 0, y1 = 0, y2 = 1},
    },
    {
        selectors = {"panel", "gr-row", "available"},
        brightness = 1.3,
        bgcolor = "@bgAlt",
    },
    {
        selectors = {"label", "gr-value"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 4,
        lmargin = 8,
        hpad = 8,
        vpad = 4,
        textAlignment = "center",
        fontFace = "@number",
        fontSize = TacPanelSizes.Fonts.grValue,
        bold = true,
        color = "@fgMuted",
        bgimage = true,
        border = 1,
        borderColor = "@borderInverse",
        cornerRadius = {x1 = 0, x2 = 0, y1 = 4, y2 = 4},
    },
    {
        selectors = {"label", "gr-value", "parent:available"},
        color = "@accent",
        borderColor = "@accent",
    },
    {
        selectors = {"label", "gr-text"},
        width = "84%",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 4,
        fontSize = TacPanelSizes.Fonts.grText,
        textWrap = true,
        color = "@fgMuted",
    },
    {
        selectors = {"label", "gr-text", "parent:available"},
        color = "@accent",
    }
}
TacPanelStyles.SkillsLanguages = ThemeEngine.MergeTokens{
    {
        selectors = {"label", "skillslangs"},
        width = "94%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 4,
        lmargin = 6,
        fontSize = TacPanelSizes.Fonts.skillsLangs,
        color = "@fg",
    },
}
TacPanelStyles.Notes = ThemeEngine.MergeTokens{
    -- Individual note label (markdown, same pattern as skillslangs)
    {
        selectors = {"label", "note-entry"},
        width = "94%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 4,
        lmargin = 6,
        fontSize = TacPanelSizes.Fonts.skillsLangs,
        color = "@fg",
    },
}
TacPanelStyles.CollapsibleEntry = ThemeEngine.MergeTokens{
    -- Outer entry panel: horizontal so arrow + text sit side by side
    {
        selectors = {"panel", "ce-entry"},
        width = "94%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "horizontal",
        tmargin = 4,
        lmargin = 6,
    },
    -- Collapse arrow (left side, top-aligned with first line of text)
    {
        selectors = {"ce-expando"},
        halign = "left",
        valign = "top",
        tmargin = 3,
        color = "@fgMuted",
    },
    -- Text label (expanded: CREAM base with inline color markup for title)
    {
        selectors = {"label", "ce-text"},
        width = "100%-20",
        height = "auto",
        halign = "left",
        valign = "top",
        lmargin = 4,
        fontSize = TacPanelSizes.Fonts.skillsLangs,
        color = "@fg",
    },
    -- Text label (collapsed: title only, MUTED)
    {
        selectors = {"label", "ce-text", "ce-collapsed"},
        color = "@fgMuted",
    },
}
TacPanelStyles.MultiEdit = ThemeEngine.MergeTokens{
    -- Row containers
    {
        selectors = {"panel", "me-actions"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "center",
        tmargin = 4,
    },
    {
        selectors = {"panel", "me-icon-row"},
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        lmargin = 6,
        tmargin = 4,
    },

    -- Heal/Damage input boxes
    {
        selectors = {"panel", "me-input-box"},
        width = "30%",
        height = 28,
        halign = "center",
        valign = "center",
        bgimage = true,
        border = 1,
        cornerRadius = 4,
        hmargin = 2,
    },
    {
        selectors = {"panel", "me-input-box", "heal"},
        borderColor = "@success",
    },
    {
        selectors = {"panel", "me-input-box", "damage"},
        borderColor = "@danger",
    },
    {
        selectors = {"input", "me-input"},
        width = "100%",
        height = "100%",
        bgcolor = "clear",
        borderWidth = 0,
        borderColor = "clear",
        pad = 0,
        margin = 0,
        fontSize = 12,
        color = "@fg",
        bold = true,
        textAlignment = "center",
    },

    -- Add Condition button
    {
        selectors = {"panel", "me-condition-btn"},
        width = "30%",
        height = 28,
        halign = "center",
        valign = "center",
        bgimage = true,
        border = 1,
        borderColor = "@fgMuted",
        cornerRadius = 4,
        hmargin = 2,
    },
    {
        selectors = {"panel", "me-condition-btn", "hover"},
        brightness = 1.3,
        transitionTime = 0.2,
    },
    {
        selectors = {"label", "me-condition-btn"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontSize = 12,
        color = "@fg",
        bold = true,
    },

    -- Icon button outline wrapper
    {
        selectors = {"panel", "me-icon-wrap"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        lmargin = 4,
        pad = 4,
        bgimage = true,
        bgcolor = "clear",
        border = 1,
        borderColor = "@fgPending",
        cornerRadius = 4,
    },

    -- Squad chip
    {
        selectors = {"panel", "me-squad-row"},
        width = "auto",
        height = 28,
        halign = "left",
        flow = "horizontal",
        tmargin = 4,
        lmargin = 6,
        hpad = 6,
        vpad = 3,
        bgimage = true,
        border = 1,
        borderColor = "@fgPending",
        cornerRadius = 4,
    },
    {
        selectors = {"label", "me-squad-label"},
        width = "auto",
        height = "auto",
        valign = "center",
        fontSize = 12,
        color = "@fgPending",
    },

    -- EDS chip
    {
        selectors = {"panel", "me-eds-chip"},
        width = "auto",
        height = 28,
        halign = "left",
        flow = "horizontal",
        hpad = 6,
        vpad = 3,
        bgimage = true,
        border = 1,
        borderColor = "@fgPending",
        cornerRadius = 4,
    },
    {
        selectors = {"label", "me-eds-label"},
        width = "auto",
        height = "auto",
        valign = "center",
        fontSize = 12,
        color = "@fgMuted",
    },
    {
        selectors = {"label", "me-eds-input"},
        width = 50,
        height = "auto",
        valign = "center",
        fontSize = 12,
        color = "@fg",
    },

    -- EV result chip
    {
        selectors = {"panel", "me-ev-chip"},
        width = "auto",
        height = 28,
        halign = "left",
        flow = "horizontal",
        lmargin = 4,
        hpad = 6,
        vpad = 3,
        bgimage = true,
        border = 1,
        borderColor = "@fgPending",
        cornerRadius = 4,
    },
    {
        selectors = {"label", "me-ev-result"},
        width = "auto",
        height = "auto",
        valign = "center",
        fontSize = 12,
        color = "@fg",
    },
}
TacPanelStyles.Routines = ThemeEngine.MergeTokens{
    -- Visibility-toggle dot tint.
    {
        selectors = {"visDot"},
        bgcolor = "@fg",
    },
    -- Container for routine chips
    {
        selectors = {"panel", "rt-container"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
    },

    -- Routine chip (unselected = dim)
    {
        selectors = {"panel", "rt-chip"},
        width = "auto",
        height = 28,
        flow = "horizontal",
        hpad = 8,
        vpad = 3,
        bgimage = true,
        border = 1,
        borderColor = "@fgPending",
        cornerRadius = 4,
        lmargin = 6,
        tmargin = 4,
    },
    {
        selectors = {"panel", "rt-chip", "hover"},
        brightness = 1.3,
        transitionTime = 0.2,
    },
    {
        selectors = {"panel", "rt-chip", "selected"},
        borderColor = "@border",
    },

    -- Routine chip label
    {
        selectors = {"label", "rt-chip"},
        width = "auto",
        height = "auto",
        valign = "center",
        fontSize = 12,
        color = "@fgMuted",
    },
    {
        selectors = {"label", "rt-chip", "parent:selected"},
        color = "@fgStrong",
    },
}
TacPanelStyles.Conditions = ThemeEngine.MergeTokens{
    {   -- Visibility-toggle dot tint.
        selectors = {"visDot"},
        bgcolor = "@fg",
    },
    {
        selectors = {"panel", "conditions"},
        height = "auto",
        width = TacPanelSizes.Panels.fullWidth,
        valign = "top",
        halign = "center",
        flow = "vertical",
        pad = 6,
    },
    {   -- Horizontal wrap container for chips
        selectors = {"panel", "cond-chips"},
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 6,
        flow = "horizontal",
    },
    {   -- Individual condition chip
        selectors = {"panel", "cond-chip"},
        height = "auto",
        minHeight = TacPanelSizes.Panels.condChipHeight,
        width = "auto",
        halign = "left",
        valign = "top",
        hpad = 6,
        vpad = 3,
        margin = 2,
        flow = "horizontal",
        bgimage = true,
        border = 1,
        borderColor = "@border",
        cornerRadius = 4,
    },
    {
        selectors = {"panel", "cond-chip", "hover"},
        brightness = 1.3,
        transitionTime = 0.2,
    },
    {   -- Condition icon
        selectors = {"panel", "cond-icon"},
        width = 16,
        height = 16,
        valign = "center",
        halign = "left",
    },
    {   -- Condition name + duration label
        selectors = {"label", "cond-name"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 4,
        fontSize = TacPanelSizes.Fonts.condName,
        color = "@fg",
    },
    {   -- Set caster button
        selectors = {"panel", "cond-setCaster"},
        height = 14,
        width = 14,
        halign = "left",
        valign = "center",
        lmargin = 4,
        color = "@border",
        cornerRadius = 2,
    },
    {
        selectors = {"panel", "cond-setCaster", "hover"},
        brightness = 1.5,
        transitionTime = 0.2,
    },
    {
        selectors = {"label", "cond-setCaster"},
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        fontSize = TacPanelSizes.Fonts.condSetCaster,
        color = "@fgMuted",
    },
    {   -- X remove button - hidden until parent hovered
        selectors = {"panel", "cond-remove"},
        width = 14,
        height = 14,
        halign = "left",
        valign = "center",
        lmargin = 4,
        bgimage = true,
        border = 1,
        borderColor = "@danger",
        cornerRadius = 2,
        hidden = 1,
    },
    {
        selectors = {"panel", "cond-remove", "parent:hover"},
        hidden = 0,
    },
    {
        selectors = {"panel", "cond-remove", "hover"},
        brightness = 1.5,
    },
    {
        selectors = {"label", "cond-remove"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontSize = TacPanelSizes.Fonts.condRemove,
        color = "@fg",
    },
    {   -- "No conditions" placeholder
        selectors = {"label", "cond-empty"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 8,
        fontSize = 16,
        color = "@fgMuted",
        bold = false,
        italics = true,
    },
}
TacPanelStyles.AddConditionMenu = ThemeEngine.MergeTokens{
    {   -- Section headings
        selectors = {"label", "menu-heading"},
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        fontSize = TacPanelSizes.Fonts.menuTitle,
        color = "@fgMuted",
        tmargin = 8,
        bmargin = 4,
        lmargin = 8,
    },
    {   -- Condition/effect option row
        selectors = {"label", "menu-option"},
        width = "95%",
        height = 24,
        halign = "center",
        fontSize = TacPanelSizes.Fonts.menuOption,
        color = "@fg",
        bgcolor = "clear",
        bgimage = true,
        cornerRadius = 4,
        hpad = 6,
    },
    {
        selectors = {"label", "menu-option", "hover"},
        brightness = 1.2,
        transitionTime = 0.15,
    },
    {
        selectors = {"label", "menu-option", "press"},
        brightness = 1.4,
    },
    {   -- Duration/rider sub-buttons
        selectors = {"label", "menu-suboption"},
        height = 20,
        minWidth = 36,
        width = "auto",
        fontSize = TacPanelSizes.Fonts.menuSuboption,
        textAlignment = "center",
        color = "@fg",
        bgimage = true,
        bgcolor = "clear",
        border = 1,
        borderColor = "@border",
        cornerRadius = 8,
        hpad = 6,
        lmargin = 4,
    },
    {
        selectors = {"label", "menu-suboption", "hover"},
        bgcolor = "@border",
        brightness = 1.2,
        transitionTime = 0.15,
    },
    {
        selectors = {"label", "menu-suboption", "press"},
        brightness = 1.4,
    },
    {
        selectors = {"label", "menu-suboption", "disabled"},
        color = "@fgMuted",
        borderColor = "@fgMuted",
    },
    {   -- Search input
        selectors = {"input", "menu-search"},
        width = "90%",
        height = "auto",
        halign = "center",
        fontSize = TacPanelSizes.Fonts.menuSearch,
        color = "@fg",
        border = 1,
        borderColor = "@fgMuted",
        cornerRadius = 4,
        hpad = 6,
        vpad = 4,
        bmargin = 6,
    },
    {   -- Divider
        selectors = {"panel", "menu-divider"},
        width = "90%",
        height = 1,
        halign = "center",
        bgimage = true,
        bgcolor = "@fgMuted",
        vmargin = 6,
    },
}
TacPanelStyles.Resistances = ThemeEngine.MergeTokens{
    -- Container: side-by-side
    {
        selectors = {"panel", "res-container"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "center",
        tmargin = 4,
    },

    -- Weakness box
    {
        selectors = {"label", "res-box", "weakness"},
        width = "47%",
        height = "auto",
        halign = "center",
        fontSize = TacPanelSizes.Fonts.resEntry,
        bold = false,
        color = "@fg",
        bgimage = true,
        border = 1,
        borderColor = "@danger",
        cornerRadius = 4,
        hpad = 6,
        vpad = 4,
        hmargin = 4,
    },

    -- Immunity box
    {
        selectors = {"label", "res-box", "immunity"},
        width = "47%",
        height = "auto",
        halign = "center",
        fontSize = TacPanelSizes.Fonts.resEntry,
        bold = false,
        color = "@fg",
        bgimage = true,
        border = 1,
        borderColor = "@success",
        cornerRadius = 4,
        hpad = 6,
        vpad = 4,
        hmargin = 4,
    },
}

-- Health bar fill: grayscale shading (from the OOTB fillBarFill class) tinted
-- by a themed bgcolor per state. Held here so it re-resolves with the scheme.
-- Very purposefully using success / warning / danger for the colors because
-- those are what are documented in the theme documentation apply to these
-- tiers of stamina.
TacPanelStyles.HealthFill = ThemeEngine.MergeTokens{
    {
        selectors = {"fillBarFill", "healthFill"},
        bgcolor = "@success",
    },
    {
        selectors = {"healthFill", "winded"},
        transitionTime = 0.4,
        bgcolor = "@warning",
    },
    {
        selectors = {"healthFill", "dying"},
        transitionTime = 0.4,
        bgcolor = "@danger",
    },
}

end

TacPanel.BuildStyles()

-- The union of every in-tree section style table. Applied once at each tac-panel
-- root (RegisterRoot) so descendants are styled purely by their classes via the
-- cascade -- nothing below needs its own `styles`. Popup-only tables (Tooltip,
-- AddConditionMenu) are applied directly by those popups, which re-root out of
-- the tree and so are not reached by a root cascade.
function TacPanel.AllStyles()
    return TacPanel.MergeStyles{
        TacPanelStyles.TacPanel,
        TacPanelStyles.Portrait,
        TacPanelStyles.SummaryInfo,
        TacPanelStyles.ControlButtons,
        TacPanelStyles.TokenBox,
        TacPanelStyles.Stamina,
        TacPanelStyles.HealthFill,
        TacPanelStyles.Resistances,
        TacPanelStyles.CharacteristicsPanel,
        TacPanelStyles.MovementPanel,
        TacPanelStyles.HeroicResources,
        TacPanelStyles.SkillsLanguages,
        TacPanelStyles.Notes,
        TacPanelStyles.CollapsibleEntry,
        TacPanelStyles.MultiEdit,
        TacPanelStyles.Routines,
        TacPanelStyles.Conditions,
    }
end

-- Theme reactivity: on a theme/color-scheme switch, re-resolve the style tables
-- and reassign each live root's `.styles`, which re-runs the cascade over the
-- whole tac-panel subtree. Inline ThemeEngine.ResolveTokens(...) sites are
-- intentionally NOT reactive.
local g_roots = {}
--- Track a tac-panel root so the OnThemeChanged handler can reassign its styles.
--- @param root Panel
--- @return Panel root The same panel, for inline use
local function RegisterRoot(root)
    g_roots[#g_roots + 1] = root
    return root
end

ThemeEngine.OnThemeChanged(mod, function()
    TacPanel.BuildStyles()
    local live = {}
    for _, r in ipairs(g_roots) do
        if r ~= nil and r.valid then
            r.styles = TacPanel.AllStyles()
            live[#live + 1] = r
        end
    end
    g_roots = live
end)

-- Big text
local HERO_TOKEN_TOOLTIP = [[**Hero Tokens**
* You can spend a hero token to gain two surges.
* You can spend a hero token when you fail a saving throw to succeed instead.
* You can reroll the result of a test. You must use the new result.
* You can spend 2 hero tokens to regain Stamina equal to your Recovery value without spending a Recovery.
]]

--- Build a linger handler that shows an attribute's base value and each
--- modification in a tooltip.
--- @param tokenInfo table Holds the live `.token`
--- @param name string Attribute display name
--- @param GetBaseFunction fun(c: any): number
--- @param DescribeModificationsFunction fun(c: any): table[]
--- @return fun(element: Panel)
local function GenerateAttributeCalculationTooltip(tokenInfo, name, GetBaseFunction, DescribeModificationsFunction)
    return function(element)
        local m_token = tokenInfo.token
        if m_token == nil or (not m_token.valid) then
            return
        end
        local baseValue = GetBaseFunction(m_token.properties)
        local modifications = DescribeModificationsFunction(m_token.properties)

        local panels = {}
        panels[#panels+1] = gui.Label{
            text = string.format("Base %s: %d", name, baseValue),
            width = "auto",
            height = "auto",
            fontSize = 14,
        }
        for _,modification in ipairs(modifications) do
            local text = string.format("%s: %s", modification.key, modification.value)
            panels[#panels+1] = gui.Label{
                text = text,
                width = "auto",
                height = "auto",
                fontSize = 14,
            }
        end

        local container = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            children = panels,
        }

        element.tooltip = gui.TooltipFrame(container)
    end
end

--- As GenerateAttributeCalculationTooltip, for a named custom attribute.
--- @param tokenInfo table Holds the live `.token`
--- @param name string Custom attribute name
--- @return fun(element: Panel)
local function GenerateCustomAttributeCalculationTooltip(tokenInfo, name)
    return GenerateAttributeCalculationTooltip(tokenInfo, name,
        function(c) return c:BaseNamedCustomAttribute(name) end,
        function(c) return c:DescribeModificationsToNamedCustomAttribute(name) end)
end

--- Shrink a font size so `len` characters fit where `maxChars` fit at baseSize.
--- @param baseSize integer The largest size the font might be
--- @param maxChars integer The number of characters the max size can fit
--- @param len integer The length of the text to display
--- @return integer fontSize
local function _fitFontSize(baseSize, maxChars, len)
    if len <= maxChars then return baseSize end
    return math.max(12, math.floor(baseSize * maxChars / len))
end

--- Merge several styles together
--- @param styles table[][] array of style arrays to concatenate
--- @return table[] merged merged array of style arrays
function TacPanel.MergeStyles(styles)
    local result = {}
    for _,styleArray in ipairs(styles) do
        for _,entry in ipairs(styleArray) do
            result[#result + 1] = entry
        end
    end
    return result
end

--- Create a tooltip panel for token resource boxes
--- @param text string
--- @return Panel
function TacPanel.Tooltip(text)
    return gui.Panel{
        styles = TacPanelStyles.Tooltip,
        classes = {"tacpanel-tooltip"},
        gui.Label{
            classes = {"tacpanel-tooltip-text"},
            text = text,
            markdown = true,
        },
    }
end

local g_companionAppSetting = setting{
    id = "companionapp",
    default = false,
    storage = "preference",
}

--- display the portrait
--- @return Panel
function TacPanel.Portrait()

    -- Portrait control buttons are 15% smaller than the standard vision button.
    local visionBtnSize = math.floor(TacPanelSizes.VisionBtn.size * 0.85 + 0.5)

    local function outlineButton(params)
        local btn
        if type(params) ~= "table" then
            btn = params
            params = nil
        end
        local args = {
            classes = {"container", "tpOutline"},
            halign = "left",
            valign = "top",
            lmargin = 3,
            vmargin = 2,
            pad = 3,
            bgimage = true,
            border = 1,
            cornerRadius = 4,
            btn,
        }

        if params ~= nil then
            for k,v in pairs(params) do
                args[k] = v
            end
        end

        return gui.Panel(args)
    end

    local m_companionAppButton = nil
    
    
    if g_companionAppSetting:Get() then
        m_companionAppButton = outlineButton(gui.Panel{
            classes = {"toggle-btn"},
            hoverCursor = "pressbutton",
            bgimage = "ui-icons/codex-logo.png",
            width = visionBtnSize,
            height = visionBtnSize,
            data = { token = nil },
            refreshCharacter = function(element, token)
                element.data.token = token
            end,
            refreshToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
            setToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
            press = function(element)
                local token = element.data.token
                if token == nil then return end
                dmhub.OpenCharacterPopout(token.charid, nil, function(msg)
                    gui.Tooltip("Couldn't open companion: " .. msg)(element)
                end)
            end,
            linger = function(element)
                gui.Tooltip("Open in companion")(element)
            end,
        })
    end

    return gui.Panel{
        classes = {"portrait-frame"},
        refreshCharacter = function(element, token)
            local bg = token.portraitBackground
            if bg == nil or bg == "" then
                element.selfStyle.bgcolor = "clear"
            else
                element.bgimage = bg
                element.selfStyle.bgcolor = "white"
            end
        end,
        gui.Panel{
            classes = {"portrait-body"},
            floating = true,
            refreshCharacter = function(element, token)
                local portrait = token.offTokenPortrait
                element.bgimage = portrait

                if portrait.hasSpineAnimation or (portrait ~= token.portrait and not token.popoutPortrait) then
                    element.selfStyle.imageRect = nil
                else
                    element.selfStyle.imageRect = token:GetPortraitRectForAspect(Styles.portraitWidthPercentOfHeight*0.01, portrait)
                end
            end,
        },


        -- Control buttons at bottom of portrait. Bound the width to the portrait
        -- frame and wrap so a 4th+ button drops to a second row within the avatar.
        gui.Panel{
            classes = {"container"},
            flow = "horizontal",
            wrap = true,
            width = "100%",
            floating = true,
            halign = "left",
            valign = "bottom",
            vmargin = 4,
            outlineButton(gui.Panel{
                id = "char-panel-light-btn",
                classes = {"toggle-btn", "light-btn"},
                hoverCursor = "pressbutton",
                width = visionBtnSize,
                height = visionBtnSize,
                bgimage = "drawsteel/light-off.png",
                refreshCharacter = function(element, token)
                    local lightOn = token.properties.selectedLoadout == 1
                    element.selfStyle.bgimage = lightOn and "drawsteel/light-on.png" or "drawsteel/light-off.png"
                    element:SetClass("light-on", lightOn)
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                press = function(element)
                    Commands.light()
                end,
                linger = function(element)
                    gui.Tooltip("Toggle Light")(element)
                end,
            }),
            outlineButton(gui.Panel{
                classes = {"toggle-btn", "character-sheet-btn"},
                hoverCursor = "pressbutton",
                width = visionBtnSize,
                height = visionBtnSize,
                data = { token = nil },
                refreshCharacter = function(element, token)
                    element.data.token = token
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                press = function(element)
                    local token = element.data.token
                    if token ~= nil then
                        token:ShowSheet()
                    end
                end,
                linger = function(element)
                    gui.Tooltip("Open Character Sheet")(element)
                end,
            }),

            m_companionAppButton,

            outlineButton(gui.Panel{
                classes = {"toggle-btn", "light-btn", "collapsed"},
                hoverCursor = "pressbutton",
                bgimage = "ui-icons/eye.png",
                width = visionBtnSize,
                height = visionBtnSize,
                data = { token = nil, maxLookup = 0 },
                monitor = "lookup",
                events = {
                    monitor = function(element)
                        local cur = dmhub.GetSettingValue("lookup")
                        element:SetClass("light-on", cur >= 1)
                    end,
                },
                refreshCharacter = function(element, token)
                    element.data.token = token
                    local canLookup = dmhub.GetSettingValue("canlookup")
                    if token == nil or (dmhub.isDM and dmhub.tokenVision == nil)
                        or canLookup == "never"
                        or (canLookup == "opening" and token.countFloorsWithVisionAbove <= 0)
                        or (canLookup == "always" and token.countFloorsAbove <= 0) then
                        element:SetClass("collapsed", true)
                        return
                    end
                    element:SetClass("collapsed", false)

                    local maxLookupSetting = dmhub.GetSettingValue("maxlookup")
                    local maxLookup
                    if canLookup == "always" then
                        maxLookup = token.countFloorsAbove
                    else
                        maxLookup = token.countFloorsWithVisionAbove
                    end
                    if maxLookupSetting >= 0 then
                        maxLookup = math.min(maxLookup, maxLookupSetting)
                    end
                    element.data.maxLookup = maxLookup

                    local cur = dmhub.GetSettingValue("lookup")
                    element:SetClass("light-on", cur >= 1)
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                press = function(element)
                    local cur = dmhub.GetSettingValue("lookup")
                    local maxLookup = element.data.maxLookup or 1

                    if maxLookup <= 1 then
                        dmhub.SetSettingValue("lookup", (cur >= 1) and 0 or 1)
                        return
                    end

                    if element.popup ~= nil then
                        element.popup = nil
                        return
                    end

                    local items = {}
                    items[#items+1] = {
                        text = "Forward",
                        click = function()
                            dmhub.SetSettingValue("lookup", 0)
                            element.popup = nil
                        end,
                    }
                    for i = 1, maxLookup do
                        items[#items+1] = {
                            text = "Up " .. tostring(i),
                            click = function()
                                dmhub.SetSettingValue("lookup", i)
                                element.popup = nil
                            end,
                        }
                    end

                    element.popup = gui.ContextMenu{
                        entries = items,
                    }
                end,
                linger = function(element)
                    local cur = dmhub.GetSettingValue("lookup")
                    local maxLookup = element.data.maxLookup or 1
                    local text
                    if cur <= 0 then
                        text = "Look up"
                    elseif maxLookup <= 1 then
                        text = "Look forward"
                    else
                        text = string.format("Up %d / %d (click to cycle)", cur, maxLookup)
                    end
                    gui.Tooltip(text)(element)
                end,
            }),
        },
    }
end

--- display the hero token box
--- @return Panel
function TacPanel.HeroTokenBox()
    return gui.Panel{
        classes = {"tokenbox", "hero-tokens", "collapsed"},
        data = {
            token = nil,
        },

        monitorGame = CharacterResource.GlobalResourcePath(),
        refreshGame = function(element)
            if element.data.token ~= nil then
                element:FireEvent("refreshCharacter", element.data.token)
            end
        end,

        linger = function(element)
            if element.data.token then
                local text = HERO_TOKEN_TOOLTIP
                local history = element.data.token.properties:GetHeroTokenHistory()
                if history ~= nil and #history > 0 then
                    text = text .. "\n<b>Recent Changes:</b>"
                    for _,entry in ipairs(history) do
                        text = string.format("%s\n%s: %d by %s %s", text, entry.note, entry.value, entry.who, entry.when)
                    end
                end
                element.tooltip = TacPanel.Tooltip(text)
            end
        end,

        refreshCharacter = function(element, token)
            element.data.token = token
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end
            local visible = token.properties:IsHero() or token.properties:IsCompanion()
            element:SetClass("collapsed", not visible)
            if visible then
                element:FireEventTree("refreshValue", token)
            end
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        -- Row 1: title
        gui.Label{
            classes = {"tokenbox", "title", "hero-tokens"},
            text = "HERO TOKENS",
        },

        -- Row 2: icon & value
        gui.Panel{
            classes = {"container"},
            halign = "center",
            valign = "top",
            flow = "horizontal",
            gui.Panel{
                classes = {"icon", "hero-tokens"},
            },
            gui.Input{
                classes = {"tokenbox", "value", "hero-tokens"},
                text = "0",
                characterLimit = 2,
                selectAllOnFocus = true,
                placeholderText = "--",
                numeric = true,
                change = function(element)
                    local token = element.parent.parent.data.token
                    if token == nil then return end
                    local n = tonum(element.text, -1)
                    if n >= 0 then
                        local prev = token.properties:GetHeroTokens()
                        token.properties:SetHeroTokens(n, "Set manually")
                        if n ~= prev then
                            local classInfo = token.properties:IsHero() and token.properties:GetClass() or nil
                            track("hero_token_change", {
                                change = n - prev,
                                source = "manual",
                                class = classInfo and classInfo.name or "unknown",
                                dailyLimit = 30,
                            })
                        end
                    end
                    element.textNoNotify = string.format("%d", token.properties:GetHeroTokens())
                end,
                refreshValue = function(element, token)
                    element.textNoNotify = tostring(token.properties:GetHeroTokens())
                end,
            },
        },

        -- Floating: refresh button
        gui.Button{
            classes = {"refresh-icon", "sizeS"},
            floating = true,
            icon = "icons/standard/Icon_App_Undo.png",
            press = function(element)
                local token = element.parent.data.token
                if token ~= nil then
                    local n = dmhub.GetSettingValue("numheroes")
                    local prev = token.properties:GetHeroTokens()
                    token:ModifyProperties{
                        description = "Reset Hero Tokens",
                        execute = function()
                            token.properties:SetHeroTokens(n, "Session Reset")
                        end,
                    }
                    if n ~= prev then
                        local classInfo = token.properties:IsHero() and token.properties:GetClass() or nil
                        track("hero_token_change", {
                            change = n - prev,
                            source = "session_reset",
                            class = classInfo and classInfo.name or "unknown",
                            dailyLimit = 30,
                        })
                    end
                end
            end,
            linger = function(element)
                local n = dmhub.GetSettingValue("numheroes")
                gui.Tooltip(string.format("Reset Hero Tokens For Session (%d heroes)", n))(element)
            end,
        },
    }
end

--- display the surges box
--- @return Panel
function TacPanel.SurgesBox()
    return gui.Panel{
        classes = {"tokenbox", "surges", "collapsed"},
        data = { token = nil },

        linger = function(element)
            if element.data.token then
                local q = dmhub.initiativeQueue
                if q == nil or q.hidden then
                    gui.Tooltip("No surges while not in combat.")(element)
                    return
                end

                element.tooltip = gui.StatsHistoryTooltip{
                    description = "Surges",
                    entries = element.data.token.properties:GetStatHistory(
                        CharacterResource.surgeResourceId):GetHistory(),
                }
            end
        end,

        refreshCharacter = function(element, token)
            element.data.token = token
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end
            local visible = token.properties:IsHero() or token.properties:IsCompanion()
            element:SetClass("collapsed", not visible)
            if visible then
                element:FireEventTree("refreshValue", token)
            end
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        -- Row 1: title
        gui.Label{
            classes = {"tokenbox", "title", "surges"},
            text = "SURGES",
        },

        -- Row 2: icon & value
        gui.Panel{
            classes = {"container"},
            halign = "center",
            flow = "horizontal",
            gui.Panel{
                classes = {"icon"},
                bgimage = "game-icons/surge.png",
            },
            gui.Input{
                classes = {"tokenbox", "value"},
                text = "--",
                characterLimit = 2,
                selectAllOnFocus = true,
                placeholderText = "--",
                numeric = true,
                change = function(element)
                    local token = element.parent.parent.data.token
                    if token == nil then return end
                    local n = tonum(element.text, -1)
                    if n < 0 then
                        element.textNoNotify = tostring(token.properties:GetAvailableSurges())
                        return
                    end
                    local diff = n - token.properties:GetAvailableSurges()
                    if diff ~= 0 then
                        token:ModifyProperties{
                            description = "Change Surges",
                            execute = function()
                                token.properties:ConsumeSurges(-diff, "Manually Set")
                            end,
                        }
                    end
                    element.textNoNotify = tostring(token.properties:GetAvailableSurges())
                end,
                refreshValue = function(element, token)
                    local q = dmhub.initiativeQueue
                    if q == nil or q.hidden then
                        element.editable = false
                        element.textNoNotify = "--"
                    else
                        element.editable = true
                        element.textNoNotify = tostring(token.properties:GetAvailableSurges())
                    end
                end,
            },
        },
    }
end

--- Display the victories box
--- @return Panel
function TacPanel.VictoriesBox()
    return gui.Panel{
        classes = {"tokenbox", "victories"},

        -- Row 1: title
        gui.Label{
            classes = {"tokenbox", "title", "victories"},
            text = "VICTORIES",
        },

        -- Row 2: icon & value
        gui.Panel{
            classes = {"container"},
            halign = "center",
            flow = "horizontal",
            gui.Panel{
                classes = {"icon", "victories"},
            },
            gui.Input{
                classes = {"tokenbox", "value"},
                text = "0",
                characterLimit = 2,
                selectAllOnFocus = true,
                placeholderText = "--",
                numeric = true,
                data = { token = nil },
                refreshCharacter = function(element, token)
                    element.data.token = token
                    element.textNoNotify = string.format("%d", token.properties:GetVictories())
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                change = function(element)
                    local token = element.data.token
                    if token == nil then return end
                    local n = tonum(element.text, -1)
                    if n < 0 then
                        element:FireEvent("refreshCharacter", token)
                        return
                    end
                    if n ~= token.properties:GetVictories() then
                        token:ModifyProperties{
                            description = "Set Victories",
                            execute = function()
                                token.properties:SetVictories(n)
                                element.textNoNotify = string.format("%d", token.properties:GetVictories())
                            end,
                        }
                    else
                        element.textNoNotify = string.format("%d", token.properties:GetVictories())
                    end
                end,
                refreshValue = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
            },
        },
    }
end

--- Display the Heroic Resources box
--- @return Panel
function TacPanel.HeroicResourcesBox()
    return gui.Panel{
        classes = {"tokenbox", "heroic-resources"},
        data = { token = nil },

        refreshCharacter = function(element, token)
            element.data.token = token
        end,

        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        linger = function(element)
            local token = element.data.token
            if token == nil then return end
            local q = dmhub.initiativeQueue
            if q == nil or q.hidden then
                gui.Tooltip(string.format("No %s while not in combat.", token.properties:GetHeroicResourceName()))(element)
                return
            end
            local desc = token.properties:GetHeroicResourceName()
            local negativeValue = token.properties:CalculateNamedCustomAttribute("Negative Heroic Resource")
            local text = nil
            if negativeValue > 0 then
                text = string.format("%s may go as low as -%d", desc, negativeValue)
            end
            element.tooltip = gui.StatsHistoryTooltip{
                text = text,
                description = desc,
                entries = token.properties:GetStatHistory(CharacterResource.heroicResourceId):GetHistory(),
            }
        end,

        -- Row 1: title
        gui.Label{
            classes = {"tokenbox", "title", "heroic-resources"},
            text = "",
            refreshToken = function(element, token)
                element.text = token.properties:GetHeroicResourceName():upper()
            end,
        },

        -- Row 2: icon & value
        gui.Panel{
            classes = {"container"},
            halign = "center",
            flow = "horizontal",
            gui.Panel{
                classes = {"icon", "heroic-resources"},
                refreshToken = function(element, token)
                    local classInfo = token.properties:IsHero() and token.properties:GetClass() or nil
                    local icon = classInfo ~= nil and classInfo:try_get("heroicResourceIcon", PLACEHOLDER_TOKEN)
                    element.selfStyle.bgimage = icon
                end,
            },
            gui.Input{
                classes = {"tokenbox", "value", "heroic-resources"},
                text = "--",
                characterLimit = 2,
                selectAllOnFocus = true,
                placeholderText = "--",
                numeric = true,
                data = { token = nil },
                refreshCharacter = function(element, token)
                    element.data.token = token
                    local q = dmhub.initiativeQueue
                    if q == nil or q.hidden then
                        element.editable = false
                        element.textNoNotify = "--"
                    else
                        element.editable = true
                        element.textNoNotify = tostring(token.properties:GetHeroicOrMaliceResources())
                    end
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                change = function(element)
                    local token = element.data.token
                    if token == nil then return end
                    local n = tonum(element.text, nil)
                    if n == nil then
                        element:FireEvent("refreshCharacter", token)
                        return
                    end
                    local creature = token.properties
                    if not creature:IsHero() and not creature:IsCompanion() then
                        CharacterResource.SetMalice(math.max(0, n), "Manually set")
                        return
                    end
                    local resource = dmhub.GetTable(CharacterResource.tableName)[CharacterResource.heroicResourceId]
                    n = resource:ClampQuantity(token.properties, n)
                    local diff = n - token.properties:GetHeroicOrMaliceResources()
                    if diff ~= 0 then
                        token:ModifyProperties{
                            description = "Change Heroic Resource",
                            execute = function()
                                if diff > 0 then
                                    token.properties:RefreshResource(CharacterResource.heroicResourceId, "unbounded", diff)
                                else
                                    token.properties:ConsumeResource(CharacterResource.heroicResourceId, "unbounded", -diff)
                                end
                            end,
                        }
                    end
                    element.textNoNotify = tostring(token.properties:GetHeroicOrMaliceResources())
                end,
            },
        },
    }
end

--- Display the summary section with portrait, class, levels, etc.
--- @return Panel
function TacPanel.Summary()

    return gui.Panel{
        classes = {"tacpanel"},
        -- Main arrangement - 3 columns
        gui.Panel{
            classes = {"container"},
            flow = "horizontal",

            -- Col1: Portrait
            TacPanel.Portrait(),

            -- Col2: Name etc.
            gui.Panel{
                classes = {"summary-info"},
                width = TacPanelSizes.Panels.summaryNames,
                refreshCharacter = function(element, token)
                    if token.properties:IsMonster() then
                        element.selfStyle.width = TacPanelSizes.Panels.summaryNames + 100
                    else
                        element.selfStyle.width = TacPanelSizes.Panels.summaryNames
                    end
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,

                -- Name
                gui.Label{
                    classes = {"summary-info", "char-name"},
                    refreshCharacter = function(element, token)
                        local name = token:GetNameMaxLength(64)
                        if name == nil or name == "" then
                            if token.properties:IsMonster() then
                                name = rawget(token.properties, "monster_type") or "Unknown Monster"
                            else
                                name = token.properties:RaceOrMonsterType()
                            end
                        end
                        element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.charName, 11, #name)
                        element.text = name
                    end,
                },

                -- Monster Keywords
                gui.Label{
                    classes = {"summary-info", "monster-keywords"},
                    refreshCharacter = function(element, token)
                        local text = ""
                        if token.properties:IsMonster() then
                            local keywords = token.properties.keywords or {}
                            local sorted = {}
                            for k, _ in pairs(keywords) do
                                sorted[#sorted+1] = ActivatedAbility.CanonicalKeyword(k)
                            end
                            table.sort(sorted)
                            text = string.join(sorted, ", ")
                        end
                        element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.charClass, 9, #text)
                        element.text = text
                    end,
                },

                -- Level
                gui.Label{
                    classes = {"summary-info", "level"},
                    refreshCharacter = function(element, token)
                        local level = token.properties:CharacterLevel()
                        local text = element.text
                        if token.properties:IsMonster() then
                            local role = token.properties:try_get("role", "")
                            local ev = token.properties:try_get("ev", 1)
                            if role ~= "" then
                                text = string.format("LEVEL %d %s  EV %d", level, string.upper(role), ev)
                            else
                                text = string.format("LEVEL %d  EV %d", level, ev)
                            end
                        elseif level == 1 then
                            local extra = token.properties:ExtraLevelInfo()
                            local encounter = type(extra) == "table" and extra.encounter or nil
                            local mapping = {"FIRST ENCOUNTER", "SECOND ENCOUNTER", "THIRD ENCOUNTER", "FOURTH ENCOUNTER"}
                            text = mapping[encounter] or "LEVEL 1"
                        else
                            text = string.format("LEVEL %d", level)
                        end
                        element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.charLevel, 12, #text)
                        element.text = text
                    end,
                    setToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                },

                -- Class
                gui.Label{
                    classes = {"summary-info", "class"},
                    refreshCharacter = function(element, token)
                        local text = ""
                        if token.properties:IsHero() then
                            local classItem = token.properties:GetClass()
                            if classItem ~= nil then
                                text = string.upper(classItem.name)
                            end
                        else
                            local mt = token.properties:try_get("monster_type", "Monster")
                            text = string.upper(mt)
                        end
                        element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.charClass, 9, #text)
                        element.text = text
                    end,
                    setToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                },

                -- Subclass
                gui.Label{
                    classes = {"summary-info", "subclass"},
                    refreshCharacter = function(element, token)
                        local text = ""
                        if token.properties:IsHero() then
                            local classItem = token.properties:GetClass()
                            if classItem ~= nil then
                                local subclass = token.properties:GetSubClass(classItem)
                                if subclass ~= nil then
                                    text = string.upper(subclass.name)
                                end
                            end
                        end
                        element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.charSubclass, 18, #text)
                        element.text = text
                    end,
                    setToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                },

            },

            -- Col3: Token boxes
            gui.Panel{
                classes = {"container"},
                flow = "vertical",
                refreshCharacter = function(element, token)
                    element:SetClass("collapsed", token.properties:IsMonster())
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,

                TacPanel.HeroTokenBox(),
                TacPanel.SurgesBox(),
            }
        },

        -- Full-width "Add to Combat" button below the avatar area. Visible only
        -- when there is an active initiative queue and this token is not yet a
        -- combatant (same semantics as the old initiative icon button).
        gui.Button{
            classes = {"sizeM", "collapsed"},
            width = "100%-12",
            height = 40,
            vmargin = 4,
            lmargin = 4,
            halign = "left",
            text = "Add to Combat",
            data = { token = nil },
            refreshCharacter = function(element, token)
                element.data.token = token
                local q = dmhub.initiativeQueue
                if q == nil or q.hidden then
                    element:SetClass("collapsed", true)
                    return
                end
                element:SetClass("collapsed",
                    token.properties:try_get("_tmp_initiativeStatus") ~= "NonCombatant")
            end,
            setToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
            press = function(element)
                Commands.rollinitiative()
            end,
        },

    }
end

--- Display the damage / harm box
--- @return Panel
function TacPanel.HarmBox()
    return gui.Panel{
        classes = {"stamina-box", "harm"},
        gui.Label{
            classes = {"stambox-title", "harm"},
            text = "DMG",
        },
        gui.Input{
            classes = {"stambox-input", "harm"},
            text = "",
            characterLimit = 8,
            placeholderText = "-",
            data = {
                token = nil,
            },
            change = function(element)
                local n = tonum(element.text, 0)
                if n > 0 and element.data.token ~= nil and element.data.token.properties ~= nil then
                    element.data.token:ModifyProperties{
                        description = "Apply Damage",
                        execute = function()
                            element.data.token.properties:TakeDamage(element.text)
                            element.text = ""
                        end,
                    }
                end
            end,
            refreshCharacter = function(element, token)
                element.data.token = token
            end,
            setToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
        },
    }
end

--- Display the heal box
--- @return Panel
function TacPanel.HealBox()
    return gui.Panel{
        classes = {"stamina-box", "heal"},
        gui.Label{
            classes = {"stambox-title", "heal"},
            text = "HEAL",
        },
        gui.Input{
            classes = {"stambox-input", "heal"},
            text = "",
            characterLimit = 8,
            placeholderText = "+",
            data = {
                token = nil,
            },
            change = function(element)
                local n = tonum(element.text, 0)
                if n > 0 and element.data.token ~= nil and element.data.token.properties ~= nil then
                    element.data.token:ModifyProperties{
                        description = "Apply Healing",
                        execute = function()
                            element.data.token.properties:Heal(n)
                            element.text = ""
                        end,
                    }
                end
            end,
            refreshCharacter = function(element, token)
                element.data.token = token
            end,
            setToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
        },
    }
end

--- Display the temp stamina box
--- @return Panel
function TacPanel.TempStamBox()
    return gui.Panel{
        classes = {"stamina-box", "temp"},
        gui.Label{
            classes = {"stambox-title", "temp"},
            text = "TEMP",
        },
        gui.Input{
            classes = {"stambox-input", "temp"},
            text = "",
            hoverCursor = "text",
            characterLimit = 8,
            placeholderText = TEMP_PLACEHOLDER,
            selectAllOnFocus = true,
            bgimage = true,
            data = {
                token = nil,
            },
            change = function(element)
                local before = tonum(element.data.token.properties:TemporaryHitpointsStr(), 0)
                local after = tonum(element.text, 0)
                if element.text ~= "" and after ~= before and element.data.token ~= nil and element.data.token.properties ~= nil then
                    element.data.token:ModifyProperties{
                        description = "Apply Temp Stamina",
                        execute = function()
                            element.data.token.properties:SetTemporaryHitpoints(element.text)
                            element.data.token.properties:DispatchEvent("gaintempstamina", {})
                        end,
                    }
                end
            end,
            refreshCharacter = function(element, token)
                element.data.token = token
                local tempHp = token.properties:TemporaryHitpoints()
                if tempHp <= 0 then
                    element.text = "0"
                else
                    element.text = string.format("%d", tempHp)
                end

            end,
            setToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
        },
    }
end

--- Display the current stamina box
--- @return Panel
function TacPanel.StaminaBox()
    return gui.Panel{
        classes = {"stamina-box", "stamina"},
        halign = "center",
        valign = "center",
        data = { token = nil },

        refreshCharacter = function(element, token)
            element.data.token = token
            element:FireEventTree("refreshValue", token)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        gui.Panel{
            classes = {"container"},
            flow = "horizontal",
            valign = "center",
            halign = "center",
            gui.Input{
                classes = {"stambox-stam", "current"},
                hoverCursor = "text",
                text = "0",
                characterLimit = 4,
                selectAllOnFocus = true,
                placeholderText = "--",
                numeric = true,
                data = {
                    token = nil,
                },
                linger = function(element)
                    local token = element.data.token
                    if token ~= nil and token.properties ~= nil then
                        element.tooltip = gui.StatsHistoryTooltip{
                            description = "stamina",
                            entries = token.properties:GetStatHistory("stamina"):GetHistory()
                        }
                    end
                end,
                change = function(element)
                    local token = element.data.token
                    if token ~= nil and token.valid and token.properties ~= nil then
                        local n = tonumber(element.text)
                        if n ~= nil and (n >= 0 or token.properties:IsHero()) then
                            token:ModifyProperties{
                                description = "Set Stamina",
                                execute = function()
                                    token.properties:SetCurrentHitpoints(n)
                                end,
                            }
                        end
                    end
                end,
                refreshValue = function(element, token)
                    element.data.token = token
                    local text = tostring(token.properties:CurrentHitpoints())
                    element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.currentStamina, 3, #text)
                    element.textNoNotify = text
                end,
            },
            gui.Label{
                classes = {"stambox-stam", "max"},
                text = "/ 0",
                data = { token = nil },
                refreshValue = function(element, token)
                    element.data.token = token
                    element.text = string.format("/ %d", token.properties:MaxHitpoints())
                end,
                linger = function(element)
                    local token = element.data.token
                    if token ~= nil and token.properties ~= nil then
                        local baseValue = token.properties:BaseHitpoints()
                        local modifications = token.properties:DescribeModifications("hitpoints", baseValue)
                        local text = string.format("Base Stamina: %d", baseValue)
                        for _, modification in ipairs(modifications) do
                            text = text .. string.format("\n%s: %s", modification.key, modification.value)
                        end
                        element.tooltip = TacPanel.Tooltip(text)
                    end
                end,
            },
        },
    }
end

--- Display-only recovery pips, split into rows of 10
--- @param recoveryid string
--- @param recoveryInfo table
--- @return Panel
function TacPanel.RecoveryPips(recoveryid, recoveryInfo)
    return gui.Panel{
        classes = {"container"},
        halign = "center",
        valign = "top",
        flow = "vertical",
        bgcolor = "clear",

        gui.Panel{
            classes = {"recovery-pip-row"},
            bgcolor = "clear",
            updatePips = function(element, info)
                local rowCount = math.min(info.maxRec, 10)
                for i = #element.children + 1, rowCount do
                    element:AddChild(gui.Panel{
                        classes = {"recovery-pip"},
                    })
                end
                for i, child in ipairs(element.children) do
                    child:SetClass("collapsed", i > rowCount)
                    child:SetClass("filled", i <= info.current)
                end
            end,
        },
        gui.Panel{
            classes = {"recovery-pip-row"},
            bgcolor = "clear",
            updatePips = function(element, info)
                local rowCount = math.max(0, info.maxRec - 10)
                for i = #element.children + 1, rowCount do
                    element:AddChild(gui.Panel{
                        classes = {"recovery-pip"},
                    })
                end
                for i, child in ipairs(element.children) do
                    child:SetClass("collapsed", i > rowCount)
                    child:SetClass("filled", (i + 10) <= info.current)
                end
                element:SetClass("collapsed", rowCount <= 0)
            end,
        },

        refreshCharacter = function(element, token)
            local maxRec = token.properties:GetResources()[recoveryid] or 0
            local usage = token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
            local current = max(0, maxRec - usage)
            element:FireEventTree("updatePips", {maxRec = maxRec, current = current})
        end,
    }
end

--- Draw the recoveries box
--- @return Panel
function TacPanel.RecoveriesBox()
    local recoveryid = nil
    local recoveryInfo = nil
    local resourcesTable = dmhub.GetTableVisible(CharacterResource.tableName)
    for k,v in pairs(resourcesTable) do
        if v.name == "Recovery" then
            recoveryid = k
            recoveryInfo = v
            break
        end
    end

    -- Build and show the "spend an ally's shared recovery" context menu on the
    -- given element. Returns true if a menu was shown (i.e. there is at least
    -- one bonded ally with a spendable recovery), false otherwise.
    local function ShowSharingMenu(element, token)
        if token == nil or not token.valid or token.properties == nil then return false end

        local recoverySharing = token.properties:ShareRecoveriesWith()
        if recoverySharing == nil then return false end

        local entries = {}
        for _, otherToken in ipairs(recoverySharing) do
            if otherToken.charid ~= token.charid then
                local sharedUsage = otherToken.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
                local sharedMax = otherToken.properties:GetResources()[recoveryid] or 0
                local sharedQuantity = sharedMax - sharedUsage
                if sharedQuantity > 0 then
                    local casterToken = token
                    local sourceToken = otherToken
                    entries[#entries+1] = {
                        text = string.format("Spend %s's Recovery (%d/%d)", sourceToken.name, sharedQuantity, sharedMax),
                        click = function()
                            element.popup = nil
                            if casterToken.properties:CurrentHitpoints() >= casterToken.properties:MaxHitpoints() then
                                return
                            end

                            local groupid = dmhub.GenerateGuid()
                            casterToken:ModifyProperties{
                                description = string.format("Use %s's Recovery", sourceToken.name),
                                groupid = groupid,
                                execute = function()
                                    casterToken.properties:Heal(casterToken.properties:RecoveryAmount(), "Use Recovery")
                                end,
                            }

                            sourceToken:ModifyProperties{
                                description = string.format("%s's Recovery used by %s", sourceToken.name, casterToken.name),
                                groupid = groupid,
                                execute = function()
                                    sourceToken.properties:ConsumeResource(recoveryid, recoveryInfo.usageLimit, 1, "Used Recovery")
                                end,
                            }
                        end,
                    }
                end
            end
        end

        if #entries == 0 then return false end

        element.popup = gui.ContextMenu{
            entries = entries,
        }
        return true
    end

    return gui.Panel{
        classes = {"stamina-box", "recoveries"},
        hoverCursor = "pressbutton",
        data = { token = nil },
        refreshCharacter = function(element, token)
            element.data.token = token
            local showRecovery = recoveryid ~= nil and (token.properties:IsHero() or token.properties:IsRetainer() or token.properties:IsCompanion())
            element:SetClass("collapsed", not showRecovery)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        linger = function(element)
            local token = element.data.token
            if token == nil or not token.valid or token.properties == nil then return end
            local usage = token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
            local maxRec = token.properties:GetResources()[recoveryid] or 0
            local quantity = maxRec - usage
            local usageNote = "Use a recovery"
            if token.properties:CurrentHitpoints() >= token.properties:MaxHitpoints() then
                usageNote = "Already at maximum stamina"
            elseif quantity <= 0 then
                if token.properties:IsHero() and token.properties:GetHeroTokens() >= 2 then
                    usageNote = "Click to spend 2 hero tokens as a Recovery"
                else
                    usageNote = "No Recoveries left"
                end
            end

            local lines = {usageNote}

            local baseRecoveryValue = math.floor(token.properties:MaxHitpoints() / 3)
            local recoveryValueMods = token.properties:DescribeModifications("recoveryvalue", baseRecoveryValue)
            if #recoveryValueMods > 0 then
                lines[#lines+1] = ""
                lines[#lines+1] = string.format("Base Recovery Value: %d", baseRecoveryValue)
                for _, modification in ipairs(recoveryValueMods) do
                    lines[#lines+1] = string.format("%s: %s", modification.key, tostring(modification.value))
                end
            end

            local recoveryMods = token.properties:DescribeResourceModifications(recoveryid)
            if #recoveryMods > 1 then
                lines[#lines+1] = ""
                lines[#lines+1] = string.format("Maximum Recoveries: %d", maxRec)
                for _, modification in ipairs(recoveryMods) do
                    local valStr
                    if type(modification.value) == "number" then
                        valStr = string.format("%+d", modification.value)
                    else
                        valStr = tostring(modification.value)
                    end
                    lines[#lines+1] = string.format("%s: %s", modification.key, valStr)
                end
            end

            local recoverySharing = token.properties:ShareRecoveriesWith()
            if recoverySharing ~= nil then
                lines[#lines+1] = ""
                lines[#lines+1] = "Can Share Recoveries With:"
                for _, otherToken in ipairs(recoverySharing) do
                    if otherToken.charid ~= token.charid then
                        local sharedUsage = otherToken.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
                        local sharedMax = otherToken.properties:GetResources()[recoveryid] or 0
                        lines[#lines+1] = string.format("%s (%d/%d)", otherToken.name, sharedMax - sharedUsage, sharedMax)
                    end
                end
            end

            element.tooltip = TacPanel.Tooltip(table.concat(lines, "\n"))
        end,
        press = function(element)
            local token = element.data.token
            if token == nil then return end

            local useHeroTokens = false
            local quantity = max(0, (token.properties:GetResources()[recoveryid] or 0) - (token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
            if quantity <= 0 then
                if (not token.properties:IsHero()) or token.properties:GetHeroTokens() < 2 then
                    -- Out of our own recoveries (and no hero tokens to spend): offer
                    -- any bonded ally's shared recoveries instead of silently failing.
                    ShowSharingMenu(element, token)
                    return
                end
                useHeroTokens = true
            end

            if token.properties:CurrentHitpoints() >= token.properties:MaxHitpoints() then
                return
            end

            token:ModifyProperties{
                description = "Use Recovery",
                execute = function()
                    token.properties:Heal(token.properties:RecoveryAmount(), "Use Recovery")
                    if useHeroTokens then
                        token.properties:SetHeroTokens(token.properties:GetHeroTokens() - 2, "Used to Recover")
                    else
                        token.properties:ConsumeResource(recoveryid, recoveryInfo.usageLimit, 1, "Used Recovery")
                    end
                end,
            }
            if useHeroTokens then
                local classInfo = token.properties:IsHero() and token.properties:GetClass() or nil
                track("hero_token_change", {
                    change = -2,
                    source = "recovery",
                    class = classInfo and classInfo.name or "unknown",
                    dailyLimit = 30,
                })
            end

            local remaining = max(0, (token.properties:GetResources()[recoveryid] or 0) - (token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
            if useHeroTokens then
                remaining = remaining
            else
                remaining = remaining - 1
            end
            local classInfo = token.properties:IsHero() and token.properties:GetClass() or nil
            local q = dmhub.initiativeQueue
            track("recovery_spend", {
                class = classInfo and classInfo.name or "unknown",
                level = token.properties:CharacterLevel(),
                remaining = max(0, remaining),
                context = (q ~= nil and not q.hidden and q:try_get("gameMode") == "combat") and "combat" or "rest",
                dailyLimit = 20,
            })
        end,
        rightClick = function(element)
            ShowSharingMenu(element, element.data.token)
        end,
        gui.Label{
            classes = {"stambox-title", "heal"},
            text = "RECOVERIES",
        },
        gui.Panel{
            classes = {"container", "borderSuccess"},
            height = "100% available",
            width = "100%+8",
            valign = "top",
            halign = "left",
            hmargin = -4,
            bgimage = true,
            bgcolor = "clear",
            border = {x1 = 0, y1 = 0, x2 = 0, y2 = 1},
            flow = "horizontal",
            gui.Panel{
                classes = {"container", "borderSuccess"},
                height = "100%+2",
                width = "40%",
                valign = "top",
                halign = "left",
                bgimage = true,
                bgcolor = "clear",
                border = {x1 = 0, y1 = 0, x2 = 1, y2 = 0},
                gui.Label{
                    classes = {"recovery-value"},
                    text = "+0",
                    refreshCharacter = function(element, token)
                        element.text = string.format("%+d", token.properties:RecoveryAmount())
                    end,
                },
            },
            gui.Panel{
                classes = {"container"},
                height = "100%",
                width = "60%",
                valign = "top",
                halign ="left",
                flow = "vertical",
                bgcolor = "clear",
                gui.Panel{
                    classes = {"container"},
                    width = "auto",
                    valign = "top",
                    halign = "center",
                    flow = "horizontal",
                    gui.Input{
                        classes = {"recovery-count"},
                        hoverCursor = "text",
                        numeric = true,
                        text = "0",
                        characterLimit = 2,
                        selectAllOnFocus = true,
                        placeholderText = "--",
                        data = { token = nil },
                        refreshCharacter = function(element, token)
                            element.data.token = token
                            local quantity = max(0, (token.properties:GetResources()[recoveryid] or 0) - (token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
                            element.textNoNotify = string.format("%d", quantity)
                        end,
                        setToken = function(element, token)
                            element.data.token = token
                        end,
                        change = function(element)
                            local token = element.data.token
                            if token == nil then return end
                            local n = tonum(element.text, -1)
                            if n < 0 then
                                element.textNoNotify = "0"
                                element:FireEvent("refreshCharacter", token)
                                return
                            end
                            local nresources = token.properties:GetResources()[recoveryid] or 0
                            n = math.min(n, nresources)
                            local usage = token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
                            local current = nresources - usage
                            local delta = n - current
                            element.textNoNotify = string.format("%d", n)
                            if delta == 0 then return end
                            token:ModifyProperties{
                                description = "Set Recoveries",
                                execute = function()
                                    if delta > 0 then
                                        token.properties:RefreshResource(recoveryid, recoveryInfo.usageLimit, delta, "Set Recoveries")
                                    else
                                        token.properties:ConsumeResource(recoveryid, recoveryInfo.usageLimit, -delta, "Set Recoveries")
                                    end
                                end,
                            }
                        end,
                    },
                    gui.Label{
                        classes = {"recovery-max"},
                        text = "/ 0",
                        refreshCharacter = function(element, token)
                            local maxRec = token.properties:GetResources()[recoveryid] or 0
                            element.text = string.format("/ %d", maxRec)
                        end,
                    }
                },
                TacPanel.RecoveryPips(recoveryid, recoveryInfo),
            }
        },
    }
end

--- Display the health bar
--- @return Panel
function TacPanel.HealthBar()
    local m_tokenid = nil

    local m_animValue
    local m_animTarget
    local m_animTempTarget
    local m_animTempValue
    local m_seekSpeed = 1
    local m_lastThink = 0

    local m_dead = false
    local m_dying = false
    local m_currentHP = nil
    local m_maxHP = nil
    local m_tempHP = nil
    local m_bloodied = nil
    local m_isHero = nil
    local m_windedVal = nil

    local resultPanel

    local fill = gui.Panel{
        width = "100%-2",
        height = "100%-2",
        valign = "center",
        halign = "left",
        lmargin = 1,
        bgimage = true,
        classes = {"fillBarFill", "healthFill"},
    }

    local tempFill = gui.Panel{
        width = "0%",
        height = "100%-2",
        valign = "center",
        halign = "left",
        bgimage = true,
        classes = {"fillBarFill"},
    }

    local icon = gui.Panel{
        classes = {"bgInverse"},
        width = 12,
        height = 12,
        valign = "center",
        halign = "left",
        hmargin = 4,
        lmargin = 50,
    }
    local label = gui.Label{
        classes = {"fg", "sizeS", "number", "bold"},
        halign = "center",
        valign = "center",
        width = "auto",
        height = "auto",
        minWidth = 80,
    }

    local labelPanel = gui.Panel{
        width = "auto",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "horizontal",
        floating = true,
        icon,
        label,
    }

    resultPanel = gui.Panel{
        classes = {"bordered"},
        width = "100%-8",
        flow = "horizontal",
        halign = "center",
        height = 20,
        cornerRadius = 0,
        bgcolor = "clear",
        fill,
        tempFill,
        labelPanel,

        thinkTime = 1,

        hover = function(element)
            local text
            if m_dead then
                if m_isHero then
                    text = "This hero is dead."
                else
                    text = "This creature is dead."
                end
            elseif m_dying then
                text = string.format("This hero is dying. If they reach -%d Stamina, they will die.", m_windedVal)
            elseif m_bloodied then
                if m_isHero then
                    text = "This hero is winded."
                else
                    text = "This creature is winded."
                end
            end

            if text ~= nil then
                gui.Tooltip(text)(element)
            end
        end,
        refreshCharacter = function(element, token)
            if token == nil or not token.valid or token.properties == nil then
                return
            end

            local newToken = token.charid ~= m_tokenid
            m_tokenid = token.charid

            local props = token.properties

            m_currentHP = props:CurrentHitpoints()
            m_maxHP = props:MaxHitpoints()
            m_tempHP = props:TemporaryHitpoints() or 0
            m_bloodied = m_currentHP <= props:BloodiedThreshold()
            m_isHero = props:IsHero()
            m_windedVal = math.floor(m_maxHP / 2)
            m_dying = props:IsDying()
            m_dead = props:IsDead()

            fill:SetClass("winded", m_bloodied)
            fill:SetClass("dying", m_dying)

            -- Border tracks the same healthy/winded/dying state as the fill.
            element:SetClass("borderSuccess", not m_bloodied and not m_dying)
            element:SetClass("borderWarning", m_bloodied and not m_dying)
            element:SetClass("borderDanger", m_dying)

            if m_dead then
                label.text = "DEAD"
                icon.bgimage = "ui-icons/Pin_Boss.png"
            elseif m_dying then
                label.text = string.format("<b>%d/%d</b>", m_currentHP, m_maxHP)
                icon.bgimage = "drawsteel/Icon_STA_Dying.png"
            elseif m_bloodied then
                label.text = string.format("<b>%d/%d</b>", m_currentHP, m_maxHP)
                icon.bgimage = "drawsteel/Icon_STA_Winded.png"
            else
                label.text = string.format("<b>%d/%d</b>", m_currentHP, m_maxHP)
                icon.bgimage = "drawsteel/Icon_STA_Healthy.png"
            end

            m_animTempTarget = m_tempHP

            m_seekSpeed = m_maxHP --seek speed per second.
            m_animTarget = m_currentHP
            if m_isHero then
                m_animTarget = math.max(m_animTarget, -m_windedVal)
            else
                m_animTarget = math.max(m_animTarget, 0)
            end

            if newToken then
                m_animValue = m_animTarget
                m_animTempValue = m_animTempTarget
                element.thinkTime = 1
            else
                m_lastThink = dmhub.Time()
                element.thinkTime = 0.01
            end
        end,

        think = function(element)
            if m_animValue == nil or m_animTarget == nil then return end

            local t = dmhub.Time()
            local delta = math.max(0.01, t - m_lastThink)
            m_lastThink = t

            local synced = true
            local seekDelta = m_seekSpeed * delta
            if math.abs(m_animTarget - m_animValue) <= seekDelta then
                m_animValue = m_animTarget
            else
                m_animValue = m_animValue + (m_animTarget > m_animValue and seekDelta or -seekDelta)
                synced = false
            end

            if math.abs(m_animTempTarget - m_animTempValue) <= seekDelta then
                m_animTempValue = m_animTempTarget
            else
                m_animTempValue = m_animTempValue + (m_animTempTarget > m_animTempValue and seekDelta or -seekDelta)
                synced = false
            end

            if synced then
                element.thinkTime = 1
            else
                element.thinkTime = 0.01
            end

            local totalAmount
            local r = 0
            if m_isHero and m_animValue < 0 then
                totalAmount = m_windedVal + m_animTempValue
                r = 1 - (-m_animValue / totalAmount)
            else
                totalAmount = m_maxHP + m_animTempValue
                r = m_animValue / totalAmount
            end

            print("SEEK:: DELTA =", seekDelta, "diff =", math.abs(m_animTarget - m_animValue), "animValue =", m_animValue, "r =", r)
            fill.selfStyle.width = string.format("%f%%-2", r * 100)

            r = m_animTempValue / totalAmount
            tempFill.selfStyle.width = string.format("%f%%", r * 100)
        end,
    }

    return resultPanel
end

--- Clean up resistance/immunity text for compact display.
--- Strips " Damage ", " weakness N.", " immunity N.", "Immune to ", trailing ".".
--- e.g. "Fire Damage weakness 5." -> "Fire 5"
---      "Damage immunity 3." -> "All 3"
---      "Immune to Frightened, Slowed." -> "Frightened, Slowed"
--- @param text string
--- @return string
function TacPanel.CleanResistanceText(text)
    local txt = text
    -- Strip "Immune to " prefix
    txt = string.gsub(txt, "^Immune to ", "")
    -- Strip trailing period
    txt = string.gsub(txt, "%.$", "")
    -- Strip " weakness N" or " immunity N" suffix
    txt = string.gsub(txt, " weakness %d+$", "")
    txt = string.gsub(txt, " immunity %d+$", "")
    -- Strip " Damage" (keep damage type prefix)
    txt = string.gsub(txt, " Damage", "")
    -- If text is now empty (was "Damage immunity 3"), show "All"
    if txt == "" then
        txt = "All"
    end
    return txt
end

--- Display weaknesses and immunities below the health bar
--- @return Panel
function TacPanel.Resistances()
    return gui.Panel{
        classes = {"res-container", "collapsed"},

        refreshCharacter = function(element, token)
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end

            local creature = token.properties
            local entries = creature:ResistanceEntries()

            -- Separate into weaknesses (dr < 0) and immunities (dr > 0)
            local weaknesses = {}
            local immunities = {}
            for _, e in ipairs(entries) do
                if (e.entry:try_get("dr", 0)) < 0 then
                    weaknesses[#weaknesses+1] = e
                else
                    immunities[#immunities+1] = e
                end
            end

            -- Sort each list alphabetically by text
            table.sort(weaknesses, function(a, b) return a.text < b.text end)
            table.sort(immunities, function(a, b) return a.text < b.text end)

            -- Condition immunities
            local condImmDesc = creature:ConditionImmunityDescription()

            -- Build comma-separated weakness string
            local weakParts = {}
            for _, e in ipairs(weaknesses) do
                local dr = math.abs(e.entry:try_get("dr", 0))
                weakParts[#weakParts+1] = TacPanel.CleanResistanceText(e.text) .. " " .. dr
            end
            local weakText = table.concat(weakParts, ", ")

            -- Build comma-separated immunity string
            local immuneParts = {}
            for _, e in ipairs(immunities) do
                local dr = math.abs(e.entry:try_get("dr", 0))
                immuneParts[#immuneParts+1] = TacPanel.CleanResistanceText(e.text) .. " " .. dr
            end
            if condImmDesc ~= "" then
                immuneParts[#immuneParts+1] = TacPanel.CleanResistanceText(condImmDesc)
            end
            local immuneText = table.concat(immuneParts, ", ")

            -- Collapse entire section if nothing to show
            local hasWeak = #weakParts > 0
            local hasImmune = #immuneParts > 0
            local hasContent = hasWeak or hasImmune
            element:SetClass("collapsed", not hasContent)

            if hasContent then
                local boxWidth = (hasWeak and hasImmune) and "47%" or "94%"
                local children = {}
                if hasWeak then
                    local weakTitle = #weakParts > 1 and "WEAKNESSES" or "WEAKNESS"
                    children[#children+1] = gui.Label{
                        classes = {"res-box", "weakness"},
                        width = boxWidth,
                        textWrap = true,
                        markdown = true,
                        text = ThemeEngine.ResolveTokens(string.format("**<color=@fgMuted>%s:</color>** %s", weakTitle, weakText)),
                    }
                end
                if hasImmune then
                    local immuneTitle = #immuneParts > 1 and "IMMUNITIES" or "IMMUNITY"
                    children[#children+1] = gui.Label{
                        classes = {"res-box", "immunity"},
                        width = boxWidth,
                        textWrap = true,
                        markdown = true,
                        text = ThemeEngine.ResolveTokens(string.format("**<color=@fgMuted>%s:</color>** %s", immuneTitle, immuneText)),
                    }
                end
                element.children = children
            end
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
    }
end

--- Display the stamina controls
--- @return Panel
function TacPanel.Stamina()
    return TacPanel.CollapsiblePanel{
        title = "STAMINA",
        altBg = false,
        gui.Panel{
            classes = {"stamina-controls"},
            TacPanel.HarmBox(),
            TacPanel.StaminaBox(),
            TacPanel.HealBox(),
            TacPanel.RecoveriesBox(),
            TacPanel.TempStamBox(),
        },
        TacPanel.HealthBar(),
        TacPanel.Resistances(),
    }
end

--- Display the Speed box
--- @return Panel
function TacPanel.SpeedBox()
    local tokenInfo = { token = nil }

    return gui.Panel{
        classes = {"movement-box"},
        data = { token = nil },
        linger = GenerateAttributeCalculationTooltip(tokenInfo, "Speed", creature.GetBaseSpeed, creature.DescribeSpeedModifications),
        press = function(element)
            local token = element.data.token
            if token ~= nil then
                gui.PopupOverrideAttribute{
                    parentElement = element,
                    token = token,
                    attributeName = "Speed",
                    baseValue = token.properties:GetBaseSpeed(),
                    modifications = token.properties:DescribeSpeedModifications(),
                }
            end
        end,
        refreshCharacter = function(element, token)
            element.data.token = token
            tokenInfo.token = token
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        gui.Label{
            classes = {"movebox-title"},
            text = "Speed",
        },
        gui.Panel{
            classes = {"container"},
            width = "auto",
            valign = "top",
            halign = "center",
            flow = "horizontal",
            gui.Label{
                classes = {"movebox-value"},
                text = "0",
                refreshCharacter = function(element, token)
                    if token == nil or not token.valid or token.properties == nil then return end
                    local baseMove = token.properties:GetBaseSpeed()
                    local curMove = token.properties:CurrentMovementSpeed()
                    element.text = tostring(curMove >= baseMove and curMove or baseMove)
                    element:SetClass("restricted", curMove < baseMove)
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
            },
            gui.Label{
                classes = {"movebox-value", "hindered", "collapsed"},
                text = "0",
                refreshCharacter = function(element, token)
                    if token == nil or not token.valid or token.properties == nil then return end
                    local baseMove = token.properties:GetBaseSpeed()
                    local curMove = token.properties:CurrentMovementSpeed()
                    element.text = tostring(curMove)
                    element:SetClass("collapsed", curMove >= baseMove)
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
            },
        },
    }
end

--- Display the Disengage box
--- @return Panel
function TacPanel.DisengageBox()
    local tokenInfo = { token = nil }

    return gui.Panel{
        classes = {"movement-box"},
        data = { token = nil },
        linger = GenerateCustomAttributeCalculationTooltip(tokenInfo, "Disengage Speed"),
        press = function(element)
            local token = element.data.token
            if token ~= nil then
                gui.PopupOverrideAttribute{
                    parentElement = element,
                    token = token,
                    attributeName = "Disengage Speed",
                }
            end
        end,
        refreshCharacter = function(element, token)
            element.data.token = token
            tokenInfo.token = token
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        gui.Label{
            classes = {"movebox-title"},
            text = "Disengage",
        },
        gui.Label{
            classes = {"movebox-value"},
            text = "0",
            refreshCharacter = function(element, token)
                if token == nil or not token.valid or token.properties == nil then return end
                local customAttr = CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"]
                if customAttr ~= nil then
                    element.text = tostring(token.properties:GetCustomAttribute(customAttr))
                else
                    element.text = "0"
                end
            end,
            refreshToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
            setToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
        },
    }
end

--- Display the Stability box
--- @return Panel
function TacPanel.StabilityBox()
    local tokenInfo = { token = nil }

    return gui.Panel{
        classes = {"movement-box"},
        data = { token = nil },
        linger = GenerateAttributeCalculationTooltip(tokenInfo, "Stability",
            creature.BaseForcedMoveResistance,
            function(c)
                return c:DescribeModifications("forcedmoveresistance", c:BaseForcedMoveResistance())
            end),
        press = function(element)
            local token = element.data.token
            if token ~= nil then
                local baseStability = token.properties:BaseForcedMoveResistance()
                gui.PopupOverrideAttribute{
                    parentElement = element,
                    token = token,
                    attributeName = "Stability",
                    baseValue = baseStability,
                    modifications = token.properties:DescribeModifications("forcedmoveresistance", baseStability),
                }
            end
        end,
        refreshCharacter = function(element, token)
            element.data.token = token
            tokenInfo.token = token
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        gui.Label{
            classes = {"movebox-title"},
            text = "Stability",
        },
        gui.Label{
            classes = {"movebox-value"},
            text = "0",
            refreshCharacter = function(element, token)
                if token == nil or not token.valid or token.properties == nil then return end
                element.text = tostring(token.properties:Stability())
            end,
            refreshToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
            setToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
        },
    }
end

--- Display the altitude box
--- @return Panel
function TacPanel.AltitudeBox()
    return gui.Panel{
        classes = {"movement-box", "collapsed"},
        data = { token = nil },
        refreshCharacter = function(element, token)
            element.data.token = token
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end
            local canFly = token.properties:CanFly()
            local canClimb = token.canCurrentlyClimb
            local canBurrow = token.properties:CanBurrow()
            local visible = canFly or canClimb or canBurrow
            element:SetClass("collapsed", not visible)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        gui.Label{
            classes = {"movebox-title"},
            text = "Flying",
            refreshCharacter = function(element, token)
                if token == nil or not token.valid or token.properties == nil then return end
                local moveType = token.properties:CurrentMoveType()
                if moveType == "fly" then
                    element.text = "Flying"
                elseif moveType == "burrow" then
                    element.text = "Burrowing"
                elseif moveType == "climb" then
                    element.text = "Climbing"
                else
                    element.text = "On Ground"
                end
            end,
            refreshToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
            setToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
        },
        gui.Panel{
            classes = {"altitude-row"},
            gui.Label{
                classes = {"movebox-value"},
                text = "0",
                refreshCharacter = function(element, token)
                    if token == nil or not token.valid then return end
                    element.text = tostring(token.floorAltitude)
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
            },
            gui.Panel{
                classes = {"altitude-btn-stack"},
                floating = true,
                halign = "right",
                gui.Label{
                    classes = {"altitude-btn"},
                    text = "+",
                    data = { token = nil },
                    press = function(element)
                        local token = element.data.token
                        if token ~= nil then
                            if token.properties:CanFly() then
                                token.properties:SetAndUploadCurrentMoveType("fly")
                            elseif token.canCurrentlyClimb then
                                token.properties:SetAndUploadCurrentMoveType("climb")
                            elseif token.properties:CanBurrow() then
                                token.properties:SetAndUploadCurrentMoveType("burrow")
                            end
                            token:MoveVertical(token.floorAltitude + 1)
                        end
                    end,
                    refreshCharacter = function(element, token)
                        element.data.token = token
                    end,
                    refreshToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                    setToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                },
                gui.Label{
                    classes = {"altitude-btn"},
                    text = "-",
                    data = { token = nil },
                    press = function(element)
                        local token = element.data.token
                        if token ~= nil then
                            if token.properties:CanFly() then
                                token.properties:SetAndUploadCurrentMoveType("fly")
                            elseif token.canCurrentlyClimb then
                                token.properties:SetAndUploadCurrentMoveType("climb")
                            elseif token.properties:CanBurrow() then
                                token.properties:SetAndUploadCurrentMoveType("burrow")
                            end
                            token:MoveVertical(token.floorAltitude - 1)
                        end
                    end,
                    refreshCharacter = function(element, token)
                        element.data.token = token
                    end,
                    refreshToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                    setToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                },
            },
        },
    }
end

--- Display the movement panel
--- @return Panel
function TacPanel.MovementPanel()
    return gui.Panel{
        classes = {"movement-panel"},
        TacPanel.SpeedBox(),
        TacPanel.DisengageBox(),
        TacPanel.StabilityBox(),
        TacPanel.AltitudeBox(),
    }
end

--- Display a single characteristic box
--- @param attrInfo table Information about the attribute
--- @return Panel
function TacPanel.CharacteristicBox(attrInfo)
    return gui.Panel{
        classes = {"characteristic-box"},
        hoverCursor = "pressbutton",
        data = { token = nil },
        press = function(element)
            local token = element.data.token
            if token ~= nil and token.properties ~= nil then
                token.properties:ShowCharacteristicRollDialog(attrInfo.id)
            end
        end,
        refreshCharacter = function(element, token)
            element.data.token = token
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        gui.Panel{
            classes = {"container"},
            halign = "center",
            valign = "top",
            flow = "horizontal",
            gui.Label{
                classes = {"char-title", "first"},
                text = attrInfo.description:sub(1,1)
            },
            gui.Label{
                classes = {"char-title"},
                text = attrInfo.description:sub(2)
            }
        },
        gui.Label{
            classes = {"char-value"},
            text = "0",
            data = {
                attrId = attrInfo.id,
            },
            refreshCharacter = function(element, token)
                if token == nil or not token.valid or token.properties == nil then return end
                local modifier = token.properties:GetAttribute(attrInfo.id):Modifier()
                element.text = (modifier == 0) and "0" or string.format("%+d", modifier)
                element:SetClass("positive", modifier > 0)
                element:SetClass("negative", modifier < 0)
            end,
            refreshToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
            setToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,
        }
    }
end

--- Display the characteristics panel
--- @return Panel
function TacPanel.CharacteristicsPanel()
    local children = {}
    local attrList = table.values(creature.attributesInfo)
    table.sort(attrList, function(a,b) return a.order < b.order end)
    for _,attr in pairs(attrList) do
        children[#children+1] = TacPanel.CharacteristicBox(attr)
    end

    return gui.Panel{
        classes = {"characteristics-panel"},
        children = children,
    }
end

--- Display the statistics panel
--- @return Panel
function TacPanel.Statistics()
    return TacPanel.CollapsiblePanel{
        sectionId = "statistics",
        title = "STATISTICS",
        altBg = false,
        gui.Panel{
            classes = {"container"},
            width = "100%",
            valign = "top",
            halign = "left",
            hpad = 4,
            vpad = 0,
            flow = "vertical",
            TacPanel.CharacteristicsPanel(),
            TacPanel.MovementPanel(),
        }
    }
end

--- Display a heroic resource gain row
--- @param entry table from GetHeroicResourceChecklist()
--- @param token table the creature token
--- @return Panel
function TacPanel.HRGainRow(entry, token)
    return gui.Panel{
        classes = {"hr-row"},
        linger = gui.Tooltip(entry.details),
        updateCompleted = function(element, consumed)
            element:FireEventTree("setCompleted", consumed)
        end,
        gui.Panel{
            classes = {"hr-chip"},
            setCompleted = function(element, consumed)
                element:SetClassImmediate("completed", consumed)
            end,
            press = function(element)
                local q = dmhub.initiativeQueue
                if q == nil or q.hidden then
                    return
                end
                if element:HasClass("completed") then
                    return
                end
                if token == nil or not token.valid then
                    return
                end
                token:ModifyProperties{
                    description = tr("Trigger resource gain"),
                    execute = function()
                        local updateid = token.properties:GetHeroicResourceChecklistRefreshId(entry.guid)
                        if updateid == nil then
                            return
                        end
                        local record = token.properties:get_or_add("heroicResourceRecord", {})
                        local checklistBefore = {}
                        checklistBefore[entry.guid] = {record[entry.guid], updateid}
                        record[entry.guid] = updateid

                        local quantity = ExecuteGoblinScript(entry.quantity, GenerateSymbols(token.properties), 0, "Heroic Resource Amount")
                        local amount = token.properties:RefreshResource(CharacterResource.heroicResourceId, "unbounded", quantity, entry.name)
                        if amount > 0 then
                            chat.SendCustom(
                                ResourceChatMessage.new{
                                    tokenid = token.charid,
                                    resourceid = CharacterResource.heroicResourceId,
                                    quantity = amount,
                                    mode = "replenish",
                                    checklistBefore = checklistBefore,
                                    reason = entry.name,
                                }
                            )
                        end
                    end,
                }
            end,
            gui.Label{
                classes = {"label", "hr-chip-value"},
                text = string.format("+%d", tonumber(entry.quantity) or 1),
                refreshToken = not safe_toint(entry.quantity) and function(element, token)
                    local text = dmhub.EvalGoblinScript(entry.quantity, token.properties:LookupSymbol())
                    element.text = string.format("+%s", text)
                end or nil,
            },
            gui.Label{ classes = {"label", "hr-chip-event"}, text = entry.name },
        },
        gui.Label{
            classes = {"label", "hr-chip-freq"},
            text = string.format("1 / %s", g_refreshChecklistName[entry.mode or "encounter"] or "always"),
        },
    }
end

--- Display a single growing HR table row
--- @param entry table from growingResources.progression
--- @param creature table the creature properties
--- @return Panel
function TacPanel.GrowingHRRow(entry, creature)
    return gui.Panel{
        classes = {"gr-row"},
        data = { entry = entry },
        setCollapse = function(element, collapsed)
            element:SetClass("collapsed", collapsed)
        end,
        update = function(element, newEntry)
            element.data.entry = newEntry
        end,
        linger = function(element)
            if element.data.entry.tooltip ~= nil then
                gui.Tooltip(element.data.entry.tooltip)(element)
            end
        end,
        gui.Label{
            classes = {"label", "gr-value"},
            text = tostring(entry.resources),
            update = function(element, newEntry)
                element.text = tostring(newEntry.resources)
            end,
        },
        gui.Label{
            classes = {"label", "gr-text"},
            text = StringInterpolateGoblinScript(entry.description, creature),
            update = function(element, newEntry)
                local text = StringInterpolateGoblinScript(newEntry.description, creature)
                element.text = text
                element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.grText, 50, #text)
            end,
        },
    }
end

--- Display the growing heroic resource table
--- @return Panel
function TacPanel.GrowingHRTable()
    return gui.Panel{
        classes = {"growing-resources", "collapsed"},
        data = { token = nil, rows = {}, collapsed = false },
        refreshCharacter = function(element, token)
            element.data.token = token
            local creature = token.properties
            if (not creature:IsHero()) and (not creature:IsCompanion()) then
                element:SetClass("collapsed", true)
                return
            end

            local growingResources = creature:GetGrowingResourcesTable()
            if growingResources == nil then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)
            element:FireEventTree("setTitle", growingResources.name:upper())

            local characterLevel = creature:CharacterLevel()
            local characterResources = creature:GetProgressionResource()

            local rows = element.data.rows
            local rowChildren = {}
            local index = 1

            for _, entry in ipairs(growingResources.progression) do
                if (tonumber(entry.level) or 0) <= characterLevel then
                    local row = rows[index]
                    if row == nil or not row.valid then
                        row = TacPanel.GrowingHRRow(entry, creature)
                    end
                    rows[index] = row
                    index = index + 1

                    row:FireEventTree("update", entry)
                    row:SetClass("available", entry.resources <= characterResources)
                    row:SetClass("collapsed", element.data.collapsed)

                    rowChildren[#rowChildren + 1] = row
                end
            end

            for i = index, #rows do
                rows[i] = nil
            end

            element.data.rows = rows
            element:FireEventTree("setContent", rowChildren)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        gui.Panel{
            classes = {"panel", "gr-title"},
            press = function(element)
                local outer = element.parent
                outer.data.collapsed = not outer.data.collapsed
                outer:FireEventTree("setCollapse", outer.data.collapsed)
            end,
            gui.Label{
                classes = {"label", "gr-title"},
                text = "",
                setTitle = function(element, text)
                    element.text = text
                end,
            },
            gui.CollapseArrow{
                classes = {"gr-expando"},
                width = 10,
                height = 10,
                setCollapse = function(element, collapsed)
                    element:SetClass("collapseSet", collapsed)
                end,
            },
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            setContent = function(element, newChildren)
                element.children = newChildren
            end,
            setCollapse = function(element, collapsed)
                element:SetClass("collapsed", collapsed)
            end,
        },
    }
end

--- Build a collapsible TacPanel section with a title bar and collapse arrow.
--- @param args table {title, styles, classes, data, ...} plus array children
--- @return Panel
function TacPanel.CollapsiblePanel(args)
    local title = args.title or ""
    local extraClasses = args.classes or {}
    local extraData = args.data or {}
    local altBg = args.altBg ~= false
    local sectionId = args.sectionId
    args.title = nil
    args.styles = nil
    args.classes = nil
    args.data = nil
    args.altBg = nil
    args.sectionId = nil

    -- Build merged data with collapsed default
    local data = { collapsed = false, sectionId = sectionId }
    for k,v in pairs(extraData) do
        data[k] = v
    end

    -- Build merged classes
    local classes = {"tacpanel"}
    if altBg then classes[#classes+1] = "alt-bg" end
    for _,c in ipairs(extraClasses) do
        classes[#classes+1] = c
    end

    -- Title bar (always child[1]): drag handle icon, title label, collapse arrow
    local titleBar = gui.Panel{
        classes = {"tp-title-bar"},
        draggable = sectionId ~= nil,
        dragTarget = sectionId ~= nil,
        canDragOnto = function(element, target)
            return target:HasClass("tp-title-bar") and target ~= element
        end,
        drag = function(element, target)
            if target == nil then return end
            local draggedSection = element.parent
            local targetSection = target.parent
            if draggedSection == nil or targetSection == nil then return end
            if draggedSection.data == nil or targetSection.data == nil then return end
            local container = draggedSection.parent
            if container ~= nil then
                container:FireEvent("reorderSections",
                    draggedSection.data.sectionId,
                    targetSection.data.sectionId)
            end
        end,
        click = function(element)
            local outer = element.parent
            outer.data.collapsed = not outer.data.collapsed
            outer:FireEventTree("setCollapse", outer.data.collapsed)
        end,
        sectionId and gui.Panel{
            classes = {"tp-drag-handle"},
        } or nil,
        gui.Label{
            classes = {"panel-title"},
            text = title,
        },
        gui.CollapseArrow{
            classes = {"tp-expando"},
            floating = true,
            width = 15,
            height = 10,
            setCollapse = function(element, collapsed)
                element:SetClass("collapseSet", collapsed)
            end,
        },
    }

    -- Collect content children from array entries into a single wrapper
    local contentPanelArgs = {
        width = "100%",
        height = "auto",
        flow = "vertical",
        setCollapse = function(element, collapsed)
            element:SetClass("collapsed", collapsed)
        end,
    }
    for i,child in ipairs(args) do
        contentPanelArgs[#contentPanelArgs+1] = child
        args[i] = nil
    end
    local contentPanel = gui.Panel(contentPanelArgs)

    -- Build the outer panel args: titleBar (child[1]), contentPanel (child[2])
    local panelArgs = {
        classes = classes,
        data = data,
        titleBar,
        contentPanel,
    }

    -- Pass through all remaining args properties
    for k,v in pairs(args) do
        panelArgs[k] = v
    end

    local panel = gui.Panel(panelArgs)

    -- Sync initial collapsed state so arrow, content wrapper, etc. all match
    if data.collapsed then
        panel:FireEventTree("setCollapse", true)
    end

    return panel
end

--- Build a single collapsible entry with a left-side expando arrow.
--- Single label uses one format string for both states.
--- @param args table {entryKey, entryId, charid, title, body, color, classes?}
--- @return Panel
function TacPanel.CollapsibleEntry(args)
    local entryKey     = args.entryKey
    local entryId      = args.entryId
    local charid       = args.charid
    local title        = args.title
    local body         = args.body
    local color        = args.color or ThemeEngine.ResolveTokens("@fgMuted")
    local extraClasses = args.classes or {}

    local prefKey = string.format("ce:%s:%s:%s", entryKey, charid or "default", entryId or "")
    local saved = dmhub.GetPref(prefKey)
    local collapsed = saved ~= "open"  -- default collapsed

    local classes = {"ce-entry"}
    for _, c in ipairs(extraClasses) do
        classes[#classes + 1] = c
    end

    local entry = gui.Panel{
        classes = classes,
        data = {
            collapsed = collapsed, prefKey = prefKey,
            title = title, body = body, color = color,
            formatText = function(d, isCollapsed)
                return string.format("**<color=%s>%s%s</color>** %s",
                    d.color, d.title, isCollapsed and "" or ":", isCollapsed and "" or d.body)
            end,
        },
        press = function(element)
            element.data.collapsed = not element.data.collapsed
            local newState = element.data.collapsed
            element:FireEventTree("setCollapse", newState)
            if newState then
                dmhub.SetPref(element.data.prefKey, nil)
            else
                dmhub.SetPref(element.data.prefKey, "open")
            end
        end,
        -- Refresh title/body in place without rebuilding the panel; preserves
        -- collapse state so the arrow does not replay its scale animation.
        update = function(element, spec)
            local d = element.data
            d.title = spec.title
            d.body  = spec.body
            if spec.color ~= nil then d.color = spec.color end
            element:FireEventTree("setCollapse", d.collapsed)
        end,
        rightClick = function(element)
            local d = element.data
            local fullText = d:formatText(false)
            element.popup = gui.ContextMenu{
                entries = {
                    {
                        text = "Copy to Clipboard",
                        click = function()
                            dmhub.CopyToClipboard(fullText)
                            element.popup = nil
                        end,
                    },
                    {
                        text = "Show in Chat",
                        click = function()
                            chat.Send(fullText)
                            element.popup = nil
                        end,
                    },
                },
            }
        end,
        gui.CollapseArrow{
            classes = {"ce-expando"},
            width = 10,
            height = 10,
            setCollapse = function(element, isCollapsed)
                element:SetClass("collapseSet", isCollapsed)
            end,
        },
        gui.Label{
            classes = {"ce-text"},
            textWrap = true,
            markdown = true,
            text = "",
            setCollapse = function(element, isCollapsed)
                local d = element.parent.data
                element:SetClass("ce-collapsed", isCollapsed)
                element.text = d:formatText(isCollapsed)
            end,
        },
    }

    entry:FireEventTree("setCollapse", collapsed)
    return entry
end

--- Build a vertical container that diffs CollapsibleEntry children across refreshes.
--- Fire `setEntries` with a list of {entryKey, entryId, charid, title, body, color?, classes?}
--- spec tables. Existing panels are reused (preserving collapse state and avoiding the
--- arrow's scale animation), missing ones drop out, new ones are built. Cache key is
--- charid+entryKey+entryId so per-character prefKeys are not reused across tokens.
--- @return Panel
function TacPanel.CollapsibleEntryContainer()
    return gui.Panel{
        classes = {"container"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        data = { entries = {} },
        setEntries = function(element, specs)
            local oldCache = element.data.entries
            local newCache = {}
            local children = {}
            for _, spec in ipairs(specs) do
                local key = string.format("%s:%s:%s",
                    tostring(spec.charid or ""),
                    tostring(spec.entryKey or ""),
                    tostring(spec.entryId or ""))
                local entry
                if newCache[key] == nil then
                    entry = oldCache[key]
                    if entry ~= nil then
                        entry:FireEvent("update", spec)
                    else
                        entry = TacPanel.CollapsibleEntry(spec)
                    end
                    newCache[key] = entry
                else
                    -- Defensive: duplicate spec key in a single refresh.
                    -- Build standalone so the children list stays valid; not cached.
                    entry = TacPanel.CollapsibleEntry(spec)
                end
                children[#children+1] = entry
            end
            element.data.entries = newCache
            element.children = children
        end,
    }
end

--- Display the Routines panel
--- @return Panel
function TacPanel.Routines()
    return TacPanel.CollapsiblePanel{
        sectionId = "routines",
        classes = {"collapsed"},
        altBg = false,
        title = "ROUTINES",
        data = { routinePanels = {} },
        setCollapse = function(element)
            element:FireEvent("refreshCharacter", element.data.token)
        end,
        refreshCharacter = function(element, token)
            if token == nil or not token.valid then
                element:SetClass("collapsed", true)
                return
            end

            element.data.token = token
            local routines = token.properties:GetRoutines()
            if routines == nil or #routines == 0 then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)

            if element.data.collapsed then
                return
            end

            local routinesSelected = token.properties:try_get("routinesSelected") or {}
            local newPanels = {}
            local children = {}

            -- "None" chip
            local noneSelected = (token.properties:try_get("routinesSelected") == nil)
            children[#children+1] = gui.Panel{
                classes = {"rt-chip"},
                press = function(el)
                    token:ModifyProperties{
                        description = tr("Select Routine"),
                        execute = function()
                            token.properties.routinesSelected = nil
                        end,
                    }
                end,
                gui.Label{
                    classes = {"rt-chip"},
                    text = "None",
                },
            }

            for _,routine in ipairs(routines) do
                local selected = (routinesSelected[routine.guid] ~= nil)
                local panel = element.data.routinePanels[routine.guid]

                if panel == nil then
                local routineLabel = gui.Label{
                    classes = {"rt-chip"},
                    text = routine.name,
                    popupPositioning = "panel",
                    hover = function(el)
                        el.tooltip = gui.TooltipFrame(routine:Render{}, {
                            halign = "left",
                            valign = "top",
                        })
                    end,
                    press = function(el)
                        token:ModifyProperties{
                            description = tr("Select Routine"),
                            execute = function()
                                local sel = token.properties:get_or_add("routinesSelected", {})
                                if sel[routine.guid] then
                                    sel[routine.guid] = nil
                                else
                                    sel[routine.guid] = ServerTimestamp()
                                end
                                token.properties.routinesSelected = sel
                            end,
                        }
                    end,
                    selectionChanged = function(el, sel)
                        el:SetClass("selected", sel)
                    end,
                }
                panel = gui.Panel{
                    data = { selected = false, label = routineLabel },
                    classes = {"rt-chip"},
                    flow = "horizontal",

                    routineLabel,

                    selectionChanged = function(el, sel)
                        el:SetClass("selected", sel)

                        if not sel then
                            el.children = {el.data.label}
                            return
                        end

                        el.children = {
                            el.data.label,
                            gui.Panel{
                                valign = "center",
                                halign = "right",
                                width = "auto",
                                height = "auto",
                                bgimage = true,
                                bgcolor = "clear",
                                pad = 3,
                                lmargin = 4,
                                gui.VisibilityPanel{
                                    classes = {"visDot"},
                                    opacity = 1,
                                    visible = true,
                                    width = 12,
                                    height = 12,
                                    press = function(element)
                                        local settings = DeepCopy(token.properties:GetAuraDisplaySetting(routine.name))
                                        settings.hide = not settings.hide

                                        token:ModifyProperties{
                                            description = tr("Set Aura Display Settings"),
                                            undoable = false,
                                            execute = function()
                                                token.properties:SetAuraDisplaySetting(routine.name, settings)
                                            end,
                                        }
                                    end,
                                    refresh = function(element)
                                        if token == nil or not token.valid then
                                            return
                                        end

                                        element:FireEvent("visible", not token.properties:GetAuraDisplaySetting(routine.name).hide)
                                    end,
                                },
                            },
                            gui.ColorPicker{
                                classes = {"bordered"},
                                valign = "center",
                                halign = "right",
                                hmargin = 6,
                                width = 20,
                                height = 20,
                                hasAlpha = true,
                                value = token.properties:GetAuraDisplaySetting(routine.name).bgcolor
                                    or (token.playerControlled and token.playerColor.tostring or "#AA0000"),
                                change = function(element)
                                    --Live preview during drag (gui.ColorPicker
                                    --fires `change` per-frame while dragging).
                                    --Mutate in place; confirm handles upload.
                                    local settings = DeepCopy(token.properties:GetAuraDisplaySetting(routine.name))
                                    settings.bgcolor = element.value.tostring
                                    token.properties:SetAuraDisplaySetting(routine.name, settings)
                                    token:UpdateAuras()
                                end,
                                confirm = function(element)
                                    --Snapshot final state, clear, and re-apply
                                    --inside ModifyProperties so the diff actually
                                    --uploads (without the clear, the live-preview
                                    --already-set value would make ModifyProperties
                                    --see no diff).
                                    local preserved = DeepCopy(token.properties:GetAuraDisplaySetting(routine.name))
                                    preserved.bgcolor = element.value.tostring
                                    token.properties:SetAuraDisplaySetting(routine.name, nil)
                                    token:ModifyProperties{
                                        description = tr("Set Aura Color"),
                                        undoable = false,
                                        execute = function()
                                            token.properties:SetAuraDisplaySetting(routine.name, preserved)
                                        end,
                                    }
                                    token:UpdateAuras()
                                end,
                            }
                        }
                    end,
                }
                end

                if selected ~= panel.data.selected then
                    panel.data.selected = selected
                    panel:FireEvent("selectionChanged", selected)
                end

                children[#children+1] = panel
                newPanels[routine.guid] = panel
            end

            element.data.routinePanels = newPanels
            element:FireEventTree("setContent", children)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        gui.Panel{
            classes = {"rt-container"},
            wrap = true,
            setContent = function(element, newChildren)
                element.children = newChildren
            end,
        },
    }
end

--- Display the summoner's squads, each a row of minion portraits with a shared
--- health bar.
--- @return Panel
function TacPanel.Summoner()
    local function BuildSquadRow(squadName, info, liveTokens, sq)
        local portraits = {}
        for _, tok in ipairs(liveTokens) do
            portraits[#portraits + 1] = gui.CreateTokenImage(tok, {
                width = 28,
                height = 28,
                halign = "left",
                hmargin = 2,
            })
        end

        local maximum = sq.maximum_health or 1
        if maximum <= 0 then maximum = 1 end
        local initialPct = math.max(0, math.min(1, (maximum - (sq.damage_taken or 0)) / maximum))

        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            bmargin = 6,

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",

                gui.Label{
                    classes = {"sizeS", "bold", "fg"},
                    text = squadName,
                    width = "auto",
                    height = "auto",
                    halign = "left",
                },

                gui.Label{
                    classes = {"sizeS", "fg"},
                    text = string.format("%d / %d", sq.liveMinions or #liveTokens, #info.charids),
                    width = "auto",
                    height = "auto",
                    halign = "right",
                },
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                vmargin = 2,
                children = portraits,
            },

            gui.Panel{
                classes = {"fillBar", "bordered"},
                width = 175,
                height = 14,
                halign = "left",

                gui.Panel{
                    classes = {"fillBarFill"},
                    interactable = false,
                    width = string.format("%.02f%%", initialPct * 100),
                    height = "100%",
                    halign = "left",
                    -- fillBarFill paints a theme-independent grayscale shade; the
                    -- bgcolor tint carries each squad's own color (or @accent if none).
                    selfStyle = {
                        bgcolor = sq.color,
                    },
                    data = {
                        fillLast = initialPct,
                        pctLast = initialPct,
                        colorLast = sq.color,
                        damageLast = sq.damage_taken or 0,
                        maxLast = sq.maximum_health or 0,
                    },
                    thinkTime = 0.1,
                    think = function(fill)
                        -- Recompute target percent only when the underlying
                        -- damage/max actually changed. Avoids per-tick math.
                        local damage = sq.damage_taken or 0
                        local maxhp = sq.maximum_health or 0
                        if damage ~= fill.data.damageLast or maxhp ~= fill.data.maxLast then
                            fill.data.damageLast = damage
                            fill.data.maxLast = maxhp
                            local denom = maxhp
                            if denom <= 0 then denom = 1 end
                            fill.data.pctLast = math.max(0, math.min(1, (maxhp - damage) / denom))
                        end

                        -- Lerp toward target. Stop touching style once we
                        -- are within a pixel of the target so a settled bar
                        -- costs zero per-tick work.
                        local diff = fill.data.pctLast - fill.data.fillLast
                        if math.abs(diff) > 0.002 then
                            fill.data.fillLast = fill.data.fillLast + diff * 0.25
                            fill.selfStyle.width = string.format("%.02f%%", fill.data.fillLast * 100)
                        elseif fill.data.fillLast ~= fill.data.pctLast then
                            fill.data.fillLast = fill.data.pctLast
                            fill.selfStyle.width = string.format("%.02f%%", fill.data.fillLast * 100)
                        end

                        if sq.color ~= fill.data.colorLast then
                            fill.data.colorLast = sq.color
                            fill.selfStyle.bgcolor = sq.color
                        end
                    end,
                },

                gui.Label{
                    classes = {"bold", "fg"},
                    interactable = false,
                    floating = true,
                    halign = "center",
                    valign = "center",
                    width = "auto",
                    height = "auto",
                    fontSize = 11,
                    textAlignment = "center",
                    text = string.format("%d / %d",
                        math.max(0, (sq.maximum_health or 0) - (sq.damage_taken or 0)),
                        sq.maximum_health or 0),
                    data = {
                        damageLast = sq.damage_taken or 0,
                        maxLast = sq.maximum_health or 0,
                    },
                    thinkTime = 0.25,
                    think = function(label)
                        local damage = sq.damage_taken or 0
                        local maxhp = sq.maximum_health or 0
                        if damage == label.data.damageLast and maxhp == label.data.maxLast then
                            return
                        end
                        label.data.damageLast = damage
                        label.data.maxLast = maxhp
                        label.text = string.format("%d / %d", math.max(0, maxhp - damage), maxhp)
                    end,
                },
            },
        }
    end

    return TacPanel.CollapsiblePanel{
        sectionId = "summoner",
        classes = {"collapsed"},
        altBg = false,
        title = "SUMMONER",
        data = {},
        setCollapse = function(element)
            element:FireEvent("refreshCharacter", element.data.token)
        end,
        refreshCharacter = function(element, token)
            if token == nil or not token.valid then
                element:SetClass("collapsed", true)
                return
            end

            element.data.token = token

            local range = token.properties:CalculateNamedCustomAttribute("SummonerRange") or 0
            if range <= 0 then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            vmargin = 4,

            gui.Button{
                classes = {"sizeM"},
                halign = "center",
                width = 175,
                height = 40,
                text = "Sacrifice Minions",
                hover = function(element)
                    element.tooltip = gui.Tooltip("You can willingly sacrifice one or more of your minions to reduce the cost of a heroic ability by 1 or more.")
                end,
                data = { token = nil },
                refreshToken = function(element, token)
                    element.data.token = token
                end,
                press = function(element)
                    local token = element.data.token
                    if token == nil or not token.valid then return end
                    local ability = MCDMUtils.GetStandardAbility("Summoner Sacrifice Minions")
                    if ability == nil then return end
                    local clone = ability:MakeTemporaryClone()
                    gamehud.actionBarPanel:FireEventTree("invokeAbility", token, clone, {})
                end,
            },

            gui.Panel{
                classes = {"summoner-squads"},
                width = "100%",
                height = "auto",
                flow = "vertical",
                vmargin = 6,
                data = { token = nil, rosterSignature = false },
                refreshToken = function(element, token)
                    element.data.token = token
                    -- Force a rebuild on the next think tick when the token swaps.
                    element.data.rosterSignature = false
                end,
                thinkTime = 0.25,
                think = function(element)
                    local token = element.data.token
                    if token == nil or not token.valid or token.properties == nil then
                        if element.data.rosterSignature ~= "" then
                            element.data.rosterSignature = ""
                            element.children = {}
                        end
                        return
                    end

                    -- Gather live squads and build a stable signature from
                    -- squad names + sorted live charids. Damage and other
                    -- mutable state are NOT in the signature -- those flow
                    -- through the inner think handlers on the bar/label,
                    -- so we don't recreate token portraits each game tick.
                    local squads = token.properties:GetSummonedSquadsByType(nil) or {}
                    local squadList = {}
                    local sigParts = {}
                    for squadName, info in pairs(squads) do
                        local liveTokens = {}
                        for _, charid in ipairs(info.charids) do
                            local mt = dmhub.GetTokenById(charid)
                            if mt ~= nil and mt.valid and mt.properties ~= nil and not mt.properties:IsDeadOrDying() then
                                liveTokens[#liveTokens + 1] = mt
                            end
                        end
                        if #liveTokens > 0 then
                            table.sort(liveTokens, function(a, b) return a.charid < b.charid end)
                            squadList[#squadList + 1] = {
                                name = squadName,
                                info = info,
                                liveTokens = liveTokens,
                            }
                            local ids = {}
                            for _, t in ipairs(liveTokens) do ids[#ids + 1] = t.charid end
                            sigParts[#sigParts + 1] = squadName .. "=" .. table.concat(ids, ",")
                        end
                    end
                    table.sort(squadList, function(a, b) return a.name < b.name end)
                    table.sort(sigParts)
                    local signature = table.concat(sigParts, "|")

                    if signature == element.data.rosterSignature then return end
                    element.data.rosterSignature = signature

                    local children = {}
                    for _, entry in ipairs(squadList) do
                        local leader = entry.liveTokens[1]
                        leader.properties:RefreshSquadInfo(leader)
                        local sq = leader.properties:try_get("_tmp_minionSquad")
                        if sq ~= nil then
                            children[#children + 1] = BuildSquadRow(entry.name, entry.info, entry.liveTokens, sq)
                        end
                    end
                    element.children = children
                end,
            },

            gui.Label{
                classes = {"fg", "bgAlt", "sizeXs"},
                width = "100%",
                height = "auto",
                hpad = 4,
                halign = "left",
                textAlignment = "topleft",
                markdown = true,
                text = "<u>**Your Minion Squads**</u>\n"
                    .. "* Move Action\n"
                    .. "* Maneuver or Main Action\n"
                    .. "* If a minion has a signature ability, apply one instance of the effects to each target.\n"
                    .. "* Each additional minion that strikes the target adds their free strike value to the action.",
            },
        },
    }
end

local g_heroicResourceDisplays = {}

--- Register a heroic-resource display box (shown in the summary token boxes).
--- @param entry {id: string, create: fun(): Panel, ord: number}
function TacPanel.RegisterHeroicResourceDisplay(entry)
    g_heroicResourceDisplays[entry.id] = entry
end

TacPanel.RegisterHeroicResourceDisplay{
    id = "victories",
    create = TacPanel.VictoriesBox,
    ord = 0,
}

TacPanel.RegisterHeroicResourceDisplay{
    id = "heroic",
    create = TacPanel.HeroicResourcesBox,
    ord = 1,
}

--- Display the heroic resources info
--- @return Panel
function TacPanel.HeroicResources()

    local displays = {}
    for id, entry in pairs(g_heroicResourceDisplays) do
        local pane = entry.create()
        pane.data.ord = entry.ord or 0
        displays[#displays + 1] = pane
    end

    table.sort(displays, function (a, b)
        return (a.data.ord or 0) < (b.data.ord or 0)
    end)

    return TacPanel.CollapsiblePanel{
        sectionId = "heroicresources",
        classes = {"collapsed"},
        altBg = false,
        title = "HEROIC RESOURCES",
        refreshCharacter = function(element, token)
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end
            local hasRampage = token.properties.GetRampageDisplayToken ~= nil and token.properties:GetRampageDisplayToken() ~= nil
            local shouldShow = token.properties:IsHero() or hasRampage
            element:SetClass("collapsed", not shouldShow)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        gui.Panel{
            classes = {"container"},
            width = "100%",
            valign = "top",
            halign = "left",
            pad = 4,
            flow = "horizontal",
            gui.Panel{
                classes = {"container"},
                width = "auto",
                halign = "left",
                valign = "top",
                flow = "vertical",
                children = displays,
            },
            gui.Panel{
                classes = {"hr-gains"},
                data = { token = nil, panels = {} },
                refreshCharacter = function(element, token)
                    element.data.token = token
                    local creature = token.properties
                    local checklist = creature:GetHeroicResourceChecklist()
                    if checklist == nil or #checklist == 0 then
                        element.children = {}
                        element.data.panels = {}
                        return
                    end

                    local panels = element.data.panels
                    local newPanels = {}
                    local children = {}

                    for _, entry in ipairs(checklist) do
                        local consumed
                        local q = dmhub.initiativeQueue
                        local record = creature:try_get("heroicResourceRecord")
                        if q == nil or q.hidden or entry.mode == "recurring" or record == nil or record[entry.guid] == nil or record[entry.guid] ~= creature:GetResourceRefreshId(entry.mode or "encounter") then
                            consumed = false
                        else
                            consumed = true
                        end

                        local panel = panels[entry.guid] or TacPanel.HRGainRow(entry, token)

                        panel:FireEvent("updateCompleted", consumed)

                        newPanels[entry.guid] = panel
                        children[#children + 1] = panel
                    end

                    element.data.panels = newPanels
                    element.children = children
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
            },
        },
        TacPanel.GrowingHRTable(),
    }
end

--- Display Epic and other custom resources
--- @param token any token
--- @param resource any CharacterResource
--- @param quantity number max quantity of the resource
--- @param styleCache table<string, any> cache keyed by resource id
--- @return Panel
function TacPanel.OtherResourceRow(token, resource, quantity, styleCache)
    local creature = token.properties
    local styles = styleCache[resource.id] or resource:CreateStyles()
    styleCache[resource.id] = styles

    local numExpended = creature:GetResourceUsage(resource.id, resource.usageLimit) or 0
    local remaining = math.max(0, (quantity or 0) - numExpended)

    local displayName = resource.name
    if resource.id == CharacterResource.epicResourceId then
        displayName = creature:GetEpicResourceName() or resource.name
    end

    return gui.Panel{
        classes = {"other-resource-row"},
        width = "100%",
        height = 24,
        flow = "horizontal",
        halign = "left",
        valign = "top",
        vmargin = 2,
        data = {
            token = token,
            resourceId = resource.id,
            usageLimit = resource.usageLimit,
            maxQuantity = quantity or 0,
        },

        -- icon
        gui.Panel{
            width = 20,
            height = 20,
            halign = "left",
            valign = "center",
            hmargin = 4,
            bgcolor = "white",
            bgimage = resource:GetImage("normal") or "",
            styles = styles,
            classes = {"normal"},
        },

        -- name label
        gui.Label{
            classes = {"sizeS"},
            width = "100%-116",
            height = "auto",
            halign = "left",
            valign = "center",
            hmargin = 6,
            text = displayName,
        },

        -- remaining / max input
        gui.Input{
            classes = {"sizeM"},
            width = 70,
            height = 22,
            halign = "right",
            valign = "center",
            hmargin = 6,
            characterLimit = 9,
            selectAllOnFocus = true,
            placeholderText = "--",
            textAlignment = "center",
            bgcolor = "clear",
            border = 0,
            text = string.format("%d/%d", remaining, quantity or 0),
            change = function(element)
                local rowData = element.parent.data
                local tok = rowData.token
                if tok == nil or not tok.valid then return end
                local maxQuantity = rowData.maxQuantity or 0
                local resourceId = rowData.resourceId
                local usageLimit = rowData.usageLimit
                local creatureRef = tok.properties
                local currentExpended = creatureRef:GetResourceUsage(resourceId, usageLimit) or 0
                local currentRemaining = math.max(0, maxQuantity - currentExpended)

                local textValue = element.text
                local n
                local slash = string.find(textValue, "/", 1, true)
                if slash ~= nil then
                    n = tonum(string.sub(textValue, 1, slash - 1), nil)
                else
                    n = tonum(textValue, nil)
                end

                if n == nil then
                    element.textNoNotify = string.format("%d/%d", currentRemaining, maxQuantity)
                    return
                end

                n = math.max(0, math.min(n, maxQuantity))
                local diff = n - currentRemaining
                if diff ~= 0 then
                    tok:ModifyProperties{
                        description = string.format("Change %s", displayName),
                        execute = function()
                            if diff > 0 then
                                tok.properties:RefreshResource(resourceId, usageLimit, diff)
                            else
                                tok.properties:ConsumeResource(resourceId, usageLimit, -diff)
                            end
                        end,
                    }
                end
                local newExpended = tok.properties:GetResourceUsage(resourceId, usageLimit) or 0
                local newRemaining = math.max(0, maxQuantity - newExpended)
                element.textNoNotify = string.format("%d/%d", newRemaining, maxQuantity)
            end,
        },
    }
end

--- Display custom/epic resources that have no dedicated tactical panel box.
--- Hidden entirely when the creature has none.
--- @return Panel
function TacPanel.OtherResources()
    local resourceStyles = {}

    -- Resource ids that already have dedicated displays elsewhere in the
    -- tactical panel / summary and should not be duplicated here.
    local excludedIds = {
        [CharacterResource.heroicResourceId] = true,
        [CharacterResource.maliceResourceId] = true,
        [CharacterResource.surgeResourceId] = true,
        [CharacterResource.heroTokenId] = true,
        [CharacterResource.recoveryResourceId] = true,
        [CharacterResource.actionResourceId] = true,
        [CharacterResource.maneuverResourceId] = true,
        [CharacterResource.freeManeuverResourceId] = true,
        [CharacterResource.triggerResourceId] = true,
        [CharacterResource.rampageId] = true,
    }

    return TacPanel.CollapsiblePanel{
        sectionId = "otherresources",
        classes = {"collapsed"},
        altBg = false,
        title = "RESOURCES",
        data = { token = nil },

        refreshCharacter = function(element, token)
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end

            element.data.token = token
            local creature = token.properties
            local resourceTable = dmhub.GetTable(CharacterResource.tableName) or {}
            local resources = creature:GetResources()

            local entries = {}
            for resourceid, quantity in pairs(resources) do
                if (quantity or 0) > 0 and not excludedIds[resourceid] then
                    local resource = resourceTable[resourceid]
                    if resource ~= nil
                        and not resource:try_get("hidden", false)
                        and resource.grouping ~= "Hidden"
                        and resource.grouping ~= "Actions" then
                        entries[#entries+1] = {
                            resource = resource,
                            id = resourceid,
                            quantity = quantity,
                        }
                    end
                end
            end

            if #entries == 0 then
                element:SetClass("collapsed", true)
                return
            end

            -- Epic resource first when present, otherwise alphabetical.
            table.sort(entries, function(a, b)
                local aEpic = a.id == CharacterResource.epicResourceId
                local bEpic = b.id == CharacterResource.epicResourceId
                if aEpic ~= bEpic then return aEpic end
                return a.resource.name < b.resource.name
            end)

            element:SetClass("collapsed", false)
            element:FireEventTree("setEntries", {
                token = token,
                entries = entries,
            })
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        gui.Panel{
            classes = {"container"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            hpad = 4,
            vpad = 4,
            setEntries = function(element, info)
                local children = {}
                for _, entry in ipairs(info.entries) do
                    children[#children+1] = TacPanel.OtherResourceRow(
                        info.token, entry.resource, entry.quantity, resourceStyles)
                end
                element.children = children
            end,
        },
    }
end

--- Display the Skills & Languages panel
--- @return Panel
function TacPanel.SkillLanguages()
    return TacPanel.CollapsiblePanel{
        sectionId = "skilllanguages",
        altBg = false,
        title = "SKILLS & LANGUAGES",
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            refreshCharacter = function(element, token)
                local creature = token.properties
                local children = {}
                -- Skill categories
                for _, cat in ipairs(Skill.categories) do
                    local proficiencyList = nil
                    for _, skill in ipairs(Skill.SkillsInfo) do
                        if skill.category == cat.id and creature:ProficientInSkill(skill) then
                            if proficiencyList == nil then
                                proficiencyList = skill.name
                            else
                                proficiencyList = proficiencyList .. ", " .. skill.name
                            end
                        end
                    end
                    if proficiencyList ~= nil then
                        children[#children + 1] = gui.Label{
                            classes = {"skillslangs"},
                            textWrap = true,
                            markdown = true,
                            text = ThemeEngine.ResolveTokens(string.format("**<color=@fgMuted>%s:</color>** %s", cat.text, proficiencyList))
                        }
                    end
                end
                -- Languages
                local languagesTable = dmhub.GetTable(Language.tableName) or {}
                local languages = {}
                for langid, _ in pairs(creature:LanguagesKnown()) do
                    local language = languagesTable[langid]
                    if language then
                        languages[#languages + 1] = language
                    end
                end
                table.sort(languages, function(a, b) return a.name < b.name end)
                local langText = nil
                for _, language in ipairs(languages) do
                    if langText == nil then
                        langText = language.name
                    else
                        langText = langText .. ", " .. language.name
                    end
                end
                if langText ~= nil then
                    children[#children + 1] = gui.Label{
                        classes = {"skillslangs"},
                        textWrap = true,
                        markdown = true,
                        text = ThemeEngine.ResolveTokens(string.format("**<color=@fgMuted>Languages:</color>** %s", langText))
                    }
                end
                element.children = children
            end,
            refreshToken = function(element, token) element:FireEvent("refreshCharacter", token) end,
            setToken = function(element, token) element:FireEvent("refreshCharacter", token) end,
        },
    }
end

--- Display the Features panel
--- @return Panel
--Best-effort description for a curated index entry. Mirrors the sheet's
--FeatureEntryDescription: each probe is pcall-isolated because reading a
--missing method on a game type errors rather than returning nil. Falls back to
--a folded made-choice's chosen feature (the slot row represents that outcome).
local function FeatureTacDescription(entry)
    local desc = nil
    pcall(function() desc = entry.feature:GetDescription() end)
    if desc == nil or desc == "" then
        pcall(function() desc = entry.feature:try_get("description") end)
    end
    if (desc == nil or desc == "") and entry.chosen ~= nil then
        for _,c in ipairs(entry.chosen) do
            pcall(function()
                local d = c:GetDescription()
                if d == nil or d == "" then d = c:try_get("description") end
                if d ~= nil and d ~= "" then desc = d end
            end)
            if desc ~= nil and desc ~= "" then break end
        end
    end
    if desc == "" then desc = nil end
    return desc
end

--"Bucket - Origin" header text for a curated group: appends the origin name
--when every entry shares one (e.g. "Class - Censor"), mirroring the sheet's
--Features tab headers. Falls back to the bare bucket name on mixed origins.
local function FeatureGroupHeaderText(group)
    local origin, mixed = nil, false
    for _,e in ipairs(group.items) do
        if e.originName ~= nil and e.originName ~= "" then
            if origin == nil then origin = e.originName
            elseif origin ~= e.originName then mixed = true end
        end
    end
    if origin ~= nil and not mixed then
        return string.format("%s - %s", group.bucket.name, origin)
    end
    return group.bucket.name
end

--A single feature chip: name only. Click opens a small popup with the
--description and an "Open on sheet" link (the ch5 filterFeatures deep-link).
--View + link only -- choice-changing stays on the sheet.
--- @param token CharacterToken
--- @param name string display name
--- @param descFn function () -> string|nil resolved on click (lazy)
--- @return Panel
function TacPanel.FeatureChip(token, name, descFn)
    local chip
    chip = gui.Panel{
        classes = {"panel", "cond-chip", "feature-chip"},
        data = { matchName = string.lower(name or "") },
        click = function(element)
            local capturedId = token.id
            local desc = (descFn and descFn()) or "*No description.*"
            element.popupsInheritStyles = true
            element.popup = gui.Panel{
                classes = {"dialog"},
                floating = true,
                flow = "vertical",
                width = 280,
                height = "auto",
                pad = 8,
                gui.Label{
                    width = "100%", height = "auto",
                    bold = true, fontSize = 14, color = "@fg",
                    text = name,
                },
                gui.Label{
                    width = "100%", height = "auto",
                    markdown = true, fontSize = 12, color = "@fg",
                    tmargin = 4,
                    text = desc,
                },
                gui.Label{
                    width = "auto", height = "auto",
                    halign = "right", tmargin = 6,
                    bold = true, fontSize = 12, color = "@accent",
                    text = "Open on sheet",
                    click = function(linkEl)
                        chip.popup = nil
                        FeatureCategoriser.OpenSheetAtFeaturesTab(capturedId, name)
                    end,
                },
            }
        end,
        gui.Label{
            classes = {"label", "cond-name"},
            text = name,
        },
    }
    return chip
end

--- The tac-panel Features section (search redesign ch6): a curated, in-context
--- "what ELSE can my character do" view -- the passive capabilities not already
--- on the action bar or a sibling tac section. Grouped by origin (collapsed,
--- with counts), chips inside, a local filter, and a click-through to the
--- sheet. Heroes gain a section they never had; monsters keep their traits.
--- @return Panel
function TacPanel.Features()
    local m_token = nil
    local m_filter = ""       -- the active filter (the Filter box text)
    local m_filterFromGlobal = false  -- true when the title-bar search set the filter
    local m_expanded = {}     -- bucketId -> true (group expansion, survives refresh)
    local m_expandedLevels = {} -- level -> true (Class by-level sub-groups)

    local section, filterInput, clearButton, countLabel, groupsContainer

    --A wrapped chip body for a set of entries.
    local function chipWrap(token, entries)
        local chipPanels = {}
        for _,e in ipairs(entries) do
            local captured = e
            chipPanels[#chipPanels+1] = TacPanel.FeatureChip(token, e.name or "Feature",
                function() return FeatureTacDescription(captured) end)
        end
        return gui.Panel{
            classes = {"panel", "cond-chips"},
            wrap = true,
            lmargin = 6,
            children = chipPanels,
        }
    end

    --A collapsible "Level N (count)" sub-group (Class bucket only), mirroring
    --the ch5 sheet's by-level sub-grouping. Toggles in place; filtering forces
    --it open and disables the toggle.
    local function buildLevelGroup(token, lvl, entries, locked)
        local expanded = locked or (m_expandedLevels[lvl] == true)
        local body = chipWrap(token, entries)
        body:SetClass("collapsed", not expanded)

        local arrow = gui.CollapseArrow{ width = 9, height = 9, valign = "center", hmargin = 4 }
        arrow:SetClass("collapseSet", not expanded)

        local header = gui.Panel{
            width = "100%", height = "auto", flow = "horizontal", valign = "center", vmargin = 1,
            press = function()
                if locked then return end
                local now = not (m_expandedLevels[lvl] == true)
                if now then m_expandedLevels[lvl] = true else m_expandedLevels[lvl] = nil end
                body:SetClass("collapsed", not now)
                arrow:SetClass("collapseSet", not now)
            end,
            arrow,
            gui.Label{
                width = "auto", height = "auto", valign = "center",
                fontSize = 11, color = "@fgMuted",
                text = string.format("%s (%d)",
                    cond(lvl > 0, string.format("Level %d", lvl), "Other"), #entries),
            },
        }
        return gui.Panel{ width = "100%-8", halign = "right", height = "auto", flow = "vertical", header, body }
    end

    --Build a collapsible origin group: header (arrow + "Bucket - Origin (N)")
    --over a chip body. The Class bucket sub-groups its chips by level; other
    --buckets are a flat chip wrap. Expansion toggles in place (no rebuild).
    --When filtering the group is forced open and only matching chips are built.
    --`locked` = filtering (no manual collapse while a filter is active).
    local function buildGroup(token, group, locked, needle)
        local items = {}
        for _,e in ipairs(group.items) do
            if not locked or Search.MatchesText(e.searchText or e.name or "", needle) then
                items[#items+1] = e
            end
        end
        if #items == 0 then return nil, 0 end

        local expanded = locked or (m_expanded[group.bucket.id] == true)

        local body
        if group.bucket.id == "class" then
            --Sub-group the matching items by level (ascending; "Other" = 0).
            local byLevel, levelsSeen = {}, {}
            for _,e in ipairs(items) do
                local lvl = e.level or 0
                if byLevel[lvl] == nil then
                    byLevel[lvl] = {}
                    levelsSeen[#levelsSeen+1] = lvl
                end
                local t = byLevel[lvl]
                t[#t+1] = e
            end
            table.sort(levelsSeen)
            local levelPanels = {}
            for _,lvl in ipairs(levelsSeen) do
                levelPanels[#levelPanels+1] = buildLevelGroup(token, lvl, byLevel[lvl], locked)
            end
            body = gui.Panel{
                width = "100%", height = "auto", flow = "vertical", lmargin = 4,
                children = levelPanels,
            }
        else
            body = chipWrap(token, items)
        end
        body:SetClass("collapsed", not expanded)

        local arrow = gui.CollapseArrow{
            width = 10,
            height = 10,
            valign = "center",
            hmargin = 4,
        }
        arrow:SetClass("collapseSet", not expanded)

        local header = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "center",
            vmargin = 2,
            press = function()
                if locked then return end
                local nowExpanded = not (m_expanded[group.bucket.id] == true)
                if nowExpanded then m_expanded[group.bucket.id] = true
                else m_expanded[group.bucket.id] = nil end
                body:SetClass("collapsed", not nowExpanded)
                arrow:SetClass("collapseSet", not nowExpanded)
            end,
            arrow,
            gui.Label{
                width = "auto",
                height = "auto",
                valign = "center",
                fontSize = 12,
                bold = true,
                color = "@fg",
                text = string.format("%s (%d)", FeatureGroupHeaderText(group), #group.items),
            },
        }

        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            header,
            body,
        }, #items
    end

    --Whether the curated index (or the With-Captain synthetic) matches a needle.
    --Used to decide whether a title-bar search should drive this section's
    --filter at all (it only responds to queries it actually contains).
    local function indexHasMatch(creature, index, needle)
        for _,e in ipairs(index.features) do
            if Search.MatchesText(e.searchText or e.name or "", needle) then return true end
        end
        if creature.withCaptain and creature.minion then
            if Search.MatchesText("With Captain", needle)
                or Search.MatchesText(creature.withCaptain or "", needle) then return true end
        end
        return false
    end

    --Keep the filter input + its inline clear (X) in sync with m_filter. Setting
    --the input's text programmatically does NOT fire its change event, so the
    --title-bar-driven path can populate it safely. The search-driven update is
    --DEBOUNCED (see onGlobalQuery) so the term only appears once typing settles,
    --rather than mirroring the global box keystroke-by-keystroke.
    local function syncFilterInput()
        if filterInput ~= nil then filterInput.text = m_filter end
        if clearButton ~= nil then clearButton:SetClass("collapsed", m_filter == "") end
    end

    --Rebuild the groups container + count from the curated index. Collapses the
    --whole section when there is nothing to show. The Filter box drives all
    --filtering; the title-bar search populates that box (see onGlobalQuery).
    local function rebuild()
        if section == nil then return end
        local token = m_token
        if token == nil or not token.valid or token.properties == nil then
            section:SetClass("collapsed", true)
            return
        end
        local creature = token.properties
        local index = FeatureCategoriser.BuildTacIndex(creature)

        local filtering = m_filter ~= ""
        local needle = Search.Normalize(m_filter)

        local children = {}
        local shown = 0

        --Minion "With Captain": preserved as a standalone chip (it is not a
        --characterFeatures entry, so the categoriser never sees it).
        if creature.withCaptain and creature.minion then
            local captainText = creature.withCaptain
            if not filtering or Search.MatchesText("With Captain", needle)
                or Search.MatchesText(captainText or "", needle) then
                children[#children+1] = gui.Panel{
                    classes = {"panel", "cond-chips"},
                    wrap = true,
                    lmargin = 6,
                    TacPanel.FeatureChip(token, "With Captain", function() return captainText end),
                }
                shown = shown + 1
            end
        end

        for _,bid in ipairs(index.order) do
            local groupPanel, n = buildGroup(token, index.groups[bid], filtering, needle)
            if groupPanel ~= nil then
                children[#children+1] = groupPanel
                shown = shown + n
            end
        end

        if #children == 0 then
            if filtering then
                countLabel.text = string.format("No matches in %d features", index.total)
                countLabel:SetClass("collapsed", false)
                groupsContainer.children = {}
                section:SetClass("collapsed", false)
                return
            end
            section:SetClass("collapsed", true)
            return
        end

        section:SetClass("collapsed", false)
        groupsContainer.children = children
        if filtering then
            countLabel.text = string.format("Showing %d of %d features", shown, index.total)
        else
            countLabel.text = string.format("%d features", index.total)
        end
        countLabel:SetClass("collapsed", false)
    end

    --Set the filter (used by the title-bar search path). When it populates the
    --filter, ensure the section is open so the filtered result is visible even
    --if the user had it collapsed -- otherwise the filtering would be silent.
    local function setFilter(text, fromGlobal)
        m_filter = text or ""
        m_filterFromGlobal = fromGlobal == true
        syncFilterInput()
        rebuild()
        if m_filter ~= "" and section ~= nil and section.data ~= nil and section.data.collapsed then
            section.data.collapsed = false
            section:FireEventTree("setCollapse", false)
        end
    end

    --Apply a title-bar query to this section's filter. When the query matches
    --curated content on the selected token, the Filter box is driven with it (so
    --the filtered list shows the term + the clear X), making it obvious the list
    --is not the whole set. A query that matches nothing here is ignored (a
    --user-typed local filter is never clobbered), except that clearing/refining
    --the search clears a filter the search itself set. Below the minimum length
    --the query is treated as no-match so a stray letter never filters.
    local FILTER_MIN_QUERY = 2
    local function applyGlobalQuery(text)
        if section == nil or not section.valid then return end
        local q = Search.Normalize(text or "")
        local token = m_token
        local matches = false
        if #q >= FILTER_MIN_QUERY and token ~= nil and token.valid and token.properties ~= nil then
            local index = FeatureCategoriser.BuildTacIndex(token.properties)
            matches = indexHasMatch(token.properties, index, q)
        end
        if matches then
            if (m_filter == "" or m_filterFromGlobal) and (text or "") ~= m_filter then
                setFilter(text, true)
            end
        elseif m_filterFromGlobal then
            setFilter("", false)
        end
    end

    --Subscribe to the live title-bar search, DEBOUNCED: a query only drives the
    --filter once typing pauses (the user asked it to wait for a more complete
    --query rather than react to every keystroke). A generation token cancels a
    --superseded query so only the latest settles.
    local m_querySeq = 0
    local function onGlobalQuery(text)
        if section == nil or not section.valid then
            Search.UnregisterQueryListener(section)
            return
        end
        m_querySeq = m_querySeq + 1
        local seq = m_querySeq
        dmhub.Schedule(0.4, function()
            if mod.unloaded or seq ~= m_querySeq then return end
            applyGlobalQuery(text)
        end)
    end

    --Inset the filter row symmetrically (the same gap each side) so the box
    --reads as centred in the panel; the right gap also clears the dock scrollbar.
    local FILTER_INSET = 14

    --Inline clear (X) button INSIDE the filter input: a floating close icon at
    --the input's right edge, shown only when there is text. Same close-icon
    --treatment the character-sheet Features tab uses; passed as a CONSTRUCTOR
    --child (a floating child added after the fact did not render on a bare
    --gui.Input -- the input needs a children container at build time).
    clearButton = gui.Panel{
        floating = true,
        bgimage = "ui-icons/close.png",
        --An inline bgcolor of "@fgMuted" is NOT resolved by the theme engine
        --(only style-rule values are), so the white icon would paint untinted
        --and read as invisible. Resolve the token to a concrete colour here.
        bgcolor = ThemeEngine.ResolveTokens("@fgMuted"),
        width = 14,
        height = 14,
        halign = "right",
        valign = "center",
        x = -4,
        classes = {"collapsed"},
        press = function()
            m_filter = ""
            m_filterFromGlobal = false
            if filterInput ~= nil then filterInput.text = "" end
            clearButton:SetClass("collapsed", true)
            rebuild()
        end,
    }

    filterInput = gui.Input{
        classes = {"input"},
        width = "100%",
        height = 22,
        halign = "left",
        valign = "center",
        borderBox = true,   -- include the input's own padding so 100% does not overflow the row
        fontSize = 12,
        placeholderText = "Filter features...",
        placeholderAlpha = 0.6,
        text = "",
        editlag = 0.1,
        change = function(element)
            m_filter = element.text or ""
            m_filterFromGlobal = false   -- the user is driving the filter now
            clearButton:SetClass("collapsed", m_filter == "")
            rebuild()
        end,
        clearButton,
    }

    countLabel = gui.Label{
        classes = {"label", "collapsed"},
        width = "auto",
        height = "auto",
        halign = "left",
        lmargin = FILTER_INSET,
        tmargin = 2,
        fontSize = 11,
        color = "@fgMuted",
        text = "",
    }

    groupsContainer = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    section = TacPanel.CollapsiblePanel{
        sectionId = "features",
        classes = {"collapsed"},
        altBg = false,
        title = "FEATURES",
        data = { token = nil },

        create = function(element)
            --Let the live title-bar search drive this section's filter. Keyed by
            --this element so multiple open Features sections coexist; released on
            --destroy.
            Search.RegisterQueryListener(element, onGlobalQuery)
        end,
        destroy = function(element)
            Search.UnregisterQueryListener(element)
        end,

        refreshCharacter = function(element, token)
            m_token = token
            rebuild()
            --Re-evaluate any active title-bar search against the new creature so
            --a search-driven filter follows token switches (immediate, not
            --debounced -- a switch is not typing).
            applyGlobalQuery(Search.GetGlobalQuery())
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        gui.Panel{
            --Centred with an equal gap each side (the right gap clears the dock
            --scrollbar the input used to run underneath).
            width = "100%-" .. tostring(FILTER_INSET * 2),
            height = "auto",
            halign = "center",
            flow = "horizontal",
            valign = "center",
            tmargin = 2,
            borderBox = true,
            filterInput,
        },
        countLabel,
        groupsContainer,
    }

    return section
end

--- Display the Notes panel
--- @return Panel
function TacPanel.Notes()
    return TacPanel.CollapsiblePanel{
        sectionId = "notes",
        classes = {"collapsed"},
        altBg = false,
        title = "NOTES",
        data = { token = nil },

        refreshCharacter = function(element, token)
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end

            element.data.token = token
            local creature = token.properties
            local notes = creature:try_get("notes")
            if notes == nil or #notes == 0 then
                element:SetClass("collapsed", true)
                return
            end

            -- Check if any note has text
            local hasContent = false
            for _, note in ipairs(notes) do
                if note.text ~= nil and note.text ~= "" then
                    hasContent = true
                    break
                end
            end
            if not hasContent then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)

            -- Rebuild note entries (collapsible) into the content container
            local charid = token.charid
            local specs = {}
            for _, note in ipairs(notes) do
                if note.text ~= nil and note.text ~= "" then
                    specs[#specs+1] = {
                        entryKey = "notes",
                        entryId  = note.title,
                        charid   = charid,
                        title    = note.title,
                        body     = note.text,
                    }
                end
            end
            element:FireEventTree("setEntries", specs)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        TacPanel.CollapsibleEntryContainer(),
    }
end

--- Display the Perks panel (heroes only)
--- @return Panel
function TacPanel.Perks()
    return TacPanel.CollapsiblePanel{
        sectionId = "perks",
        classes = {"collapsed"},
        altBg = false,
        title = "PERKS",
        data = { token = nil },

        refreshCharacter = function(element, token)
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end

            element.data.token = token
            local creature = token.properties
            if not creature:IsHero() then
                element:SetClass("collapsed", true)
                return
            end

            local charid = token.charid
            local specs = {}
            local seen = {}
            local levelChoices = creature:GetLevelChoices() or {}
            local featTable = dmhub.GetTableVisible(CharacterFeat.tableName)
            for _,choices in pairs(levelChoices) do
                for _,guid in ipairs(choices) do
                    if not seen[guid] then
                        seen[guid] = true
                        local featItem = featTable[guid]
                        if featItem then
                            specs[#specs+1] = {
                                entryKey = "perks",
                                entryId  = guid,
                                charid   = charid,
                                title    = featItem.name,
                                body     = featItem.description,
                            }
                        end
                    end
                end
            end

            if #specs == 0 then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)
            element:FireEventTree("setEntries", specs)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        TacPanel.CollapsibleEntryContainer(),
    }
end

--- Multi-token selection panel
--- @return Panel
function TacPanel.MultiEdit()
    local m_tokens = {}
    local m_selectedSquadId = nil

    -- Squad name input
    local monsterSquadInput = gui.Input{
        classes = {"me-input"},
        placeholderText = "Enter name...",
        characterLimit = 24,
        selectAllOnFocus = true,
        width = 140,
        height = "auto",
        valign = "center",
        change = function(element)
            local squadid = trim(element.text)
            if squadid ~= "" then
                for _,tok in ipairs(m_tokens) do
                    tok:ModifyProperties{
                        description = "Set Squad",
                        execute = function()
                            tok.properties.minionSquad = squadid
                        end,
                    }
                end
            end
        end,
    }

    -- Squad color picker
    local monsterSquadColorPicker = gui.ColorPicker{
        width = 20,
        height = 20,
        cornerRadius = 10,
        halign = "center",
        valign = "center",
        color = "white",
        confirm = function(element)
            local color = element.value.tostring
            for _,tok in ipairs(m_tokens) do
                tok:ModifyProperties{
                    description = "Set Color",
                    execute = function()
                        DrawSteelMinion.SetSquadColor(m_selectedSquadId, color)
                    end,
                }
            end

            local monsterTokens = dmhub.GetTokens{
                unaffiliated = true,
            }

            local squadTokens = {}
            for _,tok in ipairs(monsterTokens) do
                if tok.properties.minion and tok.properties:MinionSquad() == m_selectedSquadId then
                    squadTokens[#squadTokens+1] = tok.id
                end
            end

            if #squadTokens > 0 then
                game.Refresh{
                    tokens = squadTokens,
                }
            end
        end,
    }

    -- Add to Combat icon button
    local addToCombatBtn = gui.Panel{
        classes = {"me-icon-wrap", "collapsed"},
        tokens = function(element)
            local q = dmhub.initiativeQueue
            if q == nil or q.hidden then
                element:SetClass("collapsed", true)
                return
            end

            local hasNonCombatant = false
            for _,tok in ipairs(m_tokens) do
                if tok.properties:try_get("_tmp_initiativeStatus") == "NonCombatant" then
                    hasNonCombatant = true
                end
            end

            element:SetClass("collapsed", hasNonCombatant == false)
        end,
        gui.EnhIconButton{
            classes = {"toggle-btn", "combatTint"},
            bgimage = "panels/initiative/initiative-icon.png",
            width = TacPanelSizes.VisionBtn.size,
            height = TacPanelSizes.VisionBtn.size,
            press = function(element)
                Commands.rollinitiative()
            end,
            linger = function(element)
                gui.Tooltip("Add to Combat")(element)
            end,
        },
    }

    -- Group Initiative icon button
    local groupInitBtn = gui.Panel{
        classes = {"me-icon-wrap", "collapsed"},
        tokens = function(element)
            local initiativeid = false
            for _,tok in ipairs(m_tokens) do
                if tok.properties.initiativeGrouping == false or (initiativeid ~= false and tok.properties.initiativeGrouping ~= initiativeid) then
                    element:SetClass("collapsed", false)
                    return
                end
                initiativeid = tok.properties.initiativeGrouping
            end
            element:SetClass("collapsed", true)
        end,
        gui.Button{
            classes = {"toggle-btn"},
            icon = "icons/icon_app/icon_app_18.png",
            width = TacPanelSizes.VisionBtn.size,
            height = TacPanelSizes.VisionBtn.size,
            press = function(element)
                local guid = dmhub.GenerateGuid()

                local hasPlayers = false
                local existingInitiative = {}
                local info = gamehud.initiativeInterface

                for _,tok in ipairs(m_tokens) do
                    if tok.playerControlled then
                        hasPlayers = true
                    end
                end

                if hasPlayers then
                    guid = "PLAYERS-" .. guid
                end

                local tokens = DrawSteelMinion.GrowTokensToIncludeSquads(m_tokens)

                for _,tok in ipairs(tokens) do
                    local initiativeid = InitiativeQueue.GetInitiativeId(tok)
                    existingInitiative[initiativeid] = true
                    tok:ModifyProperties{
                        description = "Set Initiative",
                        execute = function()
                            tok.properties.initiativeGrouping = guid
                        end,
                    }
                end

                if info.initiativeQueue ~= nil and not info.initiativeQueue.hidden then
                    for initiativeid,_ in pairs(existingInitiative) do
                        info.initiativeQueue:RemoveInitiative(initiativeid)
                    end

                    info.initiativeQueue:SetInitiative(guid, 0, 0)
                    if hasPlayers then
                        local entry = info.initiativeQueue.entries[guid]
                        if entry ~= nil and entry:try_get("player") ~= true then
                            entry.player = true
                        end
                    end

                    info.UploadInitiative()
                end
            end,
            linger = function(element)
                gui.Tooltip("Group Initiative")(element)
            end,
        },
    }

    -- Ungroup Initiative icon button
    local ungroupInitBtn = gui.Panel{
        classes = {"me-icon-wrap", "collapsed"},
        tokens = function(element)
            local tokens = dmhub.allTokens
            local haveInitiativeGrouping = false

            for _,tok in ipairs(m_tokens) do
                if tok.properties.initiativeGrouping then
                    local squadsSeen = {}
                    local count = 0
                    for _,token in ipairs(tokens) do
                        if token.properties.initiativeGrouping == tok.properties.initiativeGrouping and (token.properties:MinionSquad() == nil or squadsSeen[token.properties:MinionSquad()] == nil) then
                            count = count+1
                            if token.properties:MinionSquad() ~= nil then
                                squadsSeen[token.properties:MinionSquad()] = true
                            end
                        end
                    end

                    if count > 1 then
                        haveInitiativeGrouping = true
                    end
                end
            end

            element:SetClass("collapsed", not haveInitiativeGrouping)
        end,
        gui.Button{
            classes = {"sizeM", "toggle-btn"},
            icon = "icons/icon_app/icon_app_13.png",
            width = TacPanelSizes.VisionBtn.size,
            height = TacPanelSizes.VisionBtn.size,
            press = function(element)
                local q = dmhub.initiativeQueue

                local needsInitiativeRefresh = false
                for _,tok in ipairs(m_tokens) do
                    tok:ModifyProperties{
                        description = "Set Initiative",
                        execute = function()
                            local haveInitiative = q ~= nil and (not q.hidden) and q:HasInitiative(InitiativeQueue.GetInitiativeId(tok))
                            tok.properties.initiativeGrouping = dmhub.GenerateGuid()
                            if haveInitiative then
                                needsInitiativeRefresh = true
                            end
                        end,
                    }
                end

                if needsInitiativeRefresh then
                    Commands.rollinitiative()
                end
            end,
            linger = function(element)
                gui.Tooltip("Ungroup Initiative")(element)
            end,
        },
    }

    -- Make Captain icon button
    local makeCaptainBtn = gui.Panel{
        classes = {"me-icon-wrap", "collapsed"},
        data = { mode = "Make Captain" },
        gui.Button{
            classes = {"toggle-btn"},
            icon = "panels/hud/crown.png",
            width = TacPanelSizes.VisionBtn.size,
            height = TacPanelSizes.VisionBtn.size,
            press = function(element)
                local outer = element.parent
                local isMakeCaptain = outer.data.mode == "Make Captain"
                local initiativeGrouping = nil
                local allTokens = dmhub.allTokens

                local charids = {}
                for _,tok in ipairs(m_tokens) do
                    charids[tok.charid] = true
                end
                local initiativeGroupingsSeen = {}

                for _,tok in ipairs(m_tokens) do
                    if tok.properties.initiativeGrouping and not initiativeGroupingsSeen[tok.properties.initiativeGrouping] then
                        local grouping = tok.properties.initiativeGrouping
                        local used = false
                        for _,otherTok in ipairs(allTokens) do
                            if otherTok.properties.initiativeGrouping == grouping and (not charids[otherTok.charid]) then
                                used = true
                                break
                            end
                        end

                        if not used then
                            initiativeGrouping = grouping
                            break
                        end
                    end
                end

                if initiativeGrouping == false or not isMakeCaptain then
                    initiativeGrouping = dmhub.GenerateGuid()
                end

                local groupid = dmhub.GenerateGuid()
                local captainid = nil
                for _,tok in ipairs(m_tokens) do
                    if (not tok.properties.minion) then
                        captainid = tok.id
                        tok:ModifyProperties{
                            groupid = groupid,
                            description = "Set Squad",
                            execute = function()
                                tok.properties.initiativeGrouping = initiativeGrouping
                                if isMakeCaptain then
                                    tok.properties.minionSquad = m_selectedSquadId
                                else
                                    tok.properties.minionSquad = nil
                                end
                            end,
                        }
                    elseif tok.properties.initiativeGrouping ~= initiativeGrouping and isMakeCaptain then
                        tok:ModifyProperties{
                            groupid = groupid,
                            description = "Set Squad",
                            execute = function()
                                tok.properties.initiativeGrouping = initiativeGrouping
                            end,
                        }
                    end
                end

                if captainid ~= nil then
                    local monsterTokens = dmhub.GetTokens{}
                    for _,tok in ipairs(monsterTokens) do
                        if tok.id ~= captainid and (not tok.properties.minion) and tok.properties:MinionSquad() == m_selectedSquadId then
                            tok:ModifyProperties{
                                description = "Set Squad",
                                execute = function()
                                    tok.properties.minionSquad = nil
                                end,
                            }
                        end
                    end
                end
            end,
            linger = function(element)
                gui.Tooltip(element.parent.data.mode)(element)
            end,
        },
    }

    -- Form Squad icon button
    local formSquadBtn = gui.Panel{
        classes = {"me-icon-wrap", "collapsed"},
        gui.Button{
            classes = {"toggle-btn"},
            icon = "icons/icon_app/icon_app_2.png",
            width = TacPanelSizes.VisionBtn.size,
            height = TacPanelSizes.VisionBtn.size,
            press = function(element)
                DrawSteelMinion.FormSquad(dmhub.selectedOrPrimaryTokens)
            end,
            linger = function(element)
                gui.Tooltip("Form Squad")(element)
            end,
        },
    }

    -- Monster squad row
    local monsterSquadPanel = gui.Panel{
        classes = {"me-squad-row", "collapsed"},
        tokens = function(element, tokens)
            local nminions = 0
            local monsterType = nil
            local squadid = nil
            local minionParty = nil
            local potentialCaptain = nil
            for _,tok in ipairs(tokens) do
                if (not tok.properties.minion) then
                    potentialCaptain = tok
                end
                if tok.properties.minion and tok.properties:has_key("monster_type") and (monsterType == nil or tok.properties.monster_type == monsterType) then
                    nminions = nminions + 1
                    monsterType = tok.properties.monster_type
                    if squadid == nil then
                        squadid = tok.properties:MinionSquad()
                    elseif squadid ~= tok.properties:MinionSquad() then
                        squadid = false
                    end

                    if minionParty == nil then
                        minionParty = tok.ownerId
                    elseif minionParty ~= tok.ownerId then
                        minionParty = false
                    end
                end
            end

            local showCaptainButton = false

            if nminions == #tokens-1 and potentialCaptain ~= nil and potentialCaptain.ownerId == minionParty then
                showCaptainButton = true
                if squadid ~= false and squadid ~= nil and potentialCaptain.properties:MinionSquad() == squadid then
                    nminions = nminions + 1
                    makeCaptainBtn.data.mode = "Remove Captain"
                else
                    makeCaptainBtn.data.mode = "Make Captain"
                    m_selectedSquadId = squadid
                end
            end

            makeCaptainBtn:SetClass("collapsed", not showCaptainButton)

            local shouldCollapse = nminions < #tokens
            local haveFormSquad = false

            if nminions == #tokens and squadid ~= nil then
                if squadid == false then
                    haveFormSquad = true
                    shouldCollapse = true
                else
                    monsterSquadInput.text = squadid
                    monsterSquadColorPicker:SetClass("hidden", false)
                    monsterSquadColorPicker.value = DrawSteelMinion.GetSquadColor(squadid)
                    m_selectedSquadId = squadid
                end
            end

            element:SetClass("collapsed", shouldCollapse)
            formSquadBtn:SetClass("collapsed", not haveFormSquad)
        end,
        monsterSquadColorPicker,
        gui.Label{
            classes = {"me-squad-label"},
            text = "Squad:",
            lmargin = 8,
        },
        monsterSquadInput,
    }

    -- EV result chip
    local monsterEVChip = gui.Panel{
        classes = {"me-ev-chip", "collapsed"},
        gui.Label{
            classes = {"me-ev-result"},
            text = "",
            markdown = true,

            multimonitor = {"eds"},
            monitor = function(element)
                print("EDS:: MONITOR")
                if m_tokens ~= nil then
                    element:FireEvent("tokens", m_tokens)
                end
            end,

            tokens = function(element, tokens)
                local monsterTokens = {}
                for _,tok in ipairs(tokens) do
                    if tok.properties:IsMonster() then
                        monsterTokens[#monsterTokens+1] = tok
                    end
                end

                if #monsterTokens == 0 then
                    element.text = ""
                    element.parent:SetClass("collapsed", true)
                    return
                end

                element.parent:SetClass("collapsed", false)

            local ev = 0
            for _,tok in ipairs(monsterTokens) do
                if tok.properties.minion then
                    ev = ev + tok.properties:EV()/GameSystem.minionsPerSquad
                else
                    ev = ev + tok.properties:EV()
                end
            end

            ev = round(ev)

            local edsDescription
            local eds = g_edsSetting:Get()

            if ev <= eds/2 then
                edsDescription = "<color=@success>Trivial</color>"
            elseif ev <= eds then
                local val = ev
                while val % 5 ~= 0 do
                    val = val + 1
                end

                if val - eds/2 >= eds - val then
                    edsDescription = "<color=@warning>Standard</color>"
                else
                    edsDescription = "<color=@success>Easy</color>"
                end
            elseif ev <= eds + 10 then
                edsDescription = "<color=@danger>Hard</color>"
            else
                edsDescription = "<color=@danger>Extreme</color>"
            end

            element.text = ThemeEngine.ResolveTokens(string.format("%d monsters selected, EV: %d (<b>%s</b>)", #monsterTokens, ev, edsDescription))
        end,
    },
    }

    return gui.Panel{
        styles = TacPanel.AllStyles(),
        classes = {"tacpanel", "alt-bg", "collapsed"},
        tokens = function(element, tokens)
            m_tokens = tokens
            if #tokens <= 1 then
                element:SetClass("collapsed", true)
            else
                element:SetClass("collapsed", false)
                for _,child in ipairs(element.children) do
                    child:FireEventTree("tokens", tokens)
                end
            end
        end,

        gui.Label{
            classes = {"panel-title"},
            text = "SELECTED TOKENS",
        },

        -- Row 1: Heal / Damage / Add Condition
        gui.Panel{
            classes = {"me-actions"},

            -- Heal All
            gui.Panel{
                classes = {"me-input-box", "heal"},
                gui.Input{
                    classes = {"me-input"},
                    placeholderText = "Heal All",
                    placeholderAlpha = 0.6,
                    change = function(element)
                        for _,tok in ipairs(m_tokens) do
                            tok:ModifyProperties{
                                description = "Heal",
                                execute = function()
                                    tok.properties:Heal(element.text)
                                end,
                            }
                        end
                        element.text = ""
                    end,
                },
            },

            -- Damage All
            gui.Panel{
                classes = {"me-input-box", "damage"},
                gui.Input{
                    classes = {"me-input"},
                    placeholderText = "Damage All",
                    placeholderAlpha = 0.6,
                    change = function(element)
                        for _,tok in ipairs(m_tokens) do
                            tok:ModifyProperties{
                                description = "Damage",
                                execute = function()
                                    tok.properties:TakeDamage(element.text)
                                end,
                            }
                        end
                        element.text = ""
                    end,
                },
            },

            -- Add Condition
            gui.Panel{
                classes = {"me-condition-btn"},
                press = function(element)
                    TacPanel.AddConditionMenu{
                        tokens = m_tokens,
                        button = element,
                    }
                end,
                gui.Label{
                    classes = {"me-condition-btn"},
                    text = "Add Condition",
                },
            },
        },

        -- Row 2: Icon buttons
        gui.Panel{
            classes = {"me-icon-row"},
            addToCombatBtn,
            groupInitBtn,
            ungroupInitBtn,
            makeCaptainBtn,
            formSquadBtn,
        },

        -- Squad row
        monsterSquadPanel,

        -- EDS + EV row
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            tmargin = 4,
            lmargin = 6,

            -- EDS chip
            gui.Panel{
                classes = {"me-eds-chip"},
                lmargin = 0,
                gui.Label{
                    classes = {"me-eds-label"},
                    text = "EDS:",
                },
                gui.Label{
                    classes = {"me-eds-input"},
                    editable = true,
                    text = g_edsSetting:Get(),
                    characterLimit = 3,
                    multimonitor = "eds",
                    monitor = function(element)
                        element.text = tostring(g_edsSetting:Get())
                    end,
                    change = function(element)
                        local n = tonumber(element.text)
                        if n == nil or n < 10 or n > 1000 then
                            element.text = tostring(g_edsSetting:Get())
                            return
                        end
                        g_edsSetting:Set(n)
                    end,
                },
            },

            -- EV result
            monsterEVChip,
        },
    }
end

--- Format a condition's duration for display
--- @param duration string raw duration value
--- @return string formatted duration text
function TacPanel.FormatConditionDuration(duration)
    if duration == "eot" then return "EoT"
    elseif duration == "eoe" then return "EoE"
    elseif duration == "save" then return "Save"
    elseif type(duration) == "string" then return string.upper(duration) .. " ends"
    else return "EoT"
    end
end

--- Build the display text for a condition chip
--- @param condid string condition id
--- @param cond table inflicted condition entry
--- @param creature table token.properties
--- @return string chip label text
function TacPanel.ConditionChipText(condid, cond, creature)
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
    local info = conditionsTable[condid]
    if info == nil then return "???" end

    local text = info.name

    -- Append rider names
    local riderids = creature:GetConditionRiders(condid)
    if riderids ~= nil then
        local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)
        for _, riderid in ipairs(riderids) do
            if ridersTable[riderid] then
                text = string.format("%s %s", text, ridersTable[riderid].name)
            end
        end
    end

    -- Append duration
    if not info.indefiniteDuration then
        text = string.format("%s (%s)", text, TacPanel.FormatConditionDuration(cond.duration))
    end

    return text
end

--- Build a tooltip for a condition chip (matches old code tooltip format)
--- @param condid string condition id
--- @param cond table inflicted condition entry
--- @param creature table token.properties
--- @return string tooltip markup
function TacPanel.ConditionTooltipText(condid, cond, creature)
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
    local info = conditionsTable[condid]
    if info == nil then return "" end

    local durationText = ""
    if not info.indefiniteDuration then
        durationText = string.format(" (%s)", TacPanel.FormatConditionDuration(cond.duration))
    end

    local ridersText = ""
    local riderids = creature:GetConditionRiders(condid)
    if riderids ~= nil then
        local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)
        for _, riderid in ipairs(riderids) do
            local riderInfo = ridersTable[riderid]
            if riderInfo ~= nil then
                ridersText = string.format("%s\n\n<b>%s</b>: %s", ridersText, riderInfo.name, riderInfo.description)
            end
        end
    end

    return string.format('<b>%s</b>%s: %s%s\n\n%s',
        info.name, durationText, info.description, ridersText, cond.sourceDescription or "")
end

--- Shared helper for condition/effect chip panels.
--- @param args table {token, tooltipText, label, removeDescription, onRemove, icon?, lingerExtra?, extraChildren?}
--- @return Panel
function TacPanel.EffectChip(args)
    local children = {}

    if args.icon then
        children[#children+1] = gui.Panel{
            classes = {"panel", "cond-icon"},
            bgimage = args.icon.bgimage,
            bgcolor = args.icon.bgcolor or "white",
            hueshift = args.icon.hueshift or 0,
        }
    end

    children[#children+1] = gui.Label{
        classes = {"label", "cond-name"},
        text = args.label,
        editable = args.onEdit ~= nil,
        characterLimit = args.onEdit and 60 or nil,
        textWrap = args.onEdit and false or nil,
        change = args.onEdit and function(element)
            args.onEdit(element, args.token)
        end or nil,
    }

    if args.extraChildren then
        for _,child in ipairs(args.extraChildren) do
            children[#children+1] = child
        end
    end

    if args.onRemove then
        children[#children+1] = gui.Panel{
            classes = {"panel", "cond-remove"},
            press = function(element)
                args.token:ModifyProperties{
                    description = args.removeDescription,
                    execute = function()
                        args.onRemove(args.token)
                    end,
                }
            end,
            linger = function(element)
                gui.Tooltip("Remove")(element)
            end,
            gui.Label{
                classes = {"label", "cond-remove"},
                text = "X",
            },
        }
    end

    local panelArgs = {
        classes = {"panel", "cond-chip"},
        data = { targetingMarkers = {} },
        linger = function(element)
            element:FireEvent("clearMarkers")
            element.popupPositioning = "panel"
            element.tooltip = gui.TooltipFrame(
                TacPanel.Tooltip(args.tooltipText),
                { halign = "left", valign = "top" }
            )
            if args.lingerExtra then
                args.lingerExtra(element)
            end
        end,
        dehover = function(element)
            element:FireEvent("clearMarkers")
        end,
        clearMarkers = function(element)
            for _, marker in ipairs(element.data.targetingMarkers) do
                marker:Destroy()
            end
            element.data.targetingMarkers = {}
        end,
        children = children,
    }

    return gui.Panel(panelArgs)
end

--- Create a single condition chip panel
--- @param condid string condition id
--- @param cond table inflicted condition entry
--- @param token CharacterToken
--- @return Panel
function TacPanel.ConditionChip(condid, cond, token)
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
    local info = conditionsTable[condid]
    local iconid = info and info.iconid or ""
    local display = info and info.display or {}
    local showSetCaster = info ~= nil and info.trackCaster and cond.casterInfo == nil

    return TacPanel.EffectChip{
        token = token,
        tooltipText = TacPanel.ConditionTooltipText(condid, cond, token.properties),
        label = TacPanel.ConditionChipText(condid, cond, token.properties),
        icon = { bgimage = iconid, bgcolor = display.bgcolor, hueshift = display.hueshift },
        removeDescription = "Remove Condition",
        onRemove = function(tok)
            tok.properties:InflictCondition(condid, {purge = true})
        end,
        lingerExtra = function(element)
            local creature = token.properties
            local conditions = creature:try_get("inflictedConditions", {})
            local c = conditions[condid]
            if c == nil then return end
            local caster = c.casterInfo
            if caster ~= nil and type(caster.tokenid) == "string" then
                local casterToken = dmhub.GetTokenById(caster.tokenid)
                if casterToken ~= nil then
                    element.data.targetingMarkers[#element.data.targetingMarkers+1] =
                        dmhub.HighlightLine{color = "red", a = casterToken.pos, b = token.pos}
                end
            end
        end,
        extraChildren = {
            gui.Button{
                classes = {"sizeXxs", "cond-setCaster", showSetCaster and "" or "collapsed"},
                icon = "icons/icon_app/icon_app_4.png",
                press = function(element)
                    if element.data.invoking or gamehud.actionBarPanel.data.IsCastingSpell() then return end
                    element.data.invoking = true
                    element.thinkTime = 0.1
                    local ability = DeepCopy(MCDMUtils.GetStandardAbility("SetConditionCaster"))
                    ability.behaviors[1].condid = condid
                    ability.OnFinishCast = function()
                        element.data.invoking = false
                        element.thinkTime = nil
                    end
                    ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(token, ability, token, "prompt", {}, {})
                end,
                think = function(element)
                    if element.data.invoking and element.data.invokeReady then
                        if not gamehud.actionBarPanel.data.IsCastingSpell() and not gamehud.rollDialog.data.IsShown() then
                            element.data.invoking = false
                            element.data.invokeReady = false
                            element.thinkTime = nil
                        end
                    elseif element.data.invoking then
                        element.data.invokeReady = true
                    end
                end,
                linger = function(element)
                    gui.Tooltip("Set Caster")(element)
                end,
            },
        },
    }
end

--- Build the display text for a status effect chip
--- @param entry CharacterOngoingEffectInstance
--- @param info CharacterOngoingEffect definition
--- @return string chip label text
function TacPanel.StatusEffectChipText(entry, info)
    local text = info.name
    if entry.stacks ~= nil and entry.stacks > 1 then
        text = string.format("%s x%d", text, entry.stacks)
    end
    local timeText = entry:DescribeTimeRemaining()
    if timeText ~= nil and timeText ~= "" then
        text = string.format("%s (%s)", text, timeText)
    end
    return text
end

--- Build a tooltip for a status effect chip
--- @param entry CharacterOngoingEffectInstance
--- @param info CharacterOngoingEffect definition
--- @param creature table token.properties
--- @return string tooltip markup
function TacPanel.StatusEffectTooltipText(entry, info, creature)
    local stacksText = ""
    if info.stackable and entry.stacks ~= nil and entry.stacks > 1 then
        stacksText = string.format(" (%d stacks)", entry.stacks)
    end
    local casterText = ""
    local caster = entry:DescribeCaster()
    if caster ~= nil then
        casterText = string.format("\nInflicted by %s", caster)
    end
    local timeText = entry:DescribeTimeRemaining()
    if timeText ~= nil and timeText ~= "" then
        timeText = "\n" .. timeText
    else
        timeText = ""
    end
    return string.format('<b>%s</b>%s: %s%s%s',
        info.name, stacksText,
        StringInterpolateGoblinScript(info.description, creature),
        casterText, timeText)
end

--- Create a single status effect chip panel
--- @param entry CharacterOngoingEffectInstance
--- @param info CharacterOngoingEffect definition
--- @param token CharacterToken
--- @return Panel
function TacPanel.StatusEffectChip(entry, info, token)
    local iconid = info:GetDisplayIcon()
    local display = info:GetDisplayDisplay() or {}

    return TacPanel.EffectChip{
        token = token,
        tooltipText = TacPanel.StatusEffectTooltipText(entry, info, token.properties),
        label = TacPanel.StatusEffectChipText(entry, info),
        icon = { bgimage = iconid, bgcolor = display.bgcolor, hueshift = display.hueshift },
        removeDescription = "Remove Status Effect",
        onRemove = function(tok)
            tok.properties:RemoveOngoingEffect(entry.ongoingEffectid)
        end,
        lingerExtra = function(element)
            if entry.bondid then
                local tokens = creature.GetTokensWithBoundOngoingEffect(entry.bondid)
                for i, _ in ipairs(tokens) do
                    for j = i + 1, #tokens do
                        element.data.targetingMarkers[#element.data.targetingMarkers+1] =
                            dmhub.HighlightLine{color = "red", a = tokens[i].pos, b = tokens[j].pos}
                    end
                end
            end
        end,
    }
end

--- Create a single custom condition chip panel (text only, no icon)
--- @param key string GUID key in customConditions
--- @param entry table {text, timestamp}
--- @param token CharacterToken
--- @return Panel
function TacPanel.CustomConditionChip(key, entry, token)
    return TacPanel.EffectChip{
        token = token,
        tooltipText = entry.text,
        label = entry.text,
        removeDescription = "Remove Custom Condition",
        onRemove = function(tok)
            local cc = tok.properties:get_or_add("customConditions", {})
            cc[key] = nil
        end,
        onEdit = function(element, tok)
            local newText = trim(element.text)
            tok:ModifyProperties{
                description = "Change Custom Condition",
                execute = function()
                    local cc = tok.properties:get_or_add("customConditions", {})
                    cc[key] = nil
                    if newText ~= "" then
                        local newKey = dmhub.GenerateGuid()
                        local newEntry = DeepCopy(entry)
                        newEntry.text = newText
                        cc[newKey] = newEntry
                    end
                end,
            }
        end,
    }
end

--- Create a single aura chip panel (no remove button)
--- @param auraInstance table the aura instance from GetAurasAffecting
--- @param token CharacterToken
--- @return Panel
function TacPanel.AuraChip(auraInstance, token)
    local aura = auraInstance.aura
    local display = aura.display or {}
    return TacPanel.EffectChip{
        token = token,
        tooltipText = string.format('<b>%s</b>: %s', aura.name, aura:GetDescription()),
        label = string.format("%s (Aura)", aura.name),
        icon = { bgimage = aura.iconid, bgcolor = display.bgcolor, hueshift = display.hueshift },
        lingerExtra = function(element)
            local area = auraInstance:GetArea()
            if area ~= nil then
                local marks = area:Mark{ color = "white", video = "divinationline.webm" }
                element.data.targetingMarkers[#element.data.targetingMarkers+1] = marks
            end
        end,
    }
end

--- Append a chip for each aura the creature emits/controls to `chips`.
--- @param token CharacterToken
--- @param chips Panel[] Appended in place
local function FillAurasEmittingPanels(token, chips)
    if token == nil or not token.valid or token.properties == nil then
        return
    end

    local creature = token.properties

    --Shwayguy, switch to using get aura's to include all aura's the creature controls
    local storedGuids = {}
    for _, a in ipairs(creature:try_get("auras", {})) do
        storedGuids[a.guid] = true
    end

    local auras = creature:GetAuras()
    for _, auraInstance in ipairs(auras) do
        local aura = auraInstance.aura
        local display = aura.display or {}
        local auraid = auraInstance.guid
        local iconid = aura.iconid or ""
        local iconbg = display.bgcolor or "white"
        local iconhue = display.hueshift or 0
        local removable = storedGuids[auraid] == true

        local chipChildren = {}
        if iconid ~= "" then
            chipChildren[#chipChildren+1] = gui.Panel{
                classes = {"panel", "cond-icon"},
                bgimage = iconid,
                bgcolor = iconbg,
                hueshift = iconhue,
            }
        end
        chipChildren[#chipChildren+1] = gui.Label{
            classes = {"label", "cond-name"},
            text = aura.name,
        }
        chipChildren[#chipChildren+1] = gui.Panel{
            valign = "center",
            halign = "right",
            width = "auto",
            height = "auto",
            bgimage = true,
            bgcolor = "clear",
            pad = 3,
            lmargin = 4,
            gui.VisibilityPanel{
                classes = {"visDot"},
                opacity = 1,
                visible = not token.properties:GetAuraDisplaySetting(aura.name).hide,
                width = 12,
                height = 12,
                press = function(element)
                    local settings = DeepCopy(token.properties:GetAuraDisplaySetting(aura.name))
                    settings.hide = not settings.hide
                    token:ModifyProperties{
                        description = tr("Set Aura Display Settings"),
                        undoable = false,
                        execute = function()
                            token.properties:SetAuraDisplaySetting(aura.name, settings)
                        end,
                    }
                end,
                refresh = function(element)
                    if token == nil or not token.valid then return end
                    element:FireEvent("visible", not token.properties:GetAuraDisplaySetting(aura.name).hide)
                end,
            },
        }

        if removable then
            -- Stored aura: color lives on the AuraInstance.display table
            -- and is persisted through ModifyProperties on creature.auras.
            chipChildren[#chipChildren+1] = gui.ColorPicker{
                classes = {"bordered"},
                valign = "center",
                halign = "right",
                hmargin = 6,
                width = 20,
                height = 20,
                hasAlpha = true,
                value = ((auraInstance:try_get("display") or {}).bgcolor) or "#ffffffff",
                change = function(element)
                    -- Live preview: mutate the in-memory display and refresh the
                    -- aura visual without going through ModifyProperties.
                    local liveDisplay = auraInstance:try_get("display")
                    if liveDisplay == nil then
                        return
                    end
                    liveDisplay.bgcolor = element.value.tostring
                    token:UpdateAuras()
                end,
                confirm = function(element)
                    local liveDisplay = auraInstance:try_get("display")
                    if liveDisplay ~= nil then
                        --make sure that when we do modify properties this gets picked up as a change.
                        liveDisplay.bgcolor = "none"
                    end

                    local newColor = element.value.tostring
                    token:ModifyProperties{
                        description = tr("Set Aura Color"),
                        undoable = false,
                        execute = function()
                            local settings = auraInstance:get_or_add("display", {
                                hueshift = 0, saturation = 1, brightness = 1, bgcolor = "#ffffffff",
                            })
                            settings.bgcolor = newColor
                        end,
                    }
                    token:UpdateAuras()
                end,
            }
            chipChildren[#chipChildren+1] = gui.Panel{
                classes = {"panel", "cond-remove"},
                press = function(element)
                    token:ModifyProperties{
                        description = "Remove Aura",
                        execute = function()
                            token.properties:RemoveAura(auraid)
                        end,
                    }
                end,
                linger = function(element)
                    gui.Tooltip("End Aura")(element)
                end,
                gui.Label{
                    classes = {"label", "cond-remove"},
                    text = "X",
                },
            }
        else
            -- Generated aura (creature feature, ongoing effect, etc.): the
            -- AuraInstance is rebuilt from its modifier each frame, so any
            -- color set on AuraInstance.display would be discarded. Persist
            -- the per-token override in auraDisplaySettings keyed by aura
            -- name (same persistent table the visibility toggle uses).
            local capturedAuraName = aura.name
            chipChildren[#chipChildren+1] = gui.ColorPicker{
                classes = {"bordered"},
                valign = "center",
                halign = "right",
                hmargin = 6,
                width = 20,
                height = 20,
                hasAlpha = true,
                value = token.properties:GetAuraDisplaySetting(capturedAuraName).bgcolor
                    or (token.playerControlled and token.playerColor.tostring or "#AA0000"),
                change = function(element)
                    local settings = DeepCopy(token.properties:GetAuraDisplaySetting(capturedAuraName))
                    settings.bgcolor = element.value.tostring
                    token.properties:SetAuraDisplaySetting(capturedAuraName, settings)
                    token:UpdateAuras()
                end,
                confirm = function(element)
                    -- Snapshot the final state (including preview
                    -- mutations), then clear the live setting and re-apply
                    -- inside ModifyProperties so the upload sees a real
                    -- diff.
                    local preserved = DeepCopy(token.properties:GetAuraDisplaySetting(capturedAuraName))
                    preserved.bgcolor = element.value.tostring
                    token.properties:SetAuraDisplaySetting(capturedAuraName, nil)
                    token:ModifyProperties{
                        description = tr("Set Aura Color"),
                        undoable = false,
                        execute = function()
                            token.properties:SetAuraDisplaySetting(capturedAuraName, preserved)
                        end,
                    }
                    token:UpdateAuras()
                end,
            }
        end

        local chipArgs = {
            classes = {"panel", "cond-chip"},
            data = { targetingMarkers = {} },
            popupPositioning = "panel",
            linger = function(el)
                el:FireEvent("clearMarkers")
                el.tooltip = gui.TooltipFrame(
                    TacPanel.Tooltip(string.format('<b>%s</b>: %s', aura.name, aura:GetDescription())),
                    { halign = "left", valign = "top" }
                )
                local area = auraInstance:GetArea()
                if area ~= nil then
                    local marks = area:Mark{ color = "white", video = "divinationline.webm" }
                    el.data.targetingMarkers[#el.data.targetingMarkers+1] = marks
                end
            end,
            dehover = function(el)
                el:FireEvent("clearMarkers")
            end,
            clearMarkers = function(el)
                for _, m in ipairs(el.data.targetingMarkers) do m:Destroy() end
                el.data.targetingMarkers = {}
            end,
        }
        for i, child in ipairs(chipChildren) do
            chipArgs[i] = child
        end
        chips[#chips+1] = gui.Panel(chipArgs)
    end
end

--- Open the "Add Condition" pop-up (conditions, status effects, a custom
--- condition input, and custom auras) on args.button, applied to args.tokens.
--- @param args {tokens: CharacterToken[], button: Panel}
function TacPanel.AddConditionMenu(args)
    local m_tokens = args.tokens
    local m_button = args.button

    local options = {}
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}

    for k, effect in unhidden_pairs(conditionsTable) do
        if effect.showInMenus then
            local children = {}
            if effect.indefiniteDuration then
                local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)
                for riderid, rider in unhidden_pairs(ridersTable) do
                    if rider.condition == k and rider.showAsMenuOption then
                        children[#children + 1] = gui.Label{
                            halign = "right",
                            swallowPress = true,
                            classes = {"menu-suboption"},
                            text = rider.name,
                            press = function(element)
                                element.parent:FireEvent("press", "eoe", riderid)
                            end,
                        }
                    end
                end
            else
                children = {
                    gui.Label{
                        halign = "right",
                        swallowPress = true,
                        classes = {"menu-suboption"},
                        text = "EoT",
                        press = function(element)
                            element.parent:FireEvent("press", "eot")
                        end,
                    },
                    gui.Label{
                        halign = "right",
                        swallowPress = true,
                        classes = {"menu-suboption"},
                        text = "Save",
                        press = function(element)
                            element.parent:FireEvent("press", "save")
                        end,
                    },
                    gui.Label{
                        halign = "right",
                        swallowPress = true,
                        classes = {"menu-suboption"},
                        text = "EoE",
                        press = function(element)
                            element.parent:FireEvent("press", "eoe")
                        end,
                    },
                }
            end

            options[#options + 1] = gui.Label{
                classes = {"menu-option"},
                text = effect.name,
                flow = "horizontal",
                searchText = function(element, searchText)
                    local match = string.starts_with(string.lower(element.text), searchText)
                    element:SetClass("collapsed", not match)
                end,
                press = function(element, durationOverride, riderid)
                    if (not durationOverride) and effect.indefiniteDuration then
                        durationOverride = "eoe"
                    end
                    for _, tok in ipairs(m_tokens) do
                        tok:ModifyProperties{
                            description = "Apply Condition",
                            execute = function()
                                tok.properties:InflictCondition(k, {
                                    riders = {riderid},
                                    duration = (durationOverride or "eot"),
                                })
                            end,
                        }
                    end
                    m_button.popup = nil
                end,
                linger = function(element)
                    gui.Tooltip(string.format("%s: %s", effect.name, effect.description))(element)
                end,
                children = children,
            }
        end
    end

    table.sort(options, function(a, b) return a.text < b.text end)

    local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
    local statusEffectData = {}
    for k, effect in unhidden_pairs(ongoingEffectsTable) do
        if effect.statusEffect then
            statusEffectData[#statusEffectData + 1] = {key = k, effect = effect}
        end
    end
    table.sort(statusEffectData, function(a, b) return a.effect.name < b.effect.name end)

    local function makeStatusLabel(k, effect)
        if effect == nil or effect.name == nil or effect.name == "" then
            return nil
        end
        return gui.Label{
            classes = {"menu-option"},
            text = effect.name,
            searchText = function(el, searchText)
                el:SetClass("collapsed", not string.starts_with(string.lower(el.text), searchText))
            end,
            linger = function(el)
                gui.Tooltip(string.format("%s: %s", effect.name, effect.description))(el)
            end,
            press = function(el)
                for _, tok in ipairs(m_tokens) do
                    tok:ModifyProperties{
                        description = "Apply Status Effect",
                        combine = true,
                        execute = function()
                            if tok == nil or not tok.valid then return end
                            tok.properties:ApplyOngoingEffect(k)
                        end,
                    }
                end
                m_button.popup = nil
            end,
        }
    end

    local initialCount = math.min(5, #statusEffectData)
    local initialLabels = {}
    for i = 1, initialCount do
        local d = statusEffectData[i]
        initialLabels[i] = makeStatusLabel(d.key, d.effect)
    end

    local statusExpanded = false
    local statusContent = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    if #statusEffectData > initialCount then
        local moreButton = gui.Label{
            classes = {"menu-suboption"},
            text = "More...",
            halign = "left",
            tmargin = 4,
            lmargin = 8,
            swallowPress = true,
            press = function(element)
                statusExpanded = true
                local allLabels = {}
                for i = 1, #statusEffectData do
                    local d = statusEffectData[i]
                    allLabels[i] = makeStatusLabel(d.key, d.effect)
                end
                statusContent.children = allLabels
                element:SetClass("collapsed", true)
            end,
        }
        initialLabels[#initialLabels + 1] = moreButton
    end

    statusContent.children = initialLabels

    -- CUSTOM AURAS section: lets the user attach ad-hoc auras directly to the token
    -- (stored in creature.auras with custom=true so they survive a reload).
    local primaryToken = m_tokens[1]

    local customAurasContent = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "center",
    }

    local rebuildCustomAuras
    rebuildCustomAuras = function()
        if primaryToken == nil or not primaryToken.valid or primaryToken.properties == nil then
            customAurasContent.children = {}
            return
        end

        local creature = primaryToken.properties
        local auras = creature:try_get("auras", {})
        local items = {}

        for index, auraInstance in ipairs(auras) do
            if rawget(auraInstance, "custom") == true then
                local capturedIndex = index
                local capturedAura = auraInstance
                items[#items + 1] = gui.Panel{
                    width = "95%",
                    height = "auto",
                    flow = "horizontal",
                    halign = "center",
                    valign = "top",
                    vmargin = 2,

                    gui.Input{
                        width = 110,
                        height = 22,
                        hpad = 4,
                        halign = "left",
                        valign = "center",
                        characterLimit = 40,
                        text = capturedAura.name,
                        change = function(element)
                            local auras = primaryToken.properties:try_get("auras", {})
                            capturedAura = auras[capturedIndex] or capturedAura
                            local newName = element.text
                            if newName == nil or newName == "" then
                                newName = "Custom Aura"
                                element.text = newName
                            end
                            primaryToken:ModifyProperties{
                                description = "Rename Custom Aura",
                                execute = function()
                                    capturedAura.name = newName
                                    if capturedAura.aura ~= nil then
                                        capturedAura.aura.name = newName
                                    end
                                end,
                            }
                            primaryToken:UpdateAuras()
                        end,
                    },

                    gui.Label{
                        text = "Radius:",
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        valign = "center",
                        lmargin = 8,
                        rmargin = 4,
                        fontSize = 12,
                    },

                    gui.Input{
                        width = 36,
                        height = 22,
                        hpad = 4,
                        halign = "left",
                        valign = "center",
                        characterLimit = 4,
                        text = tostring((capturedAura.area and capturedAura.area.radius) or 1),
                        change = function(element)
                            local auras = primaryToken.properties:try_get("auras", {})
                            capturedAura = auras[capturedIndex] or capturedAura
                            local r = tonumber(element.text)
                            if r == nil or r < 0 then
                                element.text = tostring((capturedAura.area and capturedAura.area.radius) or 1)
                                return
                            end
                            primaryToken:ModifyProperties{
                                description = "Set Custom Aura Radius",
                                execute = function()
                                    capturedAura.area = dmhub.CalculateShape{
                                        shape = "radiusfromcreature",
                                        token = primaryToken,
                                        range = 100,
                                        radius = r,
                                    }
                                end,
                            }
                            primaryToken:UpdateAuras()
                        end,
                    },

                    gui.Button{
                        classes = {"settingsButton", "sizeM"},
                        width = 20,
                        height = 20,
                        halign = "left",
                        valign = "center",
                        hmargin = 4,
                        linger = function(el)
                            gui.Tooltip("Edit aura settings")(el)
                        end,
                        press = function(element)
                            -- element.root is the popup's own root (popups
                            -- are their own hierarchy -- see Panel.root doc).
                            -- Use m_button.root instead so the edit dialog
                            -- lives in the main UI hierarchy and survives us
                            -- dismissing the popup. Result: popup closes,
                            -- large centered modal appears on top.
                            local mainRoot = m_button.root
                            m_button.popup = nil
                            local editable = DeepCopy(capturedAura.aura)
                            mainRoot:AddChild(editable:ShowEditDialog{
                                norelocate = true,
                                close = function()
                                    primaryToken:ModifyProperties{
                                        description = "Edit Custom Aura",
                                        execute = function()
                                            capturedAura.aura = editable
                                            capturedAura.name = editable.name
                                            capturedAura.iconid = editable.iconid
                                            if editable:has_key("display") then
                                                capturedAura.display = editable.display
                                            end
                                        end,
                                    }
                                    primaryToken:UpdateAuras()
                                end,
                            })
                        end,
                    },

                    gui.Button{
                        classes = {"deleteButton", "sizeS"},
                        halign = "left",
                        valign = "center",
                        linger = function(el)
                            gui.Tooltip("Remove custom aura")(el)
                        end,
                        press = function(element)
                            local guid = capturedAura.guid
                            primaryToken:ModifyProperties{
                                description = "Remove Custom Aura",
                                execute = function()
                                    primaryToken.properties:RemoveAura(guid)
                                end,
                            }
                            primaryToken:UpdateAuras()
                            rebuildCustomAuras()
                        end,
                    },
                }
            end
        end

        items[#items + 1] = gui.Button{
            classes = {"addButton", "sizeXs"},
            halign = "left",
            lmargin = 8,
            tmargin = 4,
            linger = function(el)
                gui.Tooltip("Add a custom aura")(el)
            end,
            press = function(element)
                if primaryToken == nil or not primaryToken.valid or primaryToken.properties == nil then return end
                -- Standard Draw Steel aura visual. Without a real objectid
                -- the engine has no visual to render, even with
                -- tokenAttached = true.
                local defaultObjectId = "b7cbb1bf-6ed4-40b8-b1c9-ce091f24f651"
                -- If the current user is a player (not the DM), seed the
                -- aura's color with their display color so their auras are
                -- visually distinct. DM gets the plain white default.
                local defaultBgcolor = "#ffffffff"
                if not dmhub.isDM then
                    local sessionInfo = dmhub.GetSessionInfo(dmhub.loginUserid)
                    if sessionInfo ~= nil and sessionInfo.displayColor ~= nil then
                        defaultBgcolor = sessionInfo.displayColor.tostring
                    end
                end
                local auraDef = Aura.Create{
                    name = "Custom Aura",
                    applyto = "all",
                    modifiers = {},
                    objectid = defaultObjectId,
                }
                local auraInstance = AuraInstance.new{
                    guid = dmhub.GenerateGuid(),
                    casterid = primaryToken.id,
                    name = "Custom Aura",
                    iconid = auraDef.iconid,
                    display = {hueshift = 0, saturation = 1, brightness = 1, bgcolor = defaultBgcolor},
                    custom = true,
                    tokenAttached = true,
                    symbols = {
                        caster = GenerateSymbols(primaryToken.properties),
                    },
                    area = dmhub.CalculateShape{
                        shape = "radiusfromcreature",
                        token = primaryToken,
                        range = 100,
                        radius = 1,
                    },
                    time = TimePoint.Create(),
                    aura = auraDef,
                }
                primaryToken:ModifyProperties{
                    description = "Add Custom Aura",
                    execute = function()
                        primaryToken.properties:AddAura(auraInstance)
                    end,
                }
                primaryToken:UpdateAuras()
                rebuildCustomAuras()
            end,
        }

        customAurasContent.children = items
    end

    m_button.popupsInheritStyles = true
    m_button.popup = gui.Panel{
        styles = TacPanelStyles.AddConditionMenu,
        classes = {"dialog"},
        floating = true,
        vscroll = true,
        hideObjectsOutOfScroll = true,
        flow = "vertical",
        width = 300,
        height = 800,
        pad = 6,

        gui.Label{
            classes = {"menu-heading"},
            text = "ADD CONDITION",
            halign = "center",
            tmargin = 2,
        },

        gui.Panel{
            classes = {"panel", "menu-divider"},
        },

        gui.Input{
            classes = {"input", "menu-search"},
            placeholderText = "Search...",
            hasFocus = true,
            data = { searchedOption = nil },
            editlag = 0.2,
            edit = function(element)
                if not statusExpanded and #statusEffectData > initialCount then
                    statusExpanded = true
                    local allLabels = {}
                    for i = 1, #statusEffectData do
                        local d = statusEffectData[i]
                        allLabels[i] = makeStatusLabel(d.key, d.effect)
                    end
                    statusContent.children = allLabels
                end
                element.parent:FireEventTree("searchText", string.lower(element.text))
                element.data.searchedOption = nil
                local found = element.text == ""
                for _, option in ipairs(options) do
                    if found == false and option:HasClass("collapsed") == false then
                        found = true
                        element.data.searchedOption = option
                    end
                end
            end,
            submit = function(element)
                if element.data.searchedOption ~= nil then
                    element.data.searchedOption:FireEvent("press")
                end
            end,
        },

        gui.Label{
            classes = {"menu-heading"},
            text = "CONDITIONS",
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = options,
        },

        gui.Input{
            classes = {"input", "cond-custom-input"},
            characterLimit = 60,
            placeholderText = "Add Custom Condition...",
            width = "94%",
            height = "auto",
            halign = "left",
            lmargin = 6,
            tmargin = 6,
            fontSize = TacPanelSizes.Fonts.condInput,
            hpad = 6,
            vpad = 4,

            change = function(element)
                local text = trim(element.text)
                if text ~= "" then
                    for _, tok in ipairs(m_tokens) do
                        tok:ModifyProperties{
                            description = "Add Custom Condition",
                            execute = function()
                                local cc = tok.properties:get_or_add("customConditions", {})
                                cc[dmhub.GenerateGuid()] = {
                                    text = text,
                                    timestamp = dmhub.serverTimeMilliseconds,
                                }
                            end,
                        }
                    end
                end
                element.text = ""
                m_button.popup = nil
            end,
        },

        gui.Label{
            classes = {"menu-heading"},
            text = "STATUS EFFECTS",
        },
        statusContent,

        gui.Label{
            classes = {"menu-heading"},
            text = "CUSTOM AURAS",
        },
        customAurasContent,
    }

    rebuildCustomAuras()
end

--- Display the Persistent Abilities panel
--- @return Panel
function TacPanel.PersistentAbilities()
    return TacPanel.CollapsiblePanel{
        sectionId = "persistentabilities",
        classes = {"collapsed"},
        altBg = false,
        title = "PERSISTENT ABILITIES",
        data = { token = nil },

        refreshCharacter = function(element, token)
            element.data.token = token
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end

            local persistentAbilities = token.properties:try_get("persistentAbilities")
            local q = dmhub.initiativeQueue
            if persistentAbilities == nil or #persistentAbilities == 0 or q == nil or q.hidden then
                element:SetClass("collapsed", true)
                return
            end

            local abilities = token.properties:GetActivatedAbilities{excludeGlobal = true}
            local totalCost = 0
            local chips = {}

            for _, entry in ipairs(persistentAbilities) do
                if entry.combatid == q.guid then
                    totalCost = totalCost + entry.cost

                    local abilityRef = nil
                    for _, ability in ipairs(abilities) do
                        if ability.name == entry.abilityName then
                            abilityRef = ability
                            break
                        end
                    end

                    local iconid = abilityRef and abilityRef.iconid or ""
                    local display = abilityRef and abilityRef.display or {}
                    local guid = entry.guid

                    chips[#chips+1] = gui.Panel{
                        classes = {"panel", "cond-chip"},
                        data = { targetingMarkers = {} },
                        popupPositioning = "panel",

                        hover = function(el)
                            el:FireEvent("clearMarkers")
                            if abilityRef then
                                el.tooltip = gui.TooltipFrame(
                                    CreateAbilityTooltip(abilityRef, {width = 540, token = token}),
                                    { halign = "left", valign = "top" }
                                )
                                if abilityRef:Persistence().mode == "recast_target" then
                                    for _, targetid in ipairs(entry.targets or {}) do
                                        local targetToken = dmhub.GetTokenById(targetid)
                                        if targetToken ~= nil then
                                            el.data.targetingMarkers[#el.data.targetingMarkers+1] =
                                                dmhub.MarkLineOfSight(token, targetToken, token.properties:GetPierceWalls())
                                        end
                                    end
                                end
                            end
                        end,
                        dehover = function(el)
                            el:FireEvent("clearMarkers")
                        end,
                        clearMarkers = function(el)
                            for _, m in ipairs(el.data.targetingMarkers) do
                                m:Destroy()
                            end
                            el.data.targetingMarkers = {}
                        end,

                        iconid ~= "" and gui.Panel{
                            classes = {"panel", "cond-icon"},
                            bgimage = iconid,
                            bgcolor = display.bgcolor or "white",
                            hueshift = display.hueshift or 0,
                        } or nil,
                        gui.Label{
                            classes = {"label", "cond-name"},
                            text = string.format("%s--%d", entry.abilityName, entry.cost),
                        },
                        gui.Panel{
                            classes = {"panel", "cond-remove"},
                            press = function(el)
                                token.properties:EndPersistentAbilityById(guid)
                            end,
                            linger = function(el)
                                gui.Tooltip("Stop")(el)
                            end,
                            gui.Label{
                                classes = {"label", "cond-remove"},
                                text = "X",
                            },
                        },
                    }
                end
            end

            if #chips == 0 then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)
            local children = {}
            for _, chip in ipairs(chips) do
                children[#children+1] = chip
            end
            if totalCost > 2 then
                children[#children+1] = gui.Label{
                    classes = {"danger", "sizeXs"},
                    width = "100%",
                    height = "auto",
                    text = "Too many persistent abilities. You must end some.",
                }
            end
            element:FireEventTree("setContent", children)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        gui.Panel{
            classes = {"panel", "cond-chips"},
            wrap = true,
            setContent = function(element, newChildren)
                element.children = newChildren
            end,
        },
    }
end

--- Display the Conditions panel
--- @return Panel
function TacPanel.Conditions()
    local m_token = nil

    -- Add button first
    local m_addButton = gui.Button{
        classes = {"addButton"} ,
        press = function(element)
            TacPanel.AddConditionMenu{
                tokens = {m_token},
                button = element,
            }
        end,
        linger = function(el)
            gui.Tooltip("Add a condition or effect")(el)
        end,
    }

    return TacPanel.CollapsiblePanel{
        sectionId = "conditions",
        altBg = false,
        title = "AURAS, CONDITIONS, & EFFECTS",
        data = { token = nil },
        refreshCharacter = function(element, token)
            m_token = token
            element.data.token = token
            if token == nil or not token.valid then
                element:FireEventTree("setContent", {})
                return
            end

            local creature = token.properties
            local conditions = creature:try_get("inflictedConditions", {})

            -- Gather status effects (ongoing effects with statusEffect flag)
            local ongoingTable = dmhub.GetTable("characterOngoingEffects")
            local activeEffects = creature:ActiveOngoingEffects()
            local statusEffects = {}
            for _, entry in ipairs(activeEffects) do
                local effectInfo = ongoingTable[entry.ongoingEffectid]
                if effectInfo ~= nil and effectInfo.statusEffect then
                    statusEffects[#statusEffects + 1] = { entry = entry, info = effectInfo }
                end
            end

            -- Rebuild chips each refresh (lists are small)
            local children = {m_addButton}

            -- Condition chips
            for condid, cond in pairs(conditions) do
                children[#children + 1] = TacPanel.ConditionChip(condid, cond, token)
            end

            -- Status effect chips
            for _, se in ipairs(statusEffects) do
                children[#children + 1] = TacPanel.StatusEffectChip(se.entry, se.info, token)
            end

            -- Custom condition chips
            local customConditions = creature:try_get("customConditions", {})
            for key, entry in pairs(customConditions) do
                children[#children + 1] = TacPanel.CustomConditionChip(key, entry, token)
            end

            -- Aura chips (DISABLED FOR DIAGNOSTIC)
            local aurasTouching = creature:GetAurasAffecting(token) or {}
            for _, auraInfo in ipairs(aurasTouching) do
                if rawget(auraInfo.auraInstance, "casterid") ~= token.charid then --we'll see our own auras because we emit them.
                    children[#children + 1] = TacPanel.AuraChip(auraInfo.auraInstance, token)
                end
            end

            --auras emitting.
            FillAurasEmittingPanels(token, children)

            -- "No conditions" placeholder when nothing to show
            if #children == 1 then
                children[#children + 1] = gui.Label{
                    classes = {"label", "cond-empty"},
                    text = "No conditions",
                }
            end

            element:FireEventTree("setContent", children)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        gui.Panel{
            classes = {"panel", "cond-chips"},
            wrap = true,
            setContent = function(element, newChildren)
                element.children = newChildren
            end,

            m_addButton,
        },

    }
end

--- Stub: conditions are rendered inline by the Conditions section now.
--- @param token CharacterToken
--- @return nil
CharacterPanel.CreateConditionsPanel = function(token)
    return nil
end

--- Build the vision "lookup" distance slider (hidden unless the token may look).
--- @return Panel
function CharacterPanel.CreateLookupPanel()
    local m_slider = nil
    local m_maxLookup = -1

    return gui.Panel{
        width = "80%",
        height = "auto",
        halign = "center",
        tmargin = 4,
        monitor = "lookup",

        events = {
            monitor = function(element)
                if m_slider ~= nil then
                    local cur = dmhub.GetSettingValue("lookup")
                    if m_slider.value ~= cur then
                        m_slider:SetValue(cur)
                    end
                end
            end,
        },

        refresh = function(element)
            local tok = dmhub.currentToken
            local canLookup = dmhub.GetSettingValue("canlookup")
            if tok == nil or (dmhub.isDM and dmhub.tokenVision == nil) or canLookup == "never" then
                element:SetClass("collapsed", true)
                m_maxLookup = -1
                m_slider = nil
                return
            end

            local maxLookupSetting = dmhub.GetSettingValue("maxlookup")
            local maxLookup
            if canLookup == "always" then
                maxLookup = tok.countFloorsAbove
            else
                maxLookup = tok.countFloorsWithVisionAbove
            end
            if maxLookupSetting >= 0 then
                maxLookup = math.min(maxLookup, maxLookupSetting)
            end

            if maxLookup ~= m_maxLookup then
                m_maxLookup = maxLookup
                element:SetClass("collapsed", maxLookup <= 0)

                if maxLookup <= 0 then
                    m_slider = nil
                    element.children = {}
                else
                    local options
                    if maxLookup == 1 then
                        options = {{id = 0, text = "Look Forward"}, {id = 1, text = "Look Up"}}
                    else
                        options = {{id = 0, text = "Fwd"}}
                        for i = 1, maxLookup do
                            options[#options+1] = {id = i, text = "Up " .. tostring(i)}
                        end
                    end

                    m_slider = gui.EnumeratedSliderControl{
                        width = "100%",
                        options = options,
                        value = dmhub.GetSettingValue("lookup"),
                        change = function(el)
                            dmhub.SetSettingValue("lookup", el.value)
                        end,
                    }
                    element.children = {m_slider}
                end
            end
        end,
    }
end

--- Open the condition-search pop-up on args.button, applied to args.tokens.
--- @param args {tokens: CharacterToken[], button: Panel}
function CharacterPanel.AddConditionMenu(args)
    local m_tokens = args.tokens
    local m_button = args.button

    local options = {}
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}

    for k, effect in unhidden_pairs(conditionsTable) do
        if effect.showInMenus then
            local children = {}
            if effect.indefiniteDuration then

                local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)
                local riders = {}
                for riderid,rider in unhidden_pairs(ridersTable) do
                    if rider.condition == k and rider.showAsMenuOption then
                        children[#children+1] = gui.Label{
                            halign = "right",
                            swallowPress = true,
                            classes = { "conditionSuboption" },
                            bgimage = true,
                            text = rider.name,
                            press = function(element)
                                element.parent:FireEvent("press", "eoe", riderid)
                            end,
                        }
                    end
                end

            else
                children = {
                    gui.Label {
                        halign = "right",
                        swallowPress = true,
                        classes = { "conditionSuboption" },
                        bgimage = true,
                        text = "EoT",
                        press = function(element)
                            element.parent:FireEvent("press", "eot")
                        end,
                    },

                    gui.Label {
                        halign = "right",
                        swallowPress = true,
                        classes = { "conditionSuboption" },
                        bgimage = true,
                        text = "Save",
                        press = function(element)
                            element.parent:FireEvent("press", "save")
                        end,
                    },
                    gui.Label {
                        halign = "right",
                        swallowPress = true,
                        classes = { "conditionSuboption" },
                        bgimage = true,
                        text = "EoE",
                        press = function(element)
                            element.parent:FireEvent("press", "eoe")
                        end,
                    },
                }
            end

            options[#options + 1] = gui.Label {
                classes = { "conditionOption" },
                bgimage = true,
                text = effect.name,
                flow = "horizontal",
                searchText = function(element, searchText)
                    if string.starts_with(string.lower(element.text), searchText) then
                        element:SetClass("collapsed", false)
                    else
                        element:SetClass("collapsed", true)
                    end
                end,
                press = function(element, durationOverride, riderid)
                    if (not durationOverride) and effect.indefiniteDuration then
                        durationOverride = "eoe"
                    end
                    for _,tok in ipairs(m_tokens) do
                        tok:BeginChanges()
                        tok.properties:InflictCondition(k, { riders = {riderid}, duration = (durationOverride or "eot") })
                        tok:CompleteChanges("Apply Condition")
                    end
                    m_button.popup = nil
                end,

                linger = function(element)
                    gui.Tooltip(string.format("%s: %s", effect.name, effect.description))(element)
                end,

                children = children,
            }
        end
    end

    table.sort(options, function(a, b) return a.text < b.text end)

    local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
    local statusEffectOptions = {}
    for k, effect in unhidden_pairs(ongoingEffectsTable) do
        if effect.statusEffect then
            statusEffectOptions[#statusEffectOptions + 1] = gui.Label {
                classes = { "conditionOption" },
                bgimage = true,
                text = effect.name,
                searchText = function(element, searchText)
                    if string.starts_with(string.lower(element.text), searchText) then
                        element:SetClass("collapsed", false)
                    else
                        element:SetClass("collapsed", true)
                    end
                end,
                linger = function(element)
                    gui.Tooltip(string.format("%s: %s", effect.name, effect.description))(element)
                end,
                press = function(element)
                    for _,tok in ipairs(m_tokens) do
                        tok:ModifyProperties{
                            description = tr("Apply Status Effect"),
                            combine = true,
                            execute = function()
                                if tok == nil or not tok.valid then
                                    return
                                end
                                tok.properties:ApplyOngoingEffect(k)
                            end,
                        }
                    end
                    m_button.popup = nil
                end,
            }
        end
    end

    table.sort(statusEffectOptions, function(a, b) return a.text < b.text end)

    m_button.popupsInheritStyles = true
    m_button.popup = gui.TooltipFrame(
        gui.Panel {
            styles = ThemeEngine.MergeTokens{
                {
                    selectors = {"conditionSuboption"},
                    textAlignment = "center",
                    fontSize = 12,
                    bgcolor = "@bg",
                    borderColor = "@fg",
                    borderWidth = 2,
                    height = 18,
                    minWidth = 40,
                    width = "auto",
                },
                {
                    selectors = {"conditionSuboption", "hover"},
                    bgcolor = "@bgInverse",
                    color = "@fgInverse",
                },
                {
                    selectors = {"conditionSuboption", "press"},
                    brightness = 1.2,
                },
                {
                    selectors = { "conditionOption" },
                    width = "95%",
                    height = 20,
                    fontSize = 14,
                    color = "@fg",
                    bgcolor = "clear",
                    halign = "center",
                },
                {
                    selectors = { "conditionOption", "searched" },
                    bgcolor = "@bgInverse",
                    color = "@fgInverse",
                },
                {
                    selectors = { "conditionOption", "hover" },
                    bgcolor = "@bgInverse",
                    color = "@fgInverse",
                },
                {
                    selectors = { "conditionOption", "press" },
                    brightness = 1.2,
                },

                {
                    selectors = { "title" },
                    fontSize = 16,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    halign = "left",
                },

            },
            vscroll = true,
            flow = "vertical",
            width = 300,
            height = 800,

            gui.Label {
                fontSize = 18,
                bold = true,
                width = "auto",
                height = "auto",
                halign = "center",
                text = "Add Condition",
            },

            gui.Panel {
                bgimage = true,
                width = "90%",
                height = 1,
                bgcolor = "white",
                halign = "center",
                vmargin = 8,
                gradient = ThemeEngine.ResolveTokens("@surfaceLinear"), --Styles.horizontalGradient,
            },

            gui.Input {
                placeholderText = "Search...",
                hasFocus = true,
                width = "70%",
                hpad = 8,
                height = 20,
                fontSize = 14,
                data = {
                    searchedOption = nil

                },
                edit = function(element)
                    element.parent:FireEventTree("searchText", string.lower(element.text))

                    element.data.searchedOption = nil

                    local found = element.text == ""
                    for i, option in ipairs(options) do
                        if found == false and option:HasClass("collapsed") == false then
                            found = true
                            option:SetClass("searched", true)
                            element.data.searchedOption = option
                        else
                            option:SetClass("searched", false)
                        end
                    end
                end,
                submit = function(element)
                    if element.data.searchedOption ~= nil then
                        element.data.searchedOption:FireEvent("press")
                    end
                end,
            },

            gui.Label {
                classes = { "title" },
                text = "Conditions",
            },

            gui.Panel {
                width = "100%",
                height = "auto",
                flow = "vertical",

                children = options,
            },

            gui.Label {
                classes = { "title" },
                text = "Status Effects",
            },

            gui.Panel {
                width = "100%",
                height = "auto",
                flow = "vertical",

                children = statusEffectOptions,
            },
        },

        {
            halign = "left",
            valign = "bottom",
        }
    )
end

local TACPANEL_DEFAULT_ORDER = {
    "statistics",
    "summoner",
    "routines",
    "persistentabilities",
    "heroicresources",
    "otherresources",
    "conditions",
    "skilllanguages",
    "features",
    "perks",
    "notes",
}

local TACPANEL_FACTORIES = {
    statistics = TacPanel.Statistics,
    routines = TacPanel.Routines,
    persistentabilities = TacPanel.PersistentAbilities,
    heroicresources = TacPanel.HeroicResources,
    otherresources = TacPanel.OtherResources,
    conditions = TacPanel.Conditions,
    skilllanguages = TacPanel.SkillLanguages,
    features = TacPanel.Features,
    perks = TacPanel.Perks,
    notes = TacPanel.Notes,
    summoner = TacPanel.Summoner,
}

--- Register a tac-panel section so it appears in the character details panel.
--- Mods outside this file should call this at load time to add their own
--- sections (the section becomes available the next time a character panel
--- is built).
--- @param id string Section id (used for ordering preference + drag/drop).
--- @param factory fun(): Panel Returns the section panel; called once per character panel build.
--- @param opts? {after?: string, before?: string} Position relative to an existing section. Defaults to appending at the end.
function TacPanel.RegisterSection(id, factory, opts)
    opts = opts or {}
    TACPANEL_FACTORIES[id] = factory

    for i,existing in ipairs(TACPANEL_DEFAULT_ORDER) do
        if existing == id then
            table.remove(TACPANEL_DEFAULT_ORDER, i)
            break
        end
    end

    local insertAt = #TACPANEL_DEFAULT_ORDER + 1
    if opts.after then
        for i,existing in ipairs(TACPANEL_DEFAULT_ORDER) do
            if existing == opts.after then
                insertAt = i + 1
                break
            end
        end
    elseif opts.before then
        for i,existing in ipairs(TACPANEL_DEFAULT_ORDER) do
            if existing == opts.before then
                insertAt = i
                break
            end
        end
    end
    table.insert(TACPANEL_DEFAULT_ORDER, insertAt, id)
end

--- Per-user preference key for the saved section order.
--- @return string
function TacPanel.KeyName()
    return string.format("tacpanel_order:%s", dmhub.userid or "default")
end

--- The saved section order, falling back to the default order and appending any
--- newly-registered sections.
--- @return string[] Section ids in display order
function TacPanel.GetOrder()
    local saved = dmhub.GetPref(TacPanel.KeyName())
    if saved == nil or type(saved) ~= "string" then
        local copy = {}
        for _, id in ipairs(TACPANEL_DEFAULT_ORDER) do
            copy[#copy+1] = id
        end
        return copy
    end
    local order = {}
    for id in string.gmatch(saved, "[^,]+") do
        if TACPANEL_FACTORIES[id] ~= nil then
            order[#order+1] = id
        end
    end
    -- Append any sections missing from the saved order (e.g. newly added)
    local present = {}
    for _, id in ipairs(order) do present[id] = true end
    for _, id in ipairs(TACPANEL_DEFAULT_ORDER) do
        if not present[id] then
            order[#order+1] = id
        end
    end
    return order
end

--- Persist the section order to the user's preferences.
--- @param order string[] Section ids in display order
function TacPanel.SaveOrder(order)
    local key = TacPanel.KeyName()
    dmhub.SetPref(key, table.concat(order, ","))
end

--- Build the vertical container of all registered sections (saved order, with
--- drag-to-reorder).
--- @return Panel
function TacPanel.SectionsContainer()
    local sectionPanels = {}
    for _, id in ipairs(TACPANEL_DEFAULT_ORDER) do
        sectionPanels[id] = TACPANEL_FACTORIES[id]()
    end

    local function sortChildren(element, order)
        local orderMap = {}
        for i, id in ipairs(order) do
            orderMap[id] = i
        end
        local sorted = {}
        for _, child in ipairs(element.children) do
            sorted[#sorted+1] = child
        end
        table.sort(sorted, function(a, b)
            local ia = orderMap[a.data.sectionId] or 999
            local ib = orderMap[b.data.sectionId] or 999
            return ia < ib
        end)
        element.children = {}
        element.children = sorted
    end

    local container = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = -26,
        monitor = GetDockablePanelsSetting(),
        events = {
            monitor = function(element)
                dmhub.SetPref(TacPanel.KeyName(), nil)
                sortChildren(element, TACPANEL_DEFAULT_ORDER)
            end,
        },

        reorderSections = function(element, draggedId, targetId)
            if draggedId == targetId then return end
            local order = TacPanel.GetOrder()
            local draggedIndex = nil
            for i, id in ipairs(order) do
                if id == draggedId then draggedIndex = i break end
            end
            if draggedIndex == nil then return end
            table.remove(order, draggedIndex)
            local targetIndex = nil
            for i, id in ipairs(order) do
                if id == targetId then targetIndex = i break end
            end
            if targetIndex == nil then return end
            table.insert(order, targetIndex, draggedId)
            TacPanel.SaveOrder(order)
            sortChildren(element, order)
        end,
    }

    local initialOrder = TacPanel.GetOrder()
    local initialChildren = {}
    for _, id in ipairs(initialOrder) do
        initialChildren[#initialChildren+1] = sectionPanels[id]
    end
    container.children = initialChildren
    return container
end

--- Build the full single-character tac panel (all registered sections). A theme
--- reactivity root.
--- @param m_token CharacterToken
--- @return Panel
CharacterPanel.CreateCharacterDetailsPanel = function(m_token)

    local m_effectEntryPanels = {}
    local m_customConditionPanels = {}

    local resultPanel = nil

    resultPanel = gui.Panel{
        styles = TacPanel.AllStyles(),
        width = "100%",
        height = "auto",
        flow = "vertical",

        refreshToken = function(element, tok)
            m_token = tok
        end,

        TacPanel.SectionsContainer(),
    }

    return RegisterRoot(resultPanel)
end

-- DEAD CODE: DecorateHitpointsPanel / DecoratePortraitPanel have no callers
-- anywhere in the repo. Commented out pending removal. Uses a level-1 long
-- bracket (--[==[ ]==]) because the body contains a [[...]] string literal that
-- would otherwise close a plain --[[ ]] comment early.
--[==[
--- Build the floating "spend a Recovery" diamond overlaid on the portrait's
--- hitpoints area (heroes / retainers / companions only).
--- @return Panel
function CharacterPanel.DecorateHitpointsPanel()
	local recoveryid = nil
	local recoveryInfo = nil
	local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
	for k,v in pairs(resourcesTable) do
		if not v:try_get("hidden", false) and v.name == "Recovery" then
			recoveryid = k
			recoveryInfo = v
		end
	end

	local m_token = nil
	local m_hidden = false
	return gui.Panel{
		floating = true,
		width = "100%",
		height = "100%",
		refreshCharacter = function(element, token)
			m_token = token
			m_hidden = recoveryid == nil or token == nil or (not token.valid) or token.properties == nil or ((not token.properties:IsHero()) and (not token.properties:IsRetainer()) and (not token.properties:IsCompanion()))
			element:SetClass("hidden", m_hidden)
		end,

		gui.Panel{
			halign = "center",
			valign = "bottom",
			cornerRadius = 16,
			y = 8,
			width = 32,
			height = 32,
			bgimage = true,
			borderWidth = 1,
			borderColor = Styles.textColor,
			gradient = Styles.healthGradient,
			bgcolor = "white",

			styles = {
				{
					selectors = {"hover", "~expended"},
					brightness = 2,
					transitionTime = 0.2,
				},
				{
					selectors = {"press", "~expended"},
					brightness = 0.5,
				},
				{
					selectors = {"expended"},
					saturation = 0,
				},
			},

			hover = function(element)
				local usage = m_token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
				local max = m_token.properties:GetResources()[recoveryid] or 0
				local quantity = max - usage


                local usageNote = "Click to use"

                if m_token.properties:CurrentHitpoints() >= m_token.properties:MaxHitpoints() then
                    usageNote = "Already at maximum stamina"
                elseif quantity <= 0 then
                    if m_token.properties:IsHero() and m_token.properties:GetHeroTokens() >= 2 then
                        usageNote = "Click to spend 2 hero tokens as a Recovery"
                    else
                        usageNote = "No Recoveries left"
                    end
                end

				local tooltip = string.format("Recoveries: %d/%d\nRecovery Value: %d\n%s.", quantity, max, m_token.properties:RecoveryAmount(), usageNote)
                local recoverySharing = m_token.properties:ShareRecoveriesWith()
                if recoverySharing ~= nil then
                    tooltip = tooltip .. "\nCan Share Recoveries With:\n"
                    for i,token in ipairs(recoverySharing) do
                        if token.charid ~= m_token.charid then
                            local usage = token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
                            local max = token.properties:GetResources()[recoveryid] or 0
                            local quantity = max - usage
                            tooltip = tooltip .. string.format("%s (%d/%d)\n", token.name, quantity, max)
                        end
                    end
                end
				gui.Tooltip(tooltip)(element)
			end,

			click = function(element)
				if m_token == nil then
					return
				end

                local useHeroTokens = false

				local quantity = max(0, (m_token.properties:GetResources()[recoveryid] or 0) - (m_token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
				if quantity <= 0 then
                    if (not m_token.properties:IsHero()) or m_token.properties:GetHeroTokens() < 2 then 
					    return
                    end

                    --can spend hero tokens instead.
                    useHeroTokens = true
				end

				if m_token.properties:CurrentHitpoints() >= m_token.properties:MaxHitpoints() then
					return
				end

				m_token:BeginChanges()
				m_token.properties:Heal(m_token.properties:RecoveryAmount(), "Use Recovery")
                if not useHeroTokens then
				    m_token.properties:ConsumeResource(recoveryid, recoveryInfo.usageLimit, 1, "Used Recovery")
                end

				m_token:CompleteChanges("Use Recovery")

                if useHeroTokens then
                    m_token.properties:SetHeroTokens(m_token.properties:GetHeroTokens()-2, "Used to Recover")
                    local classInfo = m_token.properties:IsHero() and m_token.properties:GetClass() or nil
                    track("hero_token_change", {
                        change = -2,
                        source = "recovery",
                        class = classInfo and classInfo.name or "unknown",
                        dailyLimit = 30,
                    })
                end

                local remaining = max(0, (m_token.properties:GetResources()[recoveryid] or 0) - (m_token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
                local classInfo = m_token.properties:IsHero() and m_token.properties:GetClass() or nil
                local q = dmhub.initiativeQueue
                track("recovery_spend", {
                    class = classInfo and classInfo.name or "unknown",
                    level = m_token.properties:CharacterLevel(),
                    remaining = remaining,
                    context = (q ~= nil and not q.hidden and q:try_get("gameMode") == "combat") and "combat" or "rest",
                    dailyLimit = 20,
                })
			end,

			rightClick = function(element)
                local entries = {
					{
						text = "Edit Recoveries",
						click = function()
							element.popup = nil
							element:FireEventTree("editRecoveries")
						end,
					}
                }


                local recoverySharing = m_token.properties:ShareRecoveriesWith()
                if recoverySharing ~= nil then
                    for i,token in ipairs(recoverySharing) do
                        if token.charid ~= m_token.charid then
                            local usage = token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
                            local max = token.properties:GetResources()[recoveryid] or 0
                            local quantity = max - usage
                            if quantity > 0 then
                                local casterToken = m_token
                                entries[#entries+1] = {
                                    text = string.format("Spend %s's Recovery (%d/%d)", token.name, quantity, max),
                                    click = function()
                                        element.popup = nil

                                        local groupid = dmhub.GenerateGuid()

                                        casterToken:ModifyProperties{
                                            description = string.format("Use %s's Recovery", token.name),
                                            groupid = groupid,
                                            execute = function()
                                                casterToken.properties:Heal(casterToken.properties:RecoveryAmount(), "Use Recovery")
                                            end,
                                        }

                                        token:ModifyProperties{
                                            description = string.format("%s's Recovery used by %s", token.name, casterToken.name),
                                            groupid = groupid,
                                            execute = function()
                                                token.properties:ConsumeResource(recoveryid, recoveryInfo.usageLimit, 1, "Used Recovery")
                                            end,
                                        }
                                    end,
                                }
                            end
                        end
                    end
                end

                element.popup = gui.ContextMenu{
                    entries = entries,
                }
			end,


			gui.Label{
				width = "100%",
				height = "auto",
				halign = "center",
				valign = "center",
				textAlignment = "center",
				color = "white",
				fontSize = 20,
				characterLimit = 2,
				editRecoveries = function(element)
					element:BeginEditing()
				end,
				change = function(element)
					local n = tonumber(element.text)
					if n == nil then
						element:FireEvent("refreshCharacters", m_token)
						return
					end

					local nresources = m_token.properties:GetResources()[recoveryid] or 0
					local usage = m_token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0

					local current = nresources - usage
					local delta = n - current

					m_token:BeginChanges()
					if delta > 0 then
						m_token.properties:RefreshResource(recoveryid, recoveryInfo.usageLimit, delta, "Used Recovery")
					else
						m_token.properties:ConsumeResource(recoveryid, recoveryInfo.usageLimit, -delta, "Used Recovery")
					end
					m_token:CompleteChanges("Set Recoveries")
				end,

				refreshCharacter = function(element, token)
					if m_hidden then
						return
					end

					local quantity = max(0, (token.properties:GetResources()[recoveryid] or 0) - (token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
					element.text = string.format("%d", quantity)

					element.parent:SetClass("expended", quantity <= 0)
				end,
			},
		}

	}
end

--- Build the overlay decorations drawn on top of a token portrait.
--- @param token CharacterToken
--- @return Panel
function CharacterPanel.DecoratePortraitPanel(token)
	local m_token = token
	return gui.Panel{
		width = "100%",
		height = "100%",

        gui.Panel{
            classes = {"hidden"},
            floating = true,
            halign = "left",
            valign = "top",
            width = 40,
            height = 16,
            flow = "horizontal",
            linger = function(element)
                local minHeroes = m_token.properties:try_get("minHeroes")
                if minHeroes == nil then
                    return
                end
                gui.Tooltip(string.format("This monster is used when there are %d or more heroes.", minHeroes))(element)
            end,
            gui.Panel{
                bgimage = "icons/icon_app/icon_app_18.png",
                bgcolor = Styles.textColor,
                width = 16,
                height = 16,
            },
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 12,
                color = Styles.textColor,
                refreshCharacter = function(element, token)
                    if not token.properties:IsMonster() or token.properties:try_get("minHeroes") == nil then
                        element.parent:SetClass("hidden", true)
                        return
                    end

                    element.text = string.format("%d+", token.properties.minHeroes)
                    element.parent:SetClass("hidden", false)
                end,
            },
        },

        gui.Panel{
            floating = true,
            halign = "right",
            x = 15,
            width = 30,
            height = "100%",
            flow = "vertical",

            gui.Panel{
                valign = "top",
                vmargin = 8,
                width = 30,
                height = 30,
                flow = "none",

                refreshCharacter = function(element, token)
                    m_token = token
                    element:SetClass("hidden", token == nil or (not token.valid) or token.properties == nil or (token.properties.typeName ~= "character" and token.properties.typeName ~= "AnimalCompanion"))
                end,

                gui.Label{
                    fontSize = 22,
                    textWrap = false,
                    bold = true,
                    color = Styles.textColor,
                    halign = "center",
                    valign = "center",
                    characterLimit = 2,
                    editable = true,
                    width = "100%",
                    height = "100%",
                    textAlignment = "center",
                    cornerRadius = 15,
                    bgcolor = "black",
                    borderColor = Styles.textColor,
                    borderWidth = 2,
                    bgimage = true,
                    numeric = true,
                    flow = "none",

                    gui.Label{
                        bgimage = true,
                        bgcolor = "black",
                        bold = true,
                        hpad = 1,
                        vpad = 1,
                        fontSize = 9,
                        borderWidth = 0.5,
                        borderColor = Styles.textColor,
                        halign = "center",
                        valign = "bottom",
                        width = "auto",
                        height = "auto",
                        text = "Tokens",
                        y = 7,
                        press = function(element)

                            local n = dmhub.GetSettingValue("numheroes")

                            local items = {}
                            items[#items+1] = {
                                text = string.format("Reset Hero Tokens For Session (%d heroes)", n),
                                click = function()
                                    local prev = m_token.properties:GetHeroTokens()
                                    m_token.properties:SetHeroTokens(n, "Session Reset")
                                    if n ~= prev then
                                        local classInfo = m_token.properties:IsHero() and m_token.properties:GetClass() or nil
                                        track("hero_token_change", {
                                            change = n - prev,
                                            source = "session_reset",
                                            class = classInfo and classInfo.name or "unknown",
                                            dailyLimit = 30,
                                        })
                                    end
                                    element.popup = nil
                                end,
                            }


                            element.popup = gui.ContextMenu{
                                entries = items,
                            }

                        end,
                    },

                    --if the global resources change we want to refresh.
                    monitorGame = CharacterResource.GlobalResourcePath(),
                    refreshGame = function(element)
                        element:FireEvent("refreshCharacter", m_token)
                    end,

                    hover = function(element)

                        local text = [[<b>Hero Tokens</b>
* You can spend a hero token to gain two surges. Surges allow you to increase the damage or potency of an ability.
* You can spend a hero token when you fail a saving throw to succeed on it instead.
* You can reroll the result of a test. You must use the new result and can't use more than 1 Hero token on a test.
* You can spend 2 hero tokens on your turn or whenever you take damage (no action required) to regain Stamina equal to your Recovery value without spending a Recovery.
]]
                        
                        local history = m_token.properties:GetHeroTokenHistory()
                        if history ~= nil and #history > 0 then
                            text = text .. "\n<b>Recent Changes:</b>"
                            for _,entry in ipairs(history) do
                                text = string.format("%s\n%s: %d by %s %s", text, entry.note, entry.value, entry.who, entry.when)
                            end
                        end

                        gui.Tooltip(text)(element)
                    end,

                    refreshCharacter = function(element, token)
                        if element.parent:HasClass("hidden") then
                            return
                        end

                        if m_token == nil or not m_token.valid then
                            return
                        end

                        element.text = tostring(token.properties:GetHeroTokens())
                    end,

                    change = function(element)
                        if m_token == nil or not m_token.valid then
                            return
                        end

                        local n = tonumber(element.text)
                        if n ~= nil and round(n) == n then
                            n = math.max(0, n)
                            local prev = m_token.properties:GetHeroTokens()
                            m_token.properties:SetHeroTokens(n, "Set manually")
                            if n ~= prev then
                                local classInfo = m_token.properties:IsHero() and m_token.properties:GetClass() or nil
                                track("hero_token_change", {
                                    change = n - prev,
                                    source = "manual",
                                    class = classInfo and classInfo.name or "unknown",
                                    dailyLimit = 30,
                                })
                            end
                        end
                        element.text = string.format("%d", m_token.properties:GetHeroTokens())
                    end,
                },

                gui.Label{
                    fontSize = 22,
                    textWrap = false,
                    bold = true,
                    color = Styles.textColor,
                    halign = "center",
                    valign = "center",
                    characterLimit = 2,
                    editable = true,
                    width = "100%",
                    height = "100%",
                    textAlignment = "center",
                    cornerRadius = 15,
                    bgcolor = "black",
                    borderColor = Styles.textColor,
                    borderWidth = 2,
                    bgimage = true,
                    numeric = true,
                    flow = "none",
                    y = 45,

                    hover = function(element)
                        if m_token == nil or not m_token.valid then
                            return
                        end
                        local q = dmhub.initiativeQueue
                        if q == nil or q.hidden then
                            element.tooltip = string.format("No %s while not in combat.", m_token.properties:GetHeroicResourceName())
                            return
                        end
                        local desc = m_token.properties:GetHeroicResourceName()
                        local negativeValue = m_token.properties:CalculateNamedCustomAttribute("Negative Heroic Resource")
                        local text = nil
                        if negativeValue > 0 then
                            text = string.format("%s may go as low as -%d", desc, negativeValue)
                        end
                        element.tooltip = gui.StatsHistoryTooltip{ text = text, description = desc, entries = m_token.properties:GetStatHistory(CharacterResource.heroicResourceId):GetHistory() }
                    end,

                    gui.Label{
                        bgimage = true,
                        bgcolor = "black",
                        bold = true,
                        hpad = 1,
                        vpad = 1,
                        fontSize = 9,
                        borderWidth = 1,
                        borderColor = Styles.textColor,
                        halign = "center",
                        valign = "bottom",
                        width = "auto",
                        height = "auto",
                        text = "xx",
                        y = 7,

                        refreshCharacter = function(element, token)
                            local creature = token.properties
                            element.text = string.format("%s", creature:GetHeroicResourceName())
                        end,
                    },


                    refreshCharacter = function(element, token)
                        local q = dmhub.initiativeQueue
                        if q == nil or q.hidden then
                            element.text = "-"
                            return
                        end
                        local creature = token.properties
                        local resources = creature:GetHeroicOrMaliceResources()
                        element.text = tostring(resources)
                    end,

                    change = function(element)
                        local amount = tonumber(element.text)
                        if amount == nil then
                            element:FireEvent("refreshCharacter", m_token)
                            return
                        end

                        local creature = m_token.properties
                        if not creature:IsHero() and not creature:IsCompanion() then
                            CharacterResource.SetMalice(math.max(0, amount), "Manually set")
                            return
                        end

                        local resource = dmhub.GetTable(CharacterResource.tableName)[CharacterResource.heroicResourceId]

                        amount = resource:ClampQuantity(m_token.properties, amount)

                        local diff = amount - m_token.properties:GetHeroicOrMaliceResources()
                        if diff == 0 then
                            element:FireEvent("refreshCharacter", m_token)
                            return
                        end
                        m_token:ModifyProperties{
                            description = "Change Heroic Resource",
                            execute = function()
                                if diff > 0 then
                                    print("RESOURCE:: CALLING REFRESH...")
                                    m_token.properties:RefreshResource(CharacterResource.heroicResourceId, "unbounded", diff)
                                else
                                    print("RESOURCE:: CALLING CONSUME...")
                                    m_token.properties:ConsumeResource(CharacterResource.heroicResourceId, "unbounded", -diff)
                                end
                            end,
                        }

                    end,
                },

                gui.Label{
                    fontSize = 22,
                    textWrap = false,
                    bold = true,
                    color = Styles.textColor,
                    halign = "center",
                    valign = "center",
                    characterLimit = 2,
                    editable = true,
                    width = "100%",
                    height = "100%",
                    textAlignment = "center",
                    cornerRadius = 15,
                    bgcolor = "black",
                    borderColor = Styles.textColor,
                    borderWidth = 2,
                    bgimage = true,
                    numeric = true,
                    flow = "none",
                    y = 90,

                    hover = function(element)
                        local desc = "Surges"
                        element.tooltip = gui.StatsHistoryTooltip{ description = desc, entries = m_token.properties:GetStatHistory(CharacterResource.surgeResourceId):GetHistory() }
                    end,

                    gui.Label{
                        bgimage = true,
                        bgcolor = "black",
                        bold = true,
                        fontSize = 9,
                        hpad = 1,
                        vpad = 1,
                        borderWidth = 1,
                        borderColor = Styles.textColor,
                        halign = "center",
                        valign = "bottom",
                        width = "auto",
                        height = "auto",
                        text = "Surges",
                        y = 7,
                    },


                    refreshCharacter = function(element, token)
                        local creature = token.properties
                        local resources = creature:GetAvailableSurges()
                        element.text = tostring(resources)
                    end,

                    change = function(element)
                        local amount = tonumber(element.text)
                        if amount == nil then
                            element:FireEvent("refreshCharacter", m_token)
                            return
                        end

                        amount = math.max(0, round(amount))

                        local diff = amount - m_token.properties:GetAvailableSurges()
                        if diff == 0 then
                            element:FireEvent("refreshCharacter", m_token)
                            return
                        end
                        m_token:ModifyProperties{
                            description = "Change Surges",
                            execute = function()
                                m_token.properties:ConsumeSurges(-diff, "Manually Set")
                            end,
                        }

                        element:FireEvent("refreshCharacter", m_token)
                    end,
                },

            }
        },

		gui.Panel{
			y = 19,
			width = 34,
			height = 34,
			halign = "center",
			valign = "bottom",
			flow = "none",

			refreshCharacter = function(element, token)
				m_token = token
				element:SetClass("hidden", token == nil or (not token.valid) or token.properties == nil or token.properties.typeName ~= "character")
			end,

			gui.Panel{
				rotate = 45,
				width = "100%",
				height = "100%",
				bgimage = true,
				bgcolor = "black",
				x = -3,
				borderColor = Styles.textColor,
				borderWidth = 2,
			},

			gui.Label{
				fontSize = 22,
                textWrap = false,
				bold = true,
				color = Styles.textColor,
				halign = "center",
				valign = "center",
				characterLimit = 2,
				editable = true,
				width = "100%",
				height = "auto",
				textAlignment = "center",

				hover = gui.Tooltip("Victories"),

				refreshCharacter = function(element, token)
					if element.parent:HasClass("hidden") then
						return
					end

                    element.text = tostring(token.properties:GetVictories())
				end,

                change = function(element)
                    local n = tonumber(element.text)
					if n ~= nil and round(n) == n then
						m_token:BeginChanges()
						m_token.properties:SetVictories(n)
						m_token:CompleteChanges("Set Victories")
					end
					element.text = string.format("%d", m_token.properties:GetVictories())
				end,
			}

		}
	}
end
]==]

local multiEditBaseFunction = CharacterPanel.CreateMultiEdit

--- Build the multi-token edit panel. A theme reactivity root.
--- @return Panel
CharacterPanel.CreateMultiEdit = function()
	if mod.unloaded then
		return multiEditBaseFunction()
	end

	return RegisterRoot(TacPanel.MultiEdit())
end

--- Populate `element` with the party's member panes, grouped by folder.
--- @param element Panel Container to fill
--- @param party any The party object
--- @param partyMembers string[] Character ids
--- @param memberPanes table<string, Panel> Reusable panes keyed by charid
CharacterPanel.PopulatePartyMembers = function(element, party, partyMembers, memberPanes)

	local m_folderPanels = element.data.folderPanels or {}
	element.data.folderPanels = m_folderPanels

	local newFolderPanels = {}

	local children = {}
	local newMemberPanes = {}

	for _,charid in ipairs(partyMembers) do

		local token = dmhub.GetCharacterById(charid)
		local creature = token.properties

		if creature ~= nil then
			local key = charid

			local folder = nil
			local squadid = creature:MinionSquad()

			if type(squadid) == "string" then
				key = squadid .. '-' .. charid

				folder = newFolderPanels[squadid]

				if folder == nil then

					folder = m_folderPanels[squadid]
					if folder == nil then
						local contentPanel = gui.Panel{
							width = "100%",
							height = "auto",
							flow = "vertical",
							halign = "center",
							vmargin = 4,
							hmargin = 4,
						}

						folder = gui.TreeNode{
							text = squadid,
							contentPanel = contentPanel,
							width = "100%-10",
							halign = "left",
							lmargin = 8,
							expanded = true,
							clickHeader = function(element)
								element:FireEventOnParents("ClearCharacterPanelSelection")
								local setFocus = false
								for _,p in ipairs(folder.data.children) do
									if not setFocus then
										gui.SetFocus(p)
										setFocus = true
									else
										element:FireEventOnParents("AddCharacterPanelToSelection", p)
									end
								end
							end,
						}

						local labels = folder:GetChildrenWithClassRecursive("folderLabel")
						for _,label in ipairs(labels) do
							label:SetClass("folderLabel", false)
							label:SetClass("bestiaryLabel", true)
						end

						folder.data.contentPanel = contentPanel
					end

					newFolderPanels[squadid] = folder

					--first time seeing this folder this refresh so re-init children.
					folder.data.children = {}
				end


			end

			local child = memberPanes[key] or CharacterPanel.CreateCharacterEntry(charid)
			newMemberPanes[key] = child
			child:FireEventTree("prepareRefresh")

			if folder ~= nil then
				folder.data.children[#folder.data.children+1] = child
			else
				children[#children+1] = child
			end
		end
	end

	table.sort(children, function(a,b)
		local aname = a.data.token.playerNameOrNil
		local bname = b.data.token.playerNameOrNil
		if aname == nil and bname == nil then
			return a.data.token.description < b.data.token.description
		end

		if aname == nil then
			return false
		end

		if bname == nil then
			return true
		end

		if aname == bname then
			return cond(a.data.primaryCharacter, 0, 1) < cond(b.data.primaryCharacter, 0, 1)
		end

		return aname < bname

	end)

	local folderChildren = {}
	for squadid,folder in pairs(newFolderPanels) do
		local newChildren = folder.data.children
		table.sort(newChildren, function(a,b)
			return a.data.token.description < b.data.token.description
		end)

		folder.data.contentPanel.children = newChildren
		folder.data.ord = squadid

		folderChildren[#folderChildren+1] = folder
	end

	for _,folder in ipairs(folderChildren) do
		children[#children+1] = folder
	end

	element.children = children

	element.data.folderPanels = newFolderPanels

	return newMemberPanes
end

--important attributes beyond characteristics
--e.g. things like stability etc.

--- Build the compact side-panel display for one token (Summary + Stamina). A
--- theme reactivity root.
--- @param token CharacterToken
--- @return Panel
function CharacterPanel.SingleCharacterDisplaySidePanel(token)

	local characterDisplaySidebar

	local conditionsPanel = CharacterPanel.CreateConditionsPanel(token)

	characterDisplaySidebar = gui.Panel{
		id = 'sidebar',
		styles = TacPanel.AllStyles(),

		width = "auto",
		height = "auto",
		halign = "left",
		flow = "vertical",

		events = {
			refresh = function(element)
				if token == nil or not token.valid then
					return
				end

				element.data.displayedProperties = token.properties
				element.data.hasInit = true

				characterDisplaySidebar:FireEventTree('refreshCharacter', token)

			end,

			setToken = function(element, tok)
				token = tok
				element.data.token = token
			end,
		},

		data = {
			token = token,
			hasInit = false,
			displayedProperties = nil,
		},

        TacPanel.Summary(),
        TacPanel.Stamina(),
	}

	return RegisterRoot(characterDisplaySidebar)
end
