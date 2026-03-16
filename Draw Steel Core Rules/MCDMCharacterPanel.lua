local mod = dmhub.GetModLoading()

setting{
    id = "newTacPanel",
    description = "Use the new tactical panel",
    editor = "check",
    default = false,
    storage = "preference",
    section = "game",
}

local PLACEHOLDER_TOKEN = "game-icons/griffin-symbol.png"

local g_refreshChecklistName = {
    encounter = "encounter",
    round = "round",
}

-- Commonly used colors
local GRAY02 = "#666663"
local RICH_BLACK = "#040807"
local PANEL = "#0b0f0d"
local GOLD = "#966D4B"
local GOLD_LIGHT = "#C49A5A"
local GOLD_DARK_BG = "#140d00"
local GOLD_BORDER = "#5C3D10"
local GOLD_BORDER02 = "#3F2E1F"
local CREAM = "#FFFEF8"
local MUTED = "#8A8474"
local DIM = "#B4D1C6"
local DIMMER = "#758B7D"
local TEAL = "#009C7D"
local TEAL_HEAL = "#2D6A4F"
local RED = "#D53031"
local RULE = "#1A2420"
local DYING_FILL = "#6B2020"
local WINDED_FILL = "#7A4A18"
local HEALTHY_FILL = "#2D6A4F"
local SURGE_BORDER = "#2E3F38"
local DARKRED = "#140A0A"
local TEMP_STAM = "#8B5CF6"
local MOVE_HINDERED = "#E07070"
local CHARACTERISTIC_BG = "#0B0F0D"

local TacPanel = {}
local TacPanelSizes = {}
local TacPanelStyles = {}

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
    panelTitle = 14,
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

    movePanelTitle = 14,
    movePanelValue = 24,

    charTitle = 12,
    charValue = 30,

    hrChipValue = 14,
    hrChipEvent = 12,
    hrChipFreq = 12,
    growHRTitle = 14,
    grValue = 16,
    grText = 14,

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

TacPanelStyles.TacPanel = {
    {   -- Outer tac panel. Applies margin, padding, alignment, bottom border.
        selectors = {"panel", "tacpanel"},
        width = "98%",
        height = "auto",
        halign = "left",
        valign = "top",
        hpad = 4,
        vpad = 8,
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = RICH_BLACK,
        borderColor = GRAY02,
        border = { x1 = 0, y1 = 1, x2 = 0, y2 = 0 },
    },
    {
        selectors = {"panel", "tacpanel", "alt-bg"},
        bgcolor = PANEL,
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
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.panelTitle,
        color = DIM,
    },
    -- Collapsible title bar
    { selectors = {"panel", "tp-title-bar"},
      width = "100%", height = "auto",
      halign = "left", valign = "top",
      flow = "horizontal", vpad = 2 },
    -- Collapse arrow
    { selectors = {"tp-expando"},
      hmargin = 8, halign = "right", valign = "center",
      color = DIM },
}
TacPanelStyles.Tooltip = {
    {
        selectors = {"tacpanel-tooltip"},
        bgimage = "panels/square.png",
        bgcolor = "black",
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
TacPanelStyles.Portrait = {
    {
        selectors = {"panel", "portrait-frame"},
        bgimage = "panels/square.png",
        height = TacPanelSizes.Portrait.height,
        width = string.format("%f%% height", Styles.portraitWidthPercentOfHeight),
        valign = "top",
        halign = "left",
        lmargin = 4,
        bgcolor = "white",
        borderColor = GRAY02,
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
TacPanelStyles.SummaryInfo = {
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
        fontFace = "Newzald",
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
    },
    {
        selectors = {"label", "summary-info", "char-name"},
        fontSize = TacPanelSizes.Fonts.charName,
        color = CREAM,
    },
    {
        selectors = {"label", "summary-info", "level"},
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.charLevel,
        color = DIM,
    },
    {
        selectors = {"label", "summary-info", "class"},
        fontSize = TacPanelSizes.Fonts.charClass,
        color = GOLD,
    },
    {
        selectors = {"label", "summary-info", "subclass"},
        fontSize = TacPanelSizes.Fonts.charSubclass,
        color = MUTED,
    },

    -- Control buttons below portrait
    {
        selectors = {"vision-btn"},
        halign = "left",
        valign = "top",
        pad = 4,
        border = 1,
        cornerRadius = 4,
        borderColor = GRAY02,
    },
    {
        selectors = {"vision-btn", "on"},
        bgcolor = TEAL,
    },
    {
        selectors = {"vision-btn", "hover"},
        brightness = 1.5,
        transitionTime = 0.2,
    },
    {
        selectors = {"vision-btn", "press"},
        brightness = 0.5,
    },
}
TacPanelStyles.TokenBox = {
    {
        selectors = {"panel", "tokenbox"},
        height = (TacPanelSizes.Portrait.height / 2) - 2,
        width = 100,
        valign = "top",
        halign = "left",
        bmargin = 4,
        bgimage = "panels/square.png",
        bgcolor = "clear",
        borderColor = GRAY02,
        borderWidth = 2,
        cornerRadius = 6,
        flow = "vertical",
    },
    {
        selectors = {"panel", "tokenbox", "hero-tokens"},
        borderColor = GOLD_BORDER,
    },
    {
        selectors = {"panel", "tokenbox", "surges"},
        borderColor = SURGE_BORDER,
    },
    {
        selectors = {"panel", "tokenbox", "victories"},
        borderColor = SURGE_BORDER,
    },
    {
        selectors = {"panel", "tokenbox", "heroic-resources"},
        borderColor = GOLD_BORDER,
        bgcolor = GOLD_DARK_BG,
    },
    {
        selectors = {"label", "tokenbox"},
        color = Styles.textColor,
    },
    {
        selectors = {"label", "tokenbox", "title"},
        width = "98%",
        height = "auto",
        valign = "top",
        halign = "center",
        vmargin = 4,
        fontFace = "Berling",
        fontSize = 12,
        textAlignment = "center",
    },
    {
        selectors = {"label", "tokenbox", "title", "hero-tokens"},
        color = GOLD,
    },
    {
        selectors = {"label", "tokenbox", "title", "surges"},
        color = MUTED,
    },
    {
        selectors = {"label", "tokenbox", "title", "victories"},
        color = MUTED,
    },
    {
        selectors = {"label", "tokenbox", "title", "heroic-resources"},
        color = GOLD,
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
        bgimage = PLACEHOLDER_TOKEN,
        bgcolor = GOLD,
    },
    {
        selectors = {"panel", "icon", "victories"},
        bgimage = PLACEHOLDER_TOKEN,
    },
    {
        selectors = {"panel", "icon", "heroic-resources"},
        bgimage = PLACEHOLDER_TOKEN,
        bgcolor = GOLD,
    },
    {
        selectors = {"label", "tokenbox", "value"},
        width = "auto",
        height = "auto",
        valign = "top",
        hmargin = 6,
        fontFace = "Newzald",
        fontSize = 30,
    },
    {
        selectors = {"label", "tokenbox", "value", "hero-tokens"},
        color = GOLD,
    },
    {
        selectors = {"label", "tokenbox", "value", "heroic-resources"},
        color = GOLD,
    },
    {
        selectors = {"refresh-icon"},
        halign = "right",
        valign = "bottom",
        hmargin = 6,
        vmargin = 6,
    }
}
TacPanelStyles.Stamina = {
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
        borderColor = RED,
        bgcolor = DARKRED,
    },
    {
        selectors = {"panel", "stamina-box", "stamina"},
        width = TacPanelSizes.Panels.stamBoxStam,
        borderColor = TEAL_HEAL,
        bgcolor = TEAL_HEAL .. "0F",
    },
    {
        selectors = {"panel", "stamina-box", "heal"},
        borderColor = TEAL_HEAL,
        bgcolor = TEAL_HEAL .. "0F",
    },
    {
        selectors = {"panel", "stamina-box", "recoveries"},
        width = TacPanelSizes.Panels.stamBoxRecoveries,
        borderColor = TEAL_HEAL,
        bgcolor = TEAL_HEAL .. "0F",
    },
    {
        selectors = {"panel", "stamina-box", "temp"},
        borderColor = TEMP_STAM,
        bgcolor = TEMP_STAM .. "0F",
    },
    {
        selectors = {"label", "stambox-title"},
        width = "98%",
        height = "auto",
        valign = "top",
        halign = "center",
        textAlignment = "center",
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.stamBoxTitle,
        color = CREAM,
    },
    {
        selectors = {"label", "stambox-title", "harm"},
        -- color = RED,
    },
    {
        selectors = {"label", "stambox-title", "heal"},
        -- color = TEAL_HEAL,
    },
    {
        selectors = {"label", "stambox-title", "temp"},
        fontSize = TacPanelSizes.Fonts.stamBoxTitle - 1,
        -- color = TEMP_STAM,
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
        fontFace = "Newzald",
        textAlignment = "center",
        fontSize = TacPanelSizes.Fonts.stamBoxInput,
    },
    {
        selectors = {"stambox-input", "harm"},
        color = RED,
    },
    {
        selectors = {"stambox-input", "heal"},
        color = TEAL_HEAL,
    },
    {
        selectors = {"stambox-input", "temp"},
        color = TEMP_STAM,
        fontFace = "DrawSteelGlyphs",
    },
    {
        selectors = {"stambox-input", "temp", "focus"},
        fontFace = "Newzald",
        color = CREAM,
    },
    {
        selectors = {"label", "stambox-stam", "current"},
        height = "auto",
        width = "auto",
        valign = "center",
        halign = "left",
        fontFace = "Newzald",
        fontSize = TacPanelSizes.Fonts.currentStam,
        color = CREAM,
    },
    {
        selectors = {"label", "stambox-stam", "max"},
        height = "auto",
        width = "auto",
        valign = "center",
        lmargin = 4,
        fontFace = "Newzald",
        fontSize = TacPanelSizes.Fonts.maxStamina,
        color = DIMMER,
    },
    {
        selectors = {"label", "recovery-value"},
        width = "auto",
        height = "auto",
        valign = "center",
        halign = "center",
        textAlignment = "center",
        fontFace = "Newzald",
        fontSize = TacPanelSizes.Fonts.recoveryValue,
        color = HEALTHY_FILL,
    },
    {
        selectors = {"label", "recovery-value", "hover"},
        brightness = 1.5,
    },
    {
        selectors = {"label", "recovery-count"},
        width = "auto",
        height = "auto",
        valign = "top",
        halign = "left",
        textAlignment = "left",
        fontFace = "Newzald",
        fontSize = TacPanelSizes.Fonts.recoveryCount,
        color = HEALTHY_FILL,
    },
    {
        selectors = {"label", "recovery-max"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        lmargin = 4,
        textAlignment = "left",
        fontFace = "Newzald",
        fontSize = TacPanelSizes.Fonts.recoveryCount,
        color = DIMMER,
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
        width = 5,
        height = 5,
        hmargin = 1,
        valign = "center",
        bgimage = "panels/square.png",
        borderWidth = 1,
        borderColor = HEALTHY_FILL,
    },
    {
        selectors = {"recovery-pip", "filled"},
        bgcolor = HEALTHY_FILL,
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
        bgimage = "panels/square.png",
        bgcolor = "clear",
        borderWidth = 1,
        flow = "none",
    },
    {
        selectors = {"panel", "health-segment", "dying"},
        borderColor = DYING_FILL,
    },
    {
        selectors = {"panel", "health-segment", "winded"},
        borderColor = WINDED_FILL,
    },
    {
        selectors = {"panel", "health-segment", "healthy"},
        borderColor = HEALTHY_FILL,
    },
    {   -- The fill panel inside each segment (left-aligned, height 100%)
        selectors = {"panel", "health-fill"},
        height = "100%",
        halign = "left",
        bgimage = "panels/square.png",
    },
    {
        selectors = {"panel", "health-fill", "dying"},
        bgcolor = DYING_FILL,
    },
    {
        selectors = {"panel", "health-fill", "winded"},
        bgcolor = WINDED_FILL,
    },
    {
        selectors = {"panel", "health-fill", "healthy"},
        bgcolor = HEALTHY_FILL,
    },
    {   -- White separator on right edge of dying and winded segments
        selectors = {"panel", "health-separator"},
        width = TacPanelSizes.HealthBar.separatorWidth,
        height = "100%",
        halign = "right",
        bgimage = "panels/square.png",
        bgcolor = "white",
    },
    {   -- Diamond positioner: floating panel whose width% positions the diamond
        selectors = {"panel", "health-diamond-positioner"},
        height = TacPanelSizes.HealthBar.segmentHeight,
        halign = "left",
        valign = "top",
        flow = "none",
    },
    {   -- The diamond itself: rotated square, offset by half its size
        selectors = {"panel", "health-diamond"},
        width = TacPanelSizes.HealthBar.diamondSize,
        height = TacPanelSizes.HealthBar.diamondSize,
        halign = "right",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "white",
        x = TacPanelSizes.HealthBar.diamondSize / 2,
    },
    {
        selectors = {"panel", "health-diamond", "has-temp"},
        bgcolor = TEMP_STAM,
    },
    {   -- Status box base: outlined box with transparent fill, centered label
        selectors = {"panel", "health-status"},
        width = "100%",
        height = TacPanelSizes.HealthBar.statusBoxHeight,
        tmargin = TacPanelSizes.HealthBar.statusBoxMargin,
        bgimage = "panels/square.png",
        borderWidth = 1,
        halign = "left",
        valign = "top",
    },
    {
        selectors = {"panel", "health-status", "winded"},
        borderColor = WINDED_FILL,
        bgcolor = WINDED_FILL .. "0F",
    },
    {
        selectors = {"panel", "health-status", "dying"},
        borderColor = DYING_FILL,
        bgcolor = DYING_FILL .. "0F",
    },
    {   -- Status label inside the box
        selectors = {"label", "health-status-label"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.stamBoxTitle,
    },
    {
        selectors = {"label", "health-status-label", "winded"},
        color = WINDED_FILL,
    },
    {
        selectors = {"label", "health-status-label", "dying"},
        color = DYING_FILL,
    },
    {   -- Temp stam box: horizontal layout, TEMP_STAM colors
        selectors = {"panel", "health-status", "temp"},
        borderColor = TEMP_STAM,
        bgcolor = TEMP_STAM .. "0F",
        flow = "horizontal",
    },
    {   -- Temp HP value (Newzald 12pt white)
        selectors = {"label", "temp-stam-value"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 6,
        fontFace = "Newzald",
        fontSize = TacPanelSizes.Fonts.tempStamValue,
        color = CREAM,
    },
    {   -- "TEMP" descriptor (Berling 10pt, border color)
        selectors = {"label", "temp-stam-label"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 4,
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.tempStamLabel,
        color = TEMP_STAM,
    },
    {   -- Clear button: small square, black bg, purple border
        selectors = {"panel", "temp-stam-clear"},
        width = TacPanelSizes.HealthBar.clearBtnSize,
        height = TacPanelSizes.HealthBar.clearBtnSize,
        halign = "right",
        valign = "center",
        hmargin = 2,
        bgimage = "panels/square.png",
        bgcolor = "black",
        borderWidth = 1,
        borderColor = TEMP_STAM,
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
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.tempStamClear,
        color = TEMP_STAM,
    },
}
TacPanelStyles.CharacteristicsPanel = {
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
        bgcolor = CHARACTERISTIC_BG,
        borderColor = RULE,
        border = 1,
        cornerRadius = 4,
    },
    {
        selectors = {"panel", "characteristic-box", "hover"},
        brightness = 1.5,
    },
    {
        selectors = {"label", "char-title"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 2,
        color = MUTED,
        fontFace = "Berling",
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
        tmargin = 4,
        color = MUTED,
        fontFace = "Newzald",
        fontSize = TacPanelSizes.Fonts.charValue,
    },
    {
        selectors = {"label", "char-value", "positive"},
        color = TEAL,
    },
    {
        selectors = {"label", "char-value", "negative"},
        color = RED,
    }
}
TacPanelStyles.MovementPanel = {
    {
        selectors = {"panel", "movement-panel"},
        height = "auto",
        width = "100%",
        valign = "top",
        halign = "left",
        flow = "horizontal",
        vpad = 6,
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
        color = MUTED,
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.movePanelTitle,
        textAlignment = "center",
    },
    {
        selectors = {"label", "movebox-value"},
        width = "auto",
        height = "auto",
        valign = "center",
        halign = "center",
        fontFace = "Newzald",
        color = "white",
        fontSize = TacPanelSizes.Fonts.movePanelValue,
    },
    {
        selectors = {"label", "movebox-value", "restricted"},
        color = DIMMER,
        strikethrough = true,
    },
    {
        selectors = {"label", "movebox-value", "hindered"},
        lmargin = 4,
        color = MOVE_HINDERED,
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
        bgimage = "panels/square.png",
        width = 16,
        height = 12,
        fontSize = 10,
        bold = true,
        textAlignment = "center",
        cornerRadius = 2,
        borderWidth = 1,
        bgcolor = "#ffffff22",
        borderColor = GRAY02,
        color = "white",
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
TacPanelStyles.HeroicResources = {
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
        vpad = 3,
        hpad = 6,
        flow = "horizontal",
        bgimage = true,
        border = 1,
        borderColor = GOLD,
        cornerRadius = 4,
        bgcolor = GOLD .. "0F",
    },
    {
        selectors = {"panel", "hr-chip", "completed"},
        bgcolor = DIMMER .. "0F",
        borderColor = DIM,
    },
    {
        selectors = {"label", "hr-chip-value"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        fontFace = "Newzald",
        fontSize = TacPanelSizes.Fonts.hrChipValue,
        color = GOLD,
    },
    {
        selectors = {"label", "hr-chip-value", "parent:completed"},
        strikethrough = true,
        color = DIM,
    },
    {
        selectors = {"label", "hr-chip-event"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        hmargin = 4,
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.hrChipEvent,
        color = GOLD_LIGHT,
    },
    {
        selectors = {"label", "hr-chip-event", "parent:completed"},
        strikethrough = true,
        color = DIM,
    },
    {
        selectors = {"label", "hr-chip-freq"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        hmargin = 4,
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.hrChipFreq,
        color = DIMMER,
    },
    {
        selectors = {"panel", "growing-resources"},
        width = "100%-8",
        height = "auto",
        halign = "center",
        valign = "top",
        flow = "vertical",
        bgimage = "panels/square.png",
        border = 1,
        borderColor = DIMMER,
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
        bgcolor = GOLD .. "0F",
        borderColor = GOLD,
        border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},
    },
    {
        selectors = {"label", "gr-title"},
        width = "auto",
        height = "auto",
        halign = "left",
        lmargin = 8,
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.growHRTitle,
        color = GOLD_LIGHT,
        bold = true,
    },
    {
        selectors = {"gr-expando"},
        hmargin = 8,
        halign = "right",
        valign = "center",
        bgcolor = DIM,
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
        borderColor = DIMMER,
        border = {x1 = 0, x2 = 0, y1 = 0, y2 = 1},
    },
    {
        selectors = {"panel", "gr-row", "available"},
        bgcolor = GOLD_LIGHT .. "0F"
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
        fontFace = "Newzald",
        fontSize = TacPanelSizes.Fonts.grValue,
        bold = true,
        color = DIM,
        bgimage = true,
        border = 1,
        borderColor = DIMMER,
        bgcolor = DIMMER .. "0F",
        cornerRadius = {x1 = 0, x2 = 0, y1 = 4, y2 = 4},
    },
    {
        selectors = {"label", "gr-value", "parent:available"},
        color = GOLD,
        borderColor = GOLD,
        bgcolor = GOLD .. "0F",
    },
    {
        selectors = {"label", "gr-text"},
        width = "84%",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 4,
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.grText,
        textWrap = true,
        color = DIM,
    },
    {
        selectors = {"label", "gr-text", "parent:available"},
        color = GOLD_LIGHT,
    }
}
TacPanelStyles.SkillsLanguages = {
    {
        selectors = {"label", "skillslangs"},
        width = "94%",
        height = "auto",
        halign = "left",
        valign = "top",
        tmargin = 4,
        lmargin = 6,
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.skillsLangs,
        color = CREAM,
    },
}
TacPanelStyles.Notes = {
    -- Individual note label (markdown, same pattern as skillslangs)
    { selectors = {"label", "note-entry"},
      width = "94%", height = "auto",
      halign = "left", valign = "top",
      tmargin = 4, lmargin = 6,
      fontFace = "Berling",
      fontSize = TacPanelSizes.Fonts.skillsLangs,
      color = CREAM },
}
TacPanelStyles.MultiEdit = {
    -- Row containers
    { selectors = {"panel", "me-actions"},
      width = "100%", height = "auto",
      flow = "horizontal", halign = "center", tmargin = 4 },
    { selectors = {"panel", "me-icon-row"},
      width = "auto", height = "auto",
      flow = "horizontal", halign = "left", lmargin = 6, tmargin = 4 },

    -- Heal/Damage input boxes
    { selectors = {"panel", "me-input-box"},
      width = "30%", height = 28, halign = "center", valign = "center",
      bgimage = "panels/square.png",
      border = 1, cornerRadius = 4, hmargin = 2 },
    { selectors = {"panel", "me-input-box", "heal"},
      bgcolor = TEAL_HEAL .. "1A", borderColor = TEAL_HEAL },
    { selectors = {"panel", "me-input-box", "damage"},
      bgcolor = RED .. "1A", borderColor = RED },
    { selectors = {"input", "me-input"},
      width = "100%", height = "100%",
      bgcolor = "clear", borderWidth = 0, borderColor = "clear",
      pad = 0, margin = 0,
      fontFace = "Berling", fontSize = 12, color = CREAM,
      bold = true, textAlignment = "center" },

    -- Add Condition button
    { selectors = {"panel", "me-condition-btn"},
      width = "30%", height = 28, halign = "center", valign = "center",
      bgimage = "panels/square.png",
      bgcolor = DIM .. "1A", border = 1, borderColor = DIM,
      cornerRadius = 4, hmargin = 2 },
    { selectors = {"panel", "me-condition-btn", "hover"},
      brightness = 1.3, transitionTime = 0.2 },
    { selectors = {"label", "me-condition-btn"},
      width = "100%", height = "100%",
      halign = "center", valign = "center", textAlignment = "center",
      fontFace = "Berling", fontSize = 12, color = CREAM, bold = true },

    -- Icon button outline wrapper
    { selectors = {"panel", "me-icon-wrap"},
      width = "auto", height = "auto",
      halign = "left", valign = "top",
      lmargin = 4, pad = 4,
      bgimage = true, bgcolor = "clear",
      border = 1, borderColor = DIMMER, cornerRadius = 4 },

    -- Squad chip
    { selectors = {"panel", "me-squad-row"},
      width = "auto", height = 28,
      halign = "left", flow = "horizontal",
      tmargin = 4, lmargin = 6, hpad = 6, vpad = 3,
      bgimage = "panels/square.png",
      bgcolor = DIMMER .. "0F", border = 1, borderColor = DIMMER,
      cornerRadius = 4 },
    { selectors = {"label", "me-squad-label"},
      width = "auto", height = "auto", valign = "center",
      fontFace = "Berling", fontSize = 12, color = MUTED },

    -- EDS chip
    { selectors = {"panel", "me-eds-chip"},
      width = "auto", height = 28,
      halign = "left", flow = "horizontal",
      hpad = 6, vpad = 3,
      bgimage = "panels/square.png",
      bgcolor = DIMMER .. "0F", border = 1, borderColor = DIMMER,
      cornerRadius = 4 },
    { selectors = {"label", "me-eds-label"},
      width = "auto", height = "auto", valign = "center",
      fontFace = "Berling", fontSize = 12, color = MUTED },
    { selectors = {"label", "me-eds-input"},
      width = 50, height = "auto", valign = "center",
      fontFace = "Berling", fontSize = 12, color = CREAM },

    -- EV result chip
    { selectors = {"panel", "me-ev-chip"},
      width = "auto", height = 28,
      halign = "left", flow = "horizontal",
      lmargin = 4, hpad = 6, vpad = 3,
      bgimage = "panels/square.png",
      bgcolor = DIMMER .. "0F", border = 1, borderColor = DIMMER,
      cornerRadius = 4 },
    { selectors = {"label", "me-ev-result"},
      width = "auto", height = "auto", valign = "center",
      fontFace = "Berling", fontSize = 12, color = CREAM },
}
TacPanelStyles.Routines = {
    -- Container for routine chips
    { selectors = {"panel", "rt-container"},
      width = "100%", height = "auto",
      flow = "horizontal", halign = "left" },

    -- Routine chip (unselected = dim)
    { selectors = {"panel", "rt-chip"},
      width = "auto", height = 28,
      flow = "horizontal", hpad = 8, vpad = 3,
      bgimage = "panels/square.png",
      bgcolor = DIMMER .. "0F", border = 1, borderColor = DIMMER,
      cornerRadius = 4, lmargin = 6, tmargin = 4 },
    { selectors = {"panel", "rt-chip", "hover"},
      brightness = 1.3, transitionTime = 0.2 },
    { selectors = {"panel", "rt-chip", "selected"},
      bgcolor = GOLD .. "1A", borderColor = GOLD },

    -- Routine chip label
    { selectors = {"label", "rt-chip"},
      width = "auto", height = "auto", valign = "center",
      fontFace = "Berling", fontSize = 12, color = MUTED },
    { selectors = {"label", "rt-chip", "selected"},
      color = GOLD_LIGHT },
}
TacPanelStyles.Conditions = {
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
        borderColor = GOLD,
        bgcolor = GOLD .. "0F",
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
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.condName,
        color = CREAM,
    },
    {   -- Set caster button
        selectors = {"panel", "cond-setCaster"},
        height = 14,
        width = 14,
        halign = "left",
        valign = "center",
        lmargin = 4,
        bgimage = true,
        border = 1,
        borderColor = GOLD,
        color = GOLD,
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
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.condSetCaster,
        color = MUTED,
    },
    {   -- X remove button - hidden until parent hovered
        selectors = {"panel", "cond-remove"},
        width = 14,
        height = 14,
        halign = "left",
        valign = "center",
        lmargin = 4,
        bgimage = true,
        bgcolor = RED .. "0F",
        border = 1,
        borderColor = RED,
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
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.condRemove,
        color = RED,
    },
    {   -- Add condition button
        selectors = {"panel", "cond-add"},
        width = 22,
        height = 22,
        halign = "left",
        valign = "center",
        margin = 2,
        bgimage = true,
        bgcolor = "clear",
        border = 1,
        borderColor = DIM,
        cornerRadius = 4,
    },
    {
        selectors = {"panel", "cond-add", "hover"},
        brightness = 1.5,
        transitionTime = 0.2,
    },
    {
        selectors = {"label", "cond-add"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.condAdd,
        color = DIM,
    },
    {   -- "No conditions" placeholder
        selectors = {"label", "cond-empty"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        lmargin = 8,
        fontFace = "Berling",
        fontSize = 16,
        color = DIM,
        bold = false,
        italics = true,
    },
    {   -- Custom condition input
        selectors = {"input", "cond-custom-input"},
        width = "94%",
        height = "auto",
        halign = "left",
        lmargin = 6,
        tmargin = 6,
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.condInput,
        color = CREAM,
        border = 1,
        borderColor = DIM,
        cornerRadius = 4,
        hpad = 6,
        vpad = 4,
    },
}
TacPanelStyles.AddConditionMenu = {
    {   -- Section headings
        selectors = {"label", "menu-heading"},
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.menuTitle,
        color = DIM,
        tmargin = 8,
        bmargin = 4,
        lmargin = 8,
    },
    {   -- Condition/effect option row
        selectors = {"label", "menu-option"},
        width = "95%",
        height = 24,
        halign = "center",
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.menuOption,
        color = CREAM,
        bgcolor = "clear",
        bgimage = "panels/square.png",
        cornerRadius = 4,
        hpad = 6,
    },
    {
        selectors = {"label", "menu-option", "hover"},
        bgcolor = GOLD_BORDER,
        brightness = 1.2,
        transitionTime = 0.15,
    },
    {
        selectors = {"label", "menu-option", "searched"},
        bgcolor = GOLD_BORDER,
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
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.menuSuboption,
        textAlignment = "center",
        color = CREAM,
        bgimage = true,
        bgcolor = "clear",
        border = 1,
        borderColor = GOLD_BORDER,
        cornerRadius = 8,
        hpad = 6,
        lmargin = 4,
    },
    {
        selectors = {"label", "menu-suboption", "hover"},
        bgcolor = GOLD_BORDER,
        brightness = 1.2,
        transitionTime = 0.15,
    },
    {
        selectors = {"label", "menu-suboption", "press"},
        brightness = 1.4,
    },
    {   -- Search input
        selectors = {"input", "menu-search"},
        width = "90%",
        height = "auto",
        halign = "center",
        fontFace = "Berling",
        fontSize = TacPanelSizes.Fonts.menuSearch,
        color = CREAM,
        border = 1,
        borderColor = DIM,
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
        bgimage = "panels/square.png",
        bgcolor = DIM,
        vmargin = 6,
    },
}
TacPanelStyles.Resistances = {
    -- Container: side-by-side
    { selectors = {"panel", "res-container"},
      width = "100%", height = "auto", flow = "horizontal",
      halign = "center", tmargin = 4 },

    -- Weakness box
    { selectors = {"label", "res-box", "weakness"},
      width = "47%", height = "auto", halign = "center",
      fontFace = "Berling", fontSize = TacPanelSizes.Fonts.resEntry,
      bold = true, color = RED, bgimage = "panels/square.png",
      bgcolor = RED .. "04", border = 1, borderColor = RED,
      cornerRadius = 4, hpad = 6, vpad = 4, hmargin = 4 },

    -- Immunity box
    { selectors = {"label", "res-box", "immunity"},
      width = "47%", height = "auto", halign = "center",
      fontFace = "Berling", fontSize = TacPanelSizes.Fonts.resEntry,
      bold = true, color = TEAL, bgimage = "panels/square.png",
      bgcolor = TEAL_HEAL .. "04", border = 1, borderColor = TEAL_HEAL,
      cornerRadius = 4, hpad = 6, vpad = 4, hmargin = 4 },
}

-- Big text
local HERO_TOKEN_TOOLTIP = [[**Hero Tokens**
* You can spend a hero token to gain two surges.
* You can spend a hero token when you fail a saving throw to succeed instead.
* You can reroll the result of a test. You must use the new result.
* You can spend 2 hero tokens to regain Stamina equal to your Recovery value without spending a Recovery.
]]

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

local function GenerateCustomAttributeCalculationTooltip(tokenInfo, name)
    return GenerateAttributeCalculationTooltip(tokenInfo, name,
        function(c) return c:BaseNamedCustomAttribute(name) end,
        function(c) return c:DescribeModificationsToNamedCustomAttribute(name) end)
end

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

--- display the portrait
--- @return Panel
function TacPanel.Portrait()
    return gui.Panel{
        styles = TacPanelStyles.Portrait,
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

                if portrait ~= token.portrait and not token.popoutPortrait then
                    element.selfStyle.imageRect = nil
                else
                    element.selfStyle.imageRect = token:GetPortraitRectForAspect(Styles.portraitWidthPercentOfHeight*0.01, portrait)
                end
            end,
        }
    }
end

--- display the hero token box
--- @return Panel
function TacPanel.HeroTokenBox()
    return gui.Panel{
        styles = TacPanelStyles.TokenBox,
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
            flow = "horizontal",
            gui.Panel{
                classes = {"icon", "hero-tokens"},
            },
            gui.Label{
                classes = {"tokenbox", "value", "hero-tokens"},
                text = "0",
                editable = true,
                numeric = true,
                characterLimit = 2,
                change = function(element)
                    local token = element.parent.parent.data.token
                    if token == nil then return end
                    local n = tonumber(element.text)
                    if n ~= nil and round(n) == n then
                        n = math.max(0, n)
                        token.properties:SetHeroTokens(n, "Set manually")
                    end
                    element.text = string.format("%d", token.properties:GetHeroTokens())
                end,
                refreshValue = function(element, token)
                    element.text = tostring(token.properties:GetHeroTokens())
                end,
            },
        },

        -- Floating: refresh button
        gui.EnhIconButton{
            classes = {"refresh-icon"},
            floating = true,
            bgimage = "icons/standard/Icon_App_Undo.png",
            color = GOLD,
            bgcolor = GOLD,
            width = 16,
            height = 16,
            press = function(element)
                local token = element.parent.data.token
                if token ~= nil then
                    local n = dmhub.GetSettingValue("numheroes")
                    token:ModifyProperties{
                        description = "Reset Hero Tokens",
                        execute = function()
                            token.properties:SetHeroTokens(n, "Session Reset")
                        end,
                    }
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
        styles = TacPanelStyles.TokenBox,
        classes = {"tokenbox", "surges", "collapsed"},
        data = { token = nil },

        linger = function(element)
            if element.data.token then
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
            gui.Label{
                classes = {"tokenbox", "value"},
                text = "0",
                editable = true,
                numeric = true,
                characterLimit = 2,
                change = function(element)
                    local token = element.parent.parent.data.token
                    if token == nil then return end
                    local amount = tonumber(element.text)
                    if amount == nil then
                        element.text = tostring(token.properties:GetAvailableSurges())
                        return
                    end
                    amount = math.max(0, round(amount))
                    local diff = amount - token.properties:GetAvailableSurges()
                    if diff ~= 0 then
                        token:ModifyProperties{
                            description = "Change Surges",
                            execute = function()
                                token.properties:ConsumeSurges(-diff, "Manually Set")
                            end,
                        }
                    end
                    element.text = tostring(token.properties:GetAvailableSurges())
                end,
                refreshValue = function(element, token)
                    local q = dmhub.initiativeQueue
                    if q == nil or q.hidden then
                        element.text = "--"
                    else
                        element.text = tostring(token.properties:GetAvailableSurges())
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
        styles = TacPanelStyles.TokenBox,
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
            gui.Label{
                classes = {"tokenbox", "value"},
                text = "0",
                editable = true,
                numeric = true,
                characterLimit = 2,
                data = { token = nil },
                refreshCharacter = function(element, token)
                    element.data.token = token
                    element.text = string.format("%d", token.properties:GetVictories())
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                change = function(element)
                    local token = element.data.token
                    if token == nil then return end
                    local n = math.max(0, round(tonumber(element.text) or 0))
                    if n ~= nil and n ~= token.properties:GetVictories() then
                        token:ModifyProperties{
                            description = "Set Victories",
                            execute = function()
                                token.properties:SetVictories(n)
                                element.text = string.format("%d", token.properties:GetVictories())
                            end,
                        }
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
        styles = TacPanelStyles.TokenBox,
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
                refreshCharacter = function(element, token)
                    local classInfo = token.properties:IsHero() and token.properties:GetClass() or nil
                    local icon = classInfo ~= nil and classInfo:try_get("heroicResourceIcon", PLACEHOLDER_TOKEN)
                    element.bgimage = icon
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
            },
            gui.Label{
                classes = {"tokenbox", "value", "heroic-resources"},
                text = "0",
                editable = true,
                numeric = true,
                characterLimit = 2,
                data = { token = nil },
                refreshCharacter = function(element, token)
                    element.data.token = token
                    local q = dmhub.initiativeQueue
                    if q == nil or q.hidden then
                        element.text = "--"
                    else
                        element.text = tostring(token.properties:GetHeroicOrMaliceResources())
                    end
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                change = function(element)
                    local token = element.data.token
                    if token == nil then return end
                    local amount = tonumber(element.text)
                    if amount == nil then
                        element:FireEvent("refreshCharacter", token)
                        return
                    end
                    local creature = token.properties
                    if not creature:IsHero() and not creature:IsCompanion() then
                        CharacterResource.SetMalice(math.max(0, amount), "Manually set")
                        return
                    end
                    local resource = dmhub.GetTable(CharacterResource.tableName)[CharacterResource.heroicResourceId]
                    amount = resource:ClampQuantity(token.properties, amount)
                    local diff = amount - token.properties:GetHeroicOrMaliceResources()
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
                    element.text = tostring(token.properties:GetHeroicOrMaliceResources())
                end,
            },
        },
    }
end

--- Display the summary section with portrait, class, levels, etc.
--- @return Panel
function TacPanel.Summary()
    local function outlineButton(btn)
        return gui.Panel{
            classes = {"container"},
            halign = "left",
            valign = "top",
            lmargin = 4,
            pad = 4,
            bgimage = true,
            bgcolor = "clear",
            border = 1,
            borderColor = DIMMER,
            cornerRadius = 4,
            btn
        }
    end

    return gui.Panel{
        styles = TacPanelStyles.TacPanel,
        classes = {"tacpanel"},
        -- Main arrangement - 3 columns
        gui.Panel{
            classes = {"container"},
            flow = "horizontal",
            
            -- Col1: Portrait
            TacPanel.Portrait(),

            -- Col2: Name etc.
            gui.Panel{
                styles = TacPanelStyles.SummaryInfo,
                classes = {"summary-info"},
                width = TacPanelSizes.Panels.summaryNames,

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

                -- Level
                gui.Label{
                    classes = {"summary-info", "level"},
                    refreshCharacter = function(element, token)
                        local level = token.properties:CharacterLevel()
                        local text = element.text
                        if level == 1 then
                            local extra = token.properties:ExtraLevelInfo()
                            local encounter = type(extra) == "table" and extra.encounter or nil
                            local mapping = {"FIRST ENCOUNTER", "SECOND ENCOUNTER", "THIRD ENCOUNTER", "FOURTH ENCOUNTER"}
                            text = mapping[encounter] or "LEVEL 1"
                        else
                            text = string.format("LEVEL %d", level)
                        end
                        element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.charLevel, 14, #text)
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

                TacPanel.HeroTokenBox(),
                TacPanel.SurgesBox(),
            }
        },
        -- Control buttons below portrait
        gui.Panel{
            classes = {"container"},
            flow = "horizontal",
            outlineButton(gui.EnhIconButton{
                classes = {"vision-btn"},
                bgimage = "panels/initiative/initiative-icon.png",
                width = TacPanelSizes.VisionBtn.size,
                height = TacPanelSizes.VisionBtn.size,
                bgcolor = RED,
                data = { token = nil },
                refreshCharacter = function(element, token)
                    element.data.token = token
                    local q = dmhub.initiativeQueue
                    if q == nil or q.hidden then
                        element.parent:SetClass("collapsed", true)
                        return
                    end
                    element.parent:SetClass("collapsed",
                        token.properties:try_get("_tmp_initiativeStatus") ~= "NonCombatant")
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                press = function(element)
                    Commands.rollinitiative()
                end,
                linger = function(element)
                    gui.Tooltip("Add to combat")(element)
                end,
            }),
            outlineButton(gui.Panel{
                classes = {"vision-btn"},
                bgimage = "icons/icon_weather/icon_weather_1.png",
                width = TacPanelSizes.VisionBtn.size,
                height = TacPanelSizes.VisionBtn.size,
                refreshCharacter = function(element, token)
                    local bgcolor = (token.properties.selectedLoadout == 1)
                        and GOLD_LIGHT
                        or GRAY02
                    element.selfStyle.bgcolor = bgcolor
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
                classes = {"vision-btn", "collapsed"},
                bgimage = "ui-icons/eye.png",
                width = TacPanelSizes.VisionBtn.size,
                height = TacPanelSizes.VisionBtn.size,
                data = { token = nil },
                monitor = "lookup",
                events = {
                    monitor = function(element)
                        local cur = dmhub.GetSettingValue("lookup")
                        element.selfStyle.bgcolor = (cur >= 1) and TEAL or DIM
                    end,
                },
                refreshCharacter = function(element, token)
                    element.data.token = token
                    if token == nil or (dmhub.isDM and dmhub.tokenVision == nil)
                        or token.countFloorsWithVisionAbove <= 0 then
                        element:SetClass("collapsed", true)
                        return
                    end
                    element:SetClass("collapsed", false)
                    local cur = dmhub.GetSettingValue("lookup")
                    element.selfStyle.bgcolor = (cur >= 1) and TEAL or DIM
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                press = function(element)
                    local cur = dmhub.GetSettingValue("lookup")
                    dmhub.SetSettingValue("lookup", (cur >= 1) and 0 or 1)
                end,
                linger = function(element)
                    local cur = dmhub.GetSettingValue("lookup")
                    local text = (cur >= 1) and "Look forward" or "Look up"
                    gui.Tooltip(text)(element)
                end,
            }),
        }
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
    local placeholder = "p"
    return gui.Panel{
        classes = {"stamina-box", "temp"},
        gui.Label{
            classes = {"stambox-title", "temp"},
            text = "TEMP",
        },
        gui.Input{
            classes = {"stambox-input", "temp"},
            text = "",
            characterLimit = 8,
            placeholderText = placeholder,
            bgimage = true,
            data = {
                token = nil,
            },
            change = function(element)
                local before = tonum(element.data.token.properties:TemporaryHitpointsStr(), 0)
                local after = tonum(element.text, 0)
                if after > before and element.data.token ~= nil and element.data.token.properties ~= nil then
                    element.data.token:ModifyProperties{
                        description = "Apply Temp Stamina",
                        execute = function()
                            element.data.token.properties:SetTemporaryHitpoints(element.text)
                            element.data.token.properties:DispatchEvent("gaintempstamina", {})
                            element.text = ""
                        end,
                    }
                end
            end,
            deselect = function(element)
                element.placeholderText = placeholder
            end,
            click = function(element)
                element.placeholderText = ""
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

--- Display the current stamina box
--- @return Panel
function TacPanel.StaminaBox()
    return gui.Panel{
        classes = {"stamina-box", "stamina"},
        halign = "center",
        valign = "center",
        data = { token = nil },

        linger = function(element)
            local token = element.data.token
            if token ~= nil and token.properties ~= nil then
                element.tooltip = gui.StatsHistoryTooltip{
                    description = "stamina",
                    entries = token.properties:GetStatHistory("stamina"):GetHistory()
                }
            end
        end,

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
            gui.Label{
                classes = {"stambox-stam", "current"},
                text = "0",
                refreshValue = function(element, token)
                    local text = tostring(token.properties:CurrentHitpoints())
                    element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.currentStamina, 3, #text)
                    element.text = text
                end,
            },
            gui.Label{
                classes = {"stambox-stam", "max"},
                text = "/ 0",
                refreshValue = function(element, token)
                    element.text = string.format("/ %d", token.properties:MaxHitpoints())
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

        gui.Panel{
            classes = {"recovery-pip-row"},
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

    return gui.Panel{
        classes = {"stamina-box", "recoveries"},
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
        gui.Label{
            classes = {"stambox-title", "heal"},
            text = "RECOVERIES",
        },
        gui.Panel{
            classes = {"container"},
            height = "100% available",
            width = "100%+8",
            valign = "top",
            halign = "left",
            hmargin = -4,
            bgimage = true,
            border = {x1 = 0, y1 = 0, x2 = 0, y2 = 1},
            borderColor = TEAL_HEAL,
            flow = "horizontal",
            gui.Panel{
                classes = {"container"},
                height = "100%+2",
                width = "40%",
                valign = "top",
                halign = "left",
                bgimage = true,
                border = {x1 = 0, y1 = 0, x2 = 1, y2 = 0},
                borderColor = TEAL_HEAL,
                gui.Label{
                    classes = {"recovery-value"},
                    text = "+0",
                    data = { token = nil },
                    refreshCharacter = function(element, token)
                        element.data.token = token
                        element.text = string.format("%+d", token.properties:RecoveryAmount())
                    end,
                    setToken = function(element, token)
                        element.data.token = token
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
                        gui.Tooltip(usageNote)(element)
                    end,
                    press = function(element)
                        local token = element.data.token
                        if token == nil then return end

                        local useHeroTokens = false
                        local quantity = max(0, (token.properties:GetResources()[recoveryid] or 0) - (token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
                        if quantity <= 0 then
                            if (not token.properties:IsHero()) or token.properties:GetHeroTokens() < 2 then
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
                gui.Panel{
                    classes = {"container"},
                    width = "auto",
                    valign = "top",
                    halign = "center",
                    flow = "horizontal",
                    gui.Label{
                        classes = {"recovery-count"},
                        text = "0",
                        editable = true,
                        numeric = true,
                        characterLimit = 2,
                        data = { token = nil },
                        refreshCharacter = function(element, token)
                            element.data.token = token
                            local quantity = max(0, (token.properties:GetResources()[recoveryid] or 0) - (token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
                            element.text = string.format("%d", quantity)
                        end,
                        setToken = function(element, token)
                            element.data.token = token
                        end,
                        change = function(element)
                            local token = element.data.token
                            if token == nil then return end
                            local n = tonumber(element.text)
                            if n == nil then
                                element:FireEvent("refreshCharacter", token)
                                return
                            end
                            n = math.max(0, round(n))
                            local nresources = token.properties:GetResources()[recoveryid] or 0
                            local usage = token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
                            local current = nresources - usage
                            local delta = n - current
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
    -- Dying segment (heroes only)
    local dyingFill = gui.Panel{ classes = {"panel", "health-fill", "dying"} }
    local dyingSegment = gui.Panel{
        classes = {"panel", "health-segment", "dying"},
        dyingFill,
        gui.Panel{
            classes = {"panel", "health-separator"},
            floating = true,
        },
    }

    -- Winded segment
    local windedFill = gui.Panel{ classes = {"panel", "health-fill", "winded"} }
    local windedSegment = gui.Panel{
        classes = {"panel", "health-segment", "winded"},
        windedFill,
        gui.Panel{
            classes = {"panel", "health-separator"},
            floating = true,
        },
    }

    -- Healthy segment
    local healthyFill = gui.Panel{ classes = {"panel", "health-fill", "healthy"} }
    local healthySegment = gui.Panel{
        classes = {"panel", "health-segment", "healthy"},
        healthyFill,
    }

    -- Diamond positioned via floating wrapper inside barRow
    local diamond = gui.Panel{
        classes = {"panel", "health-diamond"},
        rotate = 45,
    }
    local diamondPositioner = gui.Panel{
        classes = {"panel", "health-diamond-positioner"},
        floating = true,
        diamond,
    }

    -- Status boxes: appear below bar segment when health is in that range
    local windedStatus = gui.Panel{
        classes = {"panel", "health-status", "winded", "collapsed"},
        gui.Label{
            classes = {"label", "health-status-label", "winded"},
            text = "WINDED",
        },
    }
    local dyingStatus = gui.Panel{
        classes = {"panel", "health-status", "dying", "collapsed"},
        gui.Label{
            classes = {"label", "health-status-label", "dying"},
            text = "DYING",
        },
    }

    -- Temp stam box: shows temp HP value + label + hover-revealed clear button
    local tempStamValue = gui.Label{
        classes = {"label", "temp-stam-value"},
        text = "0",
    }
    local tempStamClearBtn = gui.Panel{
        classes = {"panel", "temp-stam-clear", "collapsed"},
        press = function(element)
            -- clearBtn -> tempStamBox -> windedColumn -> barRow -> returnPanel
            local token = element.parent.parent.parent.parent.data.token
            if token ~= nil and token.properties ~= nil then
                token:ModifyProperties{
                    description = "Clear Temporary Stamina",
                    execute = function()
                        token.properties:SetTemporaryHitpoints("0")
                    end,
                }
            end
        end,
        linger = function(element)
            gui.Tooltip("Clear temp")(element)
        end,
        gui.Label{
            classes = {"label", "temp-stam-clear-label"},
            text = "X",
        },
    }
    local tempStamBox = gui.Panel{
        classes = {"panel", "health-status", "temp", "collapsed"},
        tempStamValue,
        gui.Label{
            classes = {"label", "temp-stam-label"},
            text = "TEMP",
        },
        tempStamClearBtn,
    }

    -- Columns: pair each segment with its status box
    local dyingColumn = gui.Panel{
        classes = {"panel", "health-column", "dying"},
        dyingSegment,
        dyingStatus,
    }
    local windedColumn = gui.Panel{
        classes = {"panel", "health-column", "winded"},
        windedSegment,
        windedStatus,
    }
    local healthyColumn = gui.Panel{
        classes = {"panel", "health-column", "healthy"},
        healthySegment,
        tempStamBox,
    }

    local barRow = gui.Panel{
        classes = {"panel", "health-bar"},
        dyingColumn,
        windedColumn,
        healthyColumn,
        diamondPositioner,
    }

    local function pct(value)
        return string.format("%f%%", value)
    end

    return gui.Panel{
        styles = TacPanelStyles.Stamina,
        classes = {"container"},
        data = { token = nil },

        refreshCharacter = function(element, token)
            element.data.token = token
            if token == nil or not token.valid or token.properties == nil then
                return
            end

            local props = token.properties
            local currentHP = props:CurrentHitpoints()
            local maxHP = props:MaxHitpoints()
            local tempHP = props:TemporaryHitpoints() or 0
            local bloodied = props:BloodiedThreshold()
            local isHero = props:IsHero()
            local windedVal = math.floor(maxHP / 2)

            -- Column widths: equal splits
            if isHero then
                dyingColumn.selfStyle.width = "33%"
                windedColumn.selfStyle.width = "34%"
                healthyColumn.selfStyle.width = "33%"
            else
                windedColumn.selfStyle.width = "50%"
                healthyColumn.selfStyle.width = "50%"
            end
            dyingColumn:SetClass("collapsed", not isHero)

            -- Fill percentages per segment
            -- Dying: range is -bloodied to 0
            if isHero then
                local dyingRange = bloodied
                local dyingHP = math.max(0, math.min(dyingRange, currentHP + bloodied))
                dyingFill.selfStyle.width = dyingRange > 0
                    and pct(dyingHP / dyingRange * 100) or "0%"
            end

            -- Winded: range is 0 to windedVal
            local windedHP = math.max(0, math.min(windedVal, currentHP))
            windedFill.selfStyle.width = windedVal > 0
                and pct(windedHP / windedVal * 100) or "0%"

            -- Healthy: range is windedVal to maxHP
            local healthyRange = maxHP - windedVal
            local healthyHP = math.max(0, math.min(healthyRange, currentHP - windedVal))
            healthyFill.selfStyle.width = healthyRange > 0
                and pct(healthyHP / healthyRange * 100) or "0%"

            -- Diamond position: percentage across the full bar
            local totalRange = maxHP + (isHero and bloodied or 0)
            if totalRange <= 0 then totalRange = 1 end
            local diamondPct = isHero
                and ((currentHP + bloodied) / totalRange * 100)
                or (currentHP / totalRange * 100)
            diamondPct = math.max(0, math.min(100, diamondPct))
            diamondPositioner.selfStyle.width = pct(diamondPct)

            -- Diamond color: white normally, TEMP_STAM when temp HP > 0
            diamond:SetClass("has-temp", tempHP > 0)

            -- Status boxes: show when health is in that segment's range (mutually exclusive)
            local inDyingRange = isHero and currentHP < 0
            local inWindedRange = currentHP >= 0 and currentHP <= windedVal

            dyingStatus:SetClass("collapsed", not inDyingRange)
            windedStatus:SetClass("collapsed", not inWindedRange)

            -- Temp stam box: show when temp HP > 0
            tempStamBox:SetClass("collapsed", tempHP <= 0)
            tempStamValue.text = tostring(math.floor(tempHP))
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        barRow,
    }
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
        styles = TacPanelStyles.Resistances,
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
                        text = string.format("**<color=%s>%s:</color>** %s", DIM, weakTitle, weakText),
                    }
                end
                if hasImmune then
                    local immuneTitle = #immuneParts > 1 and "IMMUNITIES" or "IMMUNITY"
                    children[#children+1] = gui.Label{
                        classes = {"res-box", "immunity"},
                        width = boxWidth,
                        textWrap = true,
                        markdown = true,
                        text = string.format("**<color=%s>%s:</color>** %s", DIM, immuneTitle, immuneText),
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
            styles = TacPanelStyles.Stamina,
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
        styles = TacPanelStyles.MovementPanel,
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
        styles = TacPanelStyles.CharacteristicsPanel,
        classes = {"characteristics-panel"},
        children = children,
    }
end

--- Display the statistics panel
--- @return Panel
function TacPanel.Statistics()
    return TacPanel.CollapsiblePanel{
        title = "STATISTICS",
        altBg = false,
        tmargin = -26,
        gui.Panel{
            classes = {"container"},
            width = "100%",
            valign = "top",
            halign = "left",
            pad = 4,
            flow = "vertical",
            TacPanel.CharacteristicsPanel(),
            gui.MCDMDivider{ width = "96%", bgcolor = SURGE_BORDER },
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
                refreshToken = not safe_toint(entry.quantity) and function(element)
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
        styles = TacPanelStyles.HeroicResources,
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
                    local row = rows[index] or TacPanel.GrowingHRRow(entry, creature)
                    rows[index] = row
                    index = index + 1

                    row:FireEventTree("update", entry)
                    row:SetClass("available", entry.resources <= characterResources)
                    row:SetClass("collapsed", element.data.collapsed)

                    rowChildren[#rowChildren + 1] = row
                end
            end

            for i = index, #rows do
                if rows[i] then rows[i]:SetClass("collapsed", true) end
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
    local extraStyles = args.styles or {}
    local extraClasses = args.classes or {}
    local extraData = args.data or {}
    local altBg = args.altBg ~= false
    args.title = nil
    args.styles = nil
    args.classes = nil
    args.data = nil
    args.altBg = nil

    -- Build merged data with collapsed default
    local data = { collapsed = false }
    for k,v in pairs(extraData) do
        data[k] = v
    end

    -- Build merged classes
    local classes = {"tacpanel"}
    if altBg then classes[#classes+1] = "alt-bg" end
    for _,c in ipairs(extraClasses) do
        classes[#classes+1] = c
    end

    -- Build merged styles
    local allStyles = {TacPanelStyles.TacPanel}
    for _,s in ipairs(extraStyles) do
        allStyles[#allStyles+1] = s
    end

    -- Title bar (always child[1])
    local titleBar = gui.Panel{
        classes = {"tp-title-bar"},
        press = function(element)
            local outer = element.parent
            outer.data.collapsed = not outer.data.collapsed
            outer:FireEventTree("setCollapse", outer.data.collapsed)
        end,
        gui.Label{
            classes = {"panel-title"},
            text = title,
        },
        gui.CollapseArrow{
            classes = {"tp-expando"},
            floating = true,
            width = 10,
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
        styles = TacPanel.MergeStyles(allStyles),
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

--- Display the Routines panel
--- @return Panel
function TacPanel.Routines()
    return TacPanel.CollapsiblePanel{
        styles = {TacPanelStyles.Routines},
        classes = {"collapsed"},
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
                element:FireEventTree("setContent", {})
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
                    selfStyle = noneSelected and {color = GOLD_LIGHT} or nil,
                },
                selfStyle = noneSelected and {bgcolor = GOLD .. "1A", borderColor = GOLD} or nil,
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
                                width = "auto", height = "auto",
                                bgimage = "panels/square.png",
                                bgcolor = "clear",
                                border = 1,
                                borderColor = GOLD_LIGHT,
                                cornerRadius = 3,
                                pad = 3, lmargin = 4,
                                gui.VisibilityPanel{
                                    opacity = 1,
                                    visible = true,
                                    bgcolor = GOLD_LIGHT,
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
                            gui.PercentSlider{
                                valign = "center",
                                halign = "right",
                                hmargin = 6,
                                selfStyle = {borderColor = GOLD_LIGHT},
                                styles = {
                                    {selectors = {"percentSlider"},
                                     borderWidth = 1, borderColor = GOLD_LIGHT,
                                     cornerRadius = 2, bgimage = "panels/square.png",
                                     bgcolor = "black", height = 14, flow = "none"},
                                    {selectors = {"percentSliderLabel"},
                                     color = GOLD_LIGHT, bold = true, fontSize = 10,
                                     halign = "left", valign = "center",
                                     width = 40, textAlignment = "center", height = "auto"},
                                    {selectors = {"percentSliderLabel", "fill"},
                                     color = "black"},
                                    {selectors = {"percentFill"},
                                     bgcolor = GOLD_LIGHT, height = "100%",
                                     width = "0%", halign = "left", cornerRadius = 2},
                                },
                                value = token.properties:GetAuraDisplaySetting(routine.name).opacity,
                                refresh = function(element)
                                    if token == nil or not token.valid then
                                        return
                                    end

                                    element.value = token.properties:GetAuraDisplaySetting(routine.name).opacity
                                end,
                                preview = function(element)
                                    local settings = DeepCopy(token.properties:GetAuraDisplaySetting(routine.name))
                                    settings.opacity = element.value
                                    token.properties:SetAuraDisplaySetting(routine.name, settings)
                                    token:UpdateAuras()
                                end,
                                confirm = function(element)
                                    --set it to off to force upload.
                                    token.properties:SetAuraDisplaySetting(routine.name, nil)

                                    token:ModifyProperties{
                                        description = tr("Set Aura Display Settings"),
                                        undoable = false,
                                        execute = function()
                                            local settings = DeepCopy(token.properties:GetAuraDisplaySetting(routine.name))
                                            settings.opacity = element.value
                                            token.properties:SetAuraDisplaySetting(routine.name, settings)
                                        end,
                                    }
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

--- Display the heroic resources info
--- @return Panel
function TacPanel.HeroicResources()
    return TacPanel.CollapsiblePanel{
        classes = {"collapsed"},
        title = "HEROIC RESOURCES",
        refreshCharacter = function(element, token)
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end
            element:SetClass("collapsed", token.properties.typeName ~= "character")
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
                TacPanel.VictoriesBox(),
                TacPanel.HeroicResourcesBox(),
            },
            gui.Panel{
                styles = TacPanelStyles.HeroicResources,
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

--- Display the Skills & Languages panel
--- @return Panel
function TacPanel.SkillLanguages()
    return TacPanel.CollapsiblePanel{
        title = "SKILLS & LANGUAGES",
        gui.Panel{
            styles = TacPanelStyles.SkillsLanguages,
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
                            text = string.format("**<color=%s>%s:</color>** %s", MUTED, cat.text, proficiencyList)
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
                        text = string.format("**<color=%s>Languages:</color>** %s", MUTED, langText)
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
function TacPanel.Features()
    return TacPanel.CollapsiblePanel{
        styles = {TacPanelStyles.Notes},
        classes = {"collapsed"},
        title = "FEATURES",
        data = { token = nil },

        refreshCharacter = function(element, token)
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end

            element.data.token = token
            local creature = token.properties
            local features = creature:try_get("characterFeatures")
            if features == nil or #features == 0 then
                if not (creature.withCaptain and creature.minion) then
                    element:SetClass("collapsed", true)
                    return
                end
            end

            local labels = {}

            -- With Captain entry (minions only)
            if creature.withCaptain and creature.minion then
                local implemented = DrawSteelMinion.GetWithCaptainEffect(creature.withCaptain) ~= nil
                local implementedColor = cond(implemented, "#ff", "#55")

                labels[#labels+1] = gui.Label{
                    classes = {"note-entry"},
                    textWrap = true,
                    markdown = true,
                    text = string.format(
                        "**<color=%s>With Captain:</color>** <alpha=%s>%s",
                        MUTED, implementedColor, creature.withCaptain
                    ),
                }
            end

            -- Feature entries
            if features ~= nil then
                for _, feature in ipairs(features) do
                    if feature.description ~= "" then
                        local implemented = feature:try_get("implementation", 1) ~= 1
                        local implementedColor = cond(implemented, "#ff", "#55")

                        labels[#labels+1] = gui.Label{
                            classes = {"note-entry"},
                            textWrap = true,
                            markdown = true,
                            text = string.format(
                                "**<color=%s>%s:</color>** <alpha=%s>%s",
                                MUTED, feature.name, implementedColor, feature.description
                            ),
                        }
                    end
                end
            end

            if #labels == 0 then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)
            element:FireEventTree("setContent", labels)
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
            setContent = function(element, newChildren)
                element.children = newChildren
            end,
        },
    }
end

--- Display the Notes panel
--- @return Panel
function TacPanel.Notes()
    return TacPanel.CollapsiblePanel{
        styles = {TacPanelStyles.Notes},
        classes = {"collapsed"},
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

            -- Rebuild note labels into the content container
            local noteLabels = {}
            for _, note in ipairs(notes) do
                if note.text ~= nil and note.text ~= "" then
                    noteLabels[#noteLabels+1] = gui.Label{
                        classes = {"note-entry"},
                        textWrap = true,
                        markdown = true,
                        text = string.format(
                            "**<color=%s>%s:</color>** %s",
                            MUTED, note.title, note.text
                        ),
                    }
                end
            end
            element:FireEventTree("setContent", noteLabels)
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
            setContent = function(element, newChildren)
                element.children = newChildren
            end,
        },
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
            classes = {"vision-btn"},
            bgimage = "panels/initiative/initiative-icon.png",
            width = TacPanelSizes.VisionBtn.size,
            height = TacPanelSizes.VisionBtn.size,
            bgcolor = RED,
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
        gui.EnhIconButton{
            classes = {"vision-btn"},
            bgimage = "icons/icon_app/icon_app_18.png",
            width = TacPanelSizes.VisionBtn.size,
            height = TacPanelSizes.VisionBtn.size,
            bgcolor = TEAL,
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
        gui.EnhIconButton{
            classes = {"vision-btn"},
            bgimage = "icons/icon_app/icon_app_13.png",
            width = TacPanelSizes.VisionBtn.size,
            height = TacPanelSizes.VisionBtn.size,
            bgcolor = GOLD,
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
        gui.EnhIconButton{
            classes = {"vision-btn"},
            bgimage = "panels/hud/crown.png",
            width = TacPanelSizes.VisionBtn.size,
            height = TacPanelSizes.VisionBtn.size,
            bgcolor = GOLD,
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
        gui.EnhIconButton{
            classes = {"vision-btn"},
            bgimage = "icons/icon_app/icon_app_2.png",
            width = TacPanelSizes.VisionBtn.size,
            height = TacPanelSizes.VisionBtn.size,
            bgcolor = GOLD,
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

            multimonitor = "eds",
            monitor = function(element)
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
                    ev = ev + tok.properties.ev/GameSystem.minionsPerSquad
                else
                    ev = ev + tok.properties.ev
                end
            end

            ev = round(ev)

            local edsDescription
            local eds = g_edsSetting:Get()

            if ev <= eds/2 then
                edsDescription = "<color=#66ff66>Trivial</color>"
            elseif ev <= eds then
                local val = ev
                while val % 5 ~= 0 do
                    val = val + 1
                end

                if val - eds/2 >= eds - val then
                    edsDescription = "<color=#ffff66>Standard</color>"
                else
                    edsDescription = "<color=#66ff66>Easy</color>"
                end
            elseif ev <= eds + 10 then
                edsDescription = "<color=#ff6666>Hard</color>"
            else
                edsDescription = "<color=#990000>Extreme</color>"
            end

            element.text = string.format("%d monsters selected, EV: %d (<b>%s</b>)", #monsterTokens, ev, edsDescription)
        end,
    },
    }

    return gui.Panel{
        styles = {TacPanelStyles.TacPanel, TacPanelStyles.MultiEdit},
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
            width = "100%", height = "auto",
            flow = "horizontal", halign = "left",
            tmargin = 4, lmargin = 6,

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
    }
    for _,child in ipairs(children) do
        panelArgs[#panelArgs+1] = child
    end

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
            gui.Panel{
                classes = {"panel", "cond-setCaster", showSetCaster and "" or "collapsed"},
                press = function(element)
                    local ability = DeepCopy(MCDMUtils.GetStandardAbility("SetConditionCaster"))
                    ability.behaviors[1].condid = condid
                    ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(
                        token, ability, token, "prompt", {}, {})
                end,
                linger = function(element)
                    gui.Tooltip("Set Caster")(element)
                end,
                gui.Panel{
                    bgimage = "icons/icon_app/icon_app_4.png",
                    width = 10, height = 10,
                    valign = "center", halign = "center",
                    bgcolor = GOLD,
                },
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

--- Display the Auras we're emitting panel
--- @return Panel
function TacPanel.AurasEmitting()
    return TacPanel.CollapsiblePanel{
        styles = {TacPanelStyles.Conditions},
        classes = {"collapsed"},
        title = "AURAS EMITTING",
        data = { token = nil },
        refreshCharacter = function(element, token)
            element.data.token = token
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end

            local creature = token.properties
            local chips = {}

            -- Source 1: direct auras
            local auras = creature:try_get("auras", {})
            for _, auraInstance in ipairs(auras) do
                local aura = auraInstance.aura
                local display = aura.display or {}
                local auraid = auraInstance.guid
                local iconid = aura.iconid or ""
                local iconbg = display.bgcolor or "white"
                local iconhue = display.hueshift or 0

                chips[#chips+1] = gui.Panel{
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

                    iconid ~= "" and gui.Panel{
                        classes = {"panel", "cond-icon"},
                        bgimage = iconid,
                        bgcolor = iconbg,
                        hueshift = iconhue,
                    } or nil,
                    gui.Label{
                        classes = {"label", "cond-name"},
                        text = aura.name,
                    },
                    gui.Panel{
                        classes = {"panel", "cond-remove"},
                        press = function(el)
                            token:ModifyProperties{
                                description = "Remove Aura",
                                execute = function()
                                    token.properties:RemoveAura(auraid)
                                end,
                            }
                        end,
                        linger = function(el) gui.Tooltip("Remove")(el) end,
                        gui.Label{
                            classes = {"label", "cond-remove"},
                            text = "X",
                        },
                    },
                }
            end

            -- Source 2: ongoing effect modifier auras
            local ongoingEffectsTable = dmhub.GetTable(CharacterOngoingEffect.tableName)
            local ongoingEffects = creature:try_get("ongoingEffects", {})
            for _, effect in ipairs(ongoingEffects) do
                local effectInfo = ongoingEffectsTable[effect.ongoingEffectid]
                if effectInfo ~= nil then
                    for _, effmod in ipairs(effectInfo.modifiers) do
                        if effmod:has_key("aura") then
                            local aura = effmod.aura
                            local display = aura.display or {}
                            local auraid = aura.guid
                            local iconid = aura.iconid or ""
                            local iconbg = display.bgcolor or "white"
                            local iconhue = display.hueshift or 0

                            chips[#chips+1] = gui.Panel{
                                classes = {"panel", "cond-chip"},
                                data = { targetingMarkers = {} },
                                popupPositioning = "panel",

                                linger = function(el)
                                    el:FireEvent("clearMarkers")
                                    el.tooltip = gui.TooltipFrame(
                                        TacPanel.Tooltip(string.format('<b>%s</b>: %s', aura.name, aura:GetDescription())),
                                        { halign = "left", valign = "top" }
                                    )
                                end,
                                dehover = function(el)
                                    el:FireEvent("clearMarkers")
                                end,
                                clearMarkers = function(el)
                                    for _, m in ipairs(el.data.targetingMarkers) do m:Destroy() end
                                    el.data.targetingMarkers = {}
                                end,

                                iconid ~= "" and gui.Panel{
                                    classes = {"panel", "cond-icon"},
                                    bgimage = iconid,
                                    bgcolor = iconbg,
                                    hueshift = iconhue,
                                } or nil,
                                gui.Label{
                                    classes = {"label", "cond-name"},
                                    text = aura.name,
                                },
                                gui.Panel{
                                    classes = {"panel", "cond-remove"},
                                    press = function(el)
                                        token:ModifyProperties{
                                            description = "Remove Aura",
                                            execute = function()
                                                token.properties:RemoveAura(auraid)
                                            end,
                                        }
                                    end,
                                    linger = function(el) gui.Tooltip("Remove")(el) end,
                                    gui.Label{
                                        classes = {"label", "cond-remove"},
                                        text = "X",
                                    },
                                },
                            }
                        end
                    end
                end
            end

            if #chips == 0 then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)
            element:FireEventTree("setContent", chips)
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

--- Show a styled popup to add conditions or status effects
--- @param args table {tokens, button}
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
                    element:SetClass("collapsed", not string.starts_with(string.lower(element.text), searchText))
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
    local statusEffectOptions = {}
    for k, effect in unhidden_pairs(ongoingEffectsTable) do
        if effect.statusEffect then
            statusEffectOptions[#statusEffectOptions + 1] = gui.Label{
                classes = {"menu-option"},
                text = effect.name,
                searchText = function(element, searchText)
                    element:SetClass("collapsed", not string.starts_with(string.lower(element.text), searchText))
                end,
                linger = function(element)
                    gui.Tooltip(string.format("%s: %s", effect.name, effect.description))(element)
                end,
                press = function(element)
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
    end

    table.sort(statusEffectOptions, function(a, b) return a.text < b.text end)

    m_button.popup = gui.Panel{
            styles = {TacPanelStyles.AddConditionMenu},
            floating = true,
            vscroll = true,
            flow = "vertical",
            width = 300,
            height = 800,
            bgimage = "panels/square.png",
            bgcolor = RICH_BLACK,
            border = 1,
            borderColor = GOLD_BORDER,
            cornerRadius = 6,
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
                edit = function(element)
                    element.parent:FireEventTree("searchText", string.lower(element.text))
                    element.data.searchedOption = nil
                    local found = element.text == ""
                    for _, option in ipairs(options) do
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

            gui.Label{
                classes = {"menu-heading"},
                text = "STATUS EFFECTS",
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                children = statusEffectOptions,
            },
        }
end

--- Display the Persistent Abilities panel
--- @return Panel
function TacPanel.PersistentAbilities()
    return TacPanel.CollapsiblePanel{
        styles = {TacPanelStyles.Conditions},
        classes = {"collapsed"},
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
                                                dmhub.MarkLineOfSight(token, targetToken)
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
                    width = "100%",
                    height = "auto",
                    fontSize = 12,
                    color = RED,
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
    return TacPanel.CollapsiblePanel{
        styles = {TacPanelStyles.Conditions},
        title = "AURAS, CONDITIONS, & EFFECTS",
        data = { token = nil },
        refreshCharacter = function(element, token)
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
            local children = {}

            -- Add button first
            children[#children + 1] = gui.Panel{
                    classes = {"panel", "cond-add"},
                    press = function(el)
                        TacPanel.AddConditionMenu{
                            tokens = {element.data.token},
                            button = el,
                        }
                    end,
                    linger = function(el)
                        gui.Tooltip("Add a condition or effect")(el)
                    end,
                    gui.Label{
                        classes = {"label", "cond-add"},
                        text = "+",
                    },
                }

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

            -- Aura chips
            local aurasTouching = creature:GetAurasAffecting(token) or {}
            for _, auraInfo in ipairs(aurasTouching) do
                children[#children + 1] = TacPanel.AuraChip(auraInfo.auraInstance, token)
            end

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
        },
        gui.Input{
            classes = {"input", "cond-custom-input"},
            characterLimit = 60,
            placeholderText = "Add Custom Condition...",
            data = { token = nil },
            refreshCharacter = function(element, token)
                element.data.token = token
            end,
            refreshToken = function(element, token) element:FireEvent("refreshCharacter", token) end,
            setToken = function(element, token) element:FireEvent("refreshCharacter", token) end,
            change = function(element)
                local text = trim(element.text)
                if text ~= "" and element.data.token ~= nil then
                    element.data.token:ModifyProperties{
                        description = "Add Custom Condition",
                        execute = function()
                            local cc = element.data.token.properties:get_or_add("customConditions", {})
                            cc[dmhub.GenerateGuid()] = {
                                text = text,
                                timestamp = dmhub.serverTimeMilliseconds,
                            }
                        end,
                    }
                end
                element.text = ""
            end,
        },
    }
end

--- Display the testing panel
--- @return Panel
function TacPanel.Testing()
    local testInfo = [[
*Thank you for helping us test the new tactical panel!*

This panel should do everything the previous panel did.

**What Needs Testing**
* Pretty much the whole thing for all classes & levels.
* Including when you have multiple tokens selected.

If you find an issue, plese let us know via a bug report in the DMHub Discord.mod

**Known Issues**
* Lots of icons are placeholders, especially griffons, but also the light button and the icon in the temp stamina box.
]]
    return TacPanel.CollapsiblePanel{
        title = "TESTING INFO",
        altBg = true,
        data = { collapsed = false },
        gui.Label{
            width = "100%",
            height = "auto",
            fontFace = "Berling",
            fontSize = 14,
            textWrap = true,
            markdown = true,
            color = CREAM,
            text = testInfo,
        },
    }
end

CharacterPanel.CreateConditionsPanel = function(token)
    return nil
end

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
            if tok == nil or (dmhub.isDM and dmhub.tokenVision == nil) then
                element:SetClass("collapsed", true)
                m_maxLookup = -1
                m_slider = nil
                return
            end

            local maxLookupSetting = dmhub.GetSettingValue("maxlookup")
            local maxLookup = tok.countFloorsWithVisionAbove
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
                bgimage = "panels/square.png",
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
                bgimage = "panels/square.png",
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

    m_button.popup = gui.TooltipFrame(
        gui.Panel {
            styles = {
                Styles.Default,

                {
                    selectors = {"conditionSuboption"},
                    textAlignment = "center",
                    fontSize = 12,
                    bgcolor = Styles.backgroundColor,
                    borderColor = Styles.textColor,
                    borderWidth = 2,
                    height = 18,
                    minWidth = 40,
                    width = "auto",
                },
                {
                    selectors = {"conditionSuboption", "hover"},
                    bgcolor = Styles.textColor,
                    color = Styles.backgroundColor,
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
                    color = Styles.textColor,
                    bgcolor = "clear",
                    halign = "center",
                },
                {
                    selectors = { "conditionOption", "searched" },
                    bgcolor = Styles.textColor,
                    color = Styles.backgroundColor
                },
                {
                    selectors = { "conditionOption", "hover" },
                    bgcolor = Styles.textColor,
                    color = Styles.backgroundColor
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
                bgimage = "panels/square.png",
                width = "90%",
                height = 1,
                bgcolor = Styles.textColor,
                halign = "center",
                vmargin = 8,
                gradient = Styles.horizontalGradient,
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

local function PersistencePanel(m_token)


    local persistenceLabel = gui.Label{
        text = "Persistent Abilities",
        width = "100%",
        height = "auto",
        fontSize = 16,
        halign = "left",
        valign = "center",
        hpad = 4,
        color = Styles.textColor,
    }

    local errorLabel = gui.Label{
        classes = {"collapsed"},
        text = "Too many persistent abilities. You must end some.",
        width = "100%",
        height = "auto",
        fontSize = 14,
        halign = "left",
        hpad = 4,
        color = "Red",
    }


    local m_panelsCache = {}

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        styles = {
            gui.Style{
                selectors = {"persistentPanel"},

                color = Styles.textColor,
                bgcolor = Styles.backgroundColor,
                hmargin = 4,
                hpad = 4,

                width = "100%",
                height = "auto",
                fontSize = 14,
                flow = "horizontal",
            },
            gui.Style{
                selectors = {"button"},

                priority = 100,
                halign = "right",
                fontSize = 12,
                height = "100%",
                width = 50,
                height = 18,
                rmargin = 12,
                lmargin = 0,
                vmargin = 0,
            },

            gui.Style{
                selectors = {"button", "pulse"},
                transitionTime = 0.4,
                bgcolor = Styles.textColor,
                color = Styles.backgroundColor,
            },
            gui.Style{
                selectors = {"activateButton", "~parent:active"},
                hidden = 1,
            },
        },

        persistenceLabel,
        errorLabel,

        refreshToken = function(element, tok)
            m_token = tok
        end,

        refresh = function(element)
            if m_token == nil or not m_token.valid then
                element:SetClass("collapsed", true)
                return
            end

            local persistentAbilities = m_token.properties:try_get("persistentAbilities")
            if persistentAbilities == nil or #persistentAbilities == 0 then
                element:SetClass("collapsed", true)
                return
            end

            local q = dmhub.initiativeQueue
            if q == nil or q.hidden then
                element:SetClass("collapsed", true)
                return
            end

            local totalCost = 0

            local newPanelsCache = {}
            local children = {persistenceLabel}

            for i,entry in ipairs(persistentAbilities) do
                local guid = entry.guid
                if entry.combatid == q.guid then
                    totalCost = totalCost + entry.cost

                    local panel = m_panelsCache[entry.guid] or gui.Label{
                        classes = {"persistentPanel"},
                        bgimage = true,
                        text = string.format("%s--%d", entry.abilityName, entry.cost),

                        data = {
                            targetingMarkers = nil,
                        },

                        think = function(element)
                            element:FireEventTree("pulsePersist")
                        end,

                        refresh = function(element)
                            local q = dmhub.initiativeQueue
                            if q == nil or q.hidden then
                                element.thinkTime = nil
                                return
                            end

                            if m_token == nil or (not m_token.valid) then
                                return
                            end

                            local active = false
                            if m_token.properties:IsOurTurn() and (q.round ~= entry.round or q.turn ~= entry.turn) then
                                --we need to activate this entry since it's a new turn and it hasn't been used.
                                active = true
                                element.thinkTime = 1
                            else
                                element.thinkTime = nil
                            end

                            element:SetClass("active", active)
                        end,

                        hover = function(element)
                            element:FireEvent("clearTargetingMarkers")

                            local abilities = m_token.properties:GetActivatedAbilities{excludeGlobal = true}
                            for _,ability in ipairs(abilities) do
                                if ability.name == entry.abilityName then
                                    local panel = CreateAbilityTooltip(ability, {width = 540, token = m_token})
                                    element.tooltip = panel

                                    if ability:Persistence().mode == "recast_target" then
                                        for _,targetid in ipairs(entry.targets or {}) do
                                            local targetToken = dmhub.GetTokenById(targetid)
                                            if targetToken ~= nil then
                                                element.data.targetingMarkers = element.data.targetingMarkers or {}
                                                element.data.targetingMarkers[#element.data.targetingMarkers+1] = dmhub.MarkLineOfSight(m_token, targetToken)
                                            end
                                        end
                                    end

                                    break
                                end
                            end
                        end,

                        dehover = function(element)
                            element:FireEvent("clearTargetingMarkers")
                        end,

                        destroy = function(element)
                            element:FireEvent("clearTargetingMarkers")
                        end,

                        clearTargetingMarkers = function(element)
                            if element.data.targetingMarkers ~= nil then
                                for _,m in ipairs(element.data.targetingMarkers) do
                                    m:Destroy()
                                end
                                element.data.targetingMarkers = nil
                            end
                        end,

                        --[[ gui.Button{
                            classes = {"activateButton", "button"},
                            text = "Persist",
                            pulsePersist = function(element)
                                element:PulseClass("pulse")
                            end,
                            click = function(element)
                                local abilities = m_token.properties:GetActivatedAbilities{excludeGlobal = true, bindCaster = true}
                                for _,ability in ipairs(abilities) do
                                    if ability.name == entry.abilityName then
                                        ability.OnFinishCast = function(ability)
                                            local q = dmhub.initiativeQueue
                                            if q == nil or q.hidden then
                                                return
                                            end
                                            local persistentAbilities = m_token.properties:try_get("persistentAbilities", {})
                                            for _,entry in ipairs(persistentAbilities) do
                                                if entry.guid == guid then
                                                    m_token:ModifyProperties{
                                                        description = "Update Persistent Ability",
                                                        undoable = false,
                                                        execute = function()
                                                            entry.turn = q.turn
                                                            entry.round = q.round
                                                        end,
                                                    }
                                                end
                                            end
                                        end

                                        local persistenceMode = ability:Persistence().mode
                                        ability.persistence = nil
                                        ability.resourceNumber = entry.cost
                                        ability.actionResourceId = cond(persistenceMode == "recast_maneuver", CharacterResource.maneuverResourceId, "none")
                                        ability.promptOverride = string.format(tr("Persistence: Recast %s"), ability.name)

                                        local targeting = "prompt"

                                        local targets = nil

                                        if persistenceMode == "recast_target" then
                                            targeting = "inherit"
                                            targets = {}
                                            for _,targetid in ipairs(entry.targets or {}) do
                                                local targetToken = dmhub.GetTokenById(targetid)
                                                if targetToken ~= nil then
                                                    targets[#targets+1] = {
                                                        token = targetToken,
                                                    }
                                                end
                                            end
                                        elseif persistenceMode == "recast_with_one_target" then
                                            ability.numTargets = 1
                                        end

                                        ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(m_token, ability, m_token, targeting, {}, { targets = targets })
                                        return
                                    end
                                end
                            end,
                        }, ]]

                        gui.Button{
                            classes = {"deleteButton", "button"},
                            text = "Stop",
                            --[[ pulsePersist = function(element)
                                element:PulseClass("pulse")
                            end, ]]
                            click = function(element)
                                m_token.properties:EndPersistentAbilityById(guid)
                            end,
                        },
                    }

                    newPanelsCache[guid] = panel
                    children[#children+1] = panel
                end
            end

            children[#children+1] = errorLabel

            errorLabel:SetClass("collapsed", totalCost <= 2)

            element.children = children
            m_panelsCache = newPanelsCache

            if #children <= 2 then
                element:SetClass("collapsed", true)
            else
                element:SetClass("collapsed", false)
            end
        end,

    }

    return resultPanel
end


local function RoutinesPanel(m_token)

    local m_routinePanels = {}

    local startDiv = gui.Divider{}
    local endDiv = gui.Divider{}

    local routinesLabel = gui.Label{
        text = "Routines",
        width = "100%",
        height = "auto",
        fontSize = 16,
        halign = "left",
        valign = "center",
        hpad = 4,
        color = Styles.textColor,
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        minHeight = 20,
        styles = {
            {
                selectors = {"routine"},
                color = Styles.textColor,
                bgcolor = Styles.backgroundColor,
                hmargin = 4,
                hpad = 4,
            },
            {
                selectors = {"routine", "hover"},
                bgcolor = Styles.textColor,
                color = Styles.backgroundColor,
                brightness = 1.2,
            },
            {
                selectors = {"routine", "selected"},
                bgcolor = Styles.textColor,
                color = Styles.backgroundColor,
                brightness = 1,
            },
        },

        startDiv,
        routinesLabel,
        endDiv,

        refreshToken = function(element, tok)
            m_token = tok
        end,

        refresh = function(element)
            if m_token == nil or not m_token.valid then
                element:SetClass("collapsed", true)
                return
            end
            local routines = m_token.properties:GetRoutines()
            if routines == nil or #routines == 0 then
                element:SetClass("collapsed", true)
                return
            end

            local initiative = dmhub.initiativeQueue

            local routinesSelected = m_token.properties:try_get("routinesSelected")

            element:SetClass("collapsed", false)

            local newPanels = {}

            local nonePanel = gui.Label{
                text = "None",
                classes = {"routine"},
                bgimage = true,
                width = "100%",
                height = "auto",
                fontSize = 14,
                flow = "horizontal",
                press = function(element)
                    m_token:ModifyProperties{
                        description = tr("Select Routine"),
                        execute = function()
                            m_token.properties.routinesSelected = nil
                        end,
                    }
                end,
                refresh = function(element)
                    if m_token == nil or not m_token.valid then
                        return
                    end

                    local routinesSelected = m_token.properties:try_get("routinesSelected")
                    element:FireEvent("selected", routinesSelected == nil)
                end,
            }

            local routinesSelected = m_token.properties:try_get("routinesSelected") or {}

            local children = {startDiv, routinesLabel, nonePanel}

            for routineIndex,routine in ipairs(routines) do
                local panel = m_routinePanels[routine.guid] or gui.Panel{
                    data = {
                        selected = false,
                    },
                    classes = {"routine"},
                    bgimage = true,
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",

                    gui.Label{
                        classes = {"routine"},
                        text = routine.name,
                        inherit_selectors = true,
                        bgimage = true,
                        width = "50%",
                        height = "auto",
                        fontSize = 14,
                        hover = function(element)
                            element.tooltip = gui.TooltipFrame(routine:Render{})
                        end,
                        press = function(element)
                            m_token:ModifyProperties{
                                description = tr("Select Routine"),
                                execute = function()
                                    local selected = m_token.properties:get_or_add("routinesSelected", {})
                                    if selected[routine.guid] then
                                        selected[routine.guid] = nil
                                    else
                                        selected[routine.guid] = ServerTimestamp()
                                    end
                                    m_token.properties.routinesSelected = selected
                                end,
                            }
                        end,
                    },

                    selectionChanged = function(element, selected)
                        element:SetClass("selected", selected)
                        local labelChild = element.children[1]
                        labelChild:SetClass("selected", selected)
                        
                        if not selected then
                            element.children = {labelChild}
                            return
                        end

                        element.children = {
                            labelChild,
                            gui.VisibilityPanel{
                                valign = "center",
                                halign = "right",
                                opacity = 1,
                                visible = true,
                                bgcolor = "black",
                                press = function(element)
                                    local settings = DeepCopy(m_token.properties:GetAuraDisplaySetting(routine.name))
                                    settings.hide = not settings.hide

                                    m_token:ModifyProperties{
                                        description = tr("Set Aura Display Settings"),
                                        undoable = false,
                                        execute = function()
                                            m_token.properties:SetAuraDisplaySetting(routine.name, settings)
                                        end,
                                    }
                                end,
                                refresh = function(element)
                                    if m_token == nil or not m_token.valid then
                                        return
                                    end

                                    element:FireEvent("visible", not m_token.properties:GetAuraDisplaySetting(routine.name).hide)
                                end,
                            },
                            gui.PercentSlider{
                                valign = "center",
                                halign = "right",
                                hmargin = 6,
                                value = m_token.properties:GetAuraDisplaySetting(routine.name).opacity,
                                refresh = function(element)
                                    if m_token == nil or not m_token.valid then
                                        return
                                    end

                                    element.value = m_token.properties:GetAuraDisplaySetting(routine.name).opacity
                                end,
                                preview = function(element)
                                    local settings = DeepCopy(m_token.properties:GetAuraDisplaySetting(routine.name))
                                    settings.opacity = element.value
                                    m_token.properties:SetAuraDisplaySetting(routine.name, settings)
                                    m_token:UpdateAuras()
                                end,
                                confirm = function(element)
                                    --set it to off to force upload.
                                    m_token.properties:SetAuraDisplaySetting(routine.name, nil)

                                    m_token:ModifyProperties{
                                        description = tr("Set Aura Display Settings"),
                                        undoable = false,
                                        execute = function()
                                            local settings = DeepCopy(m_token.properties:GetAuraDisplaySetting(routine.name))
                                            settings.opacity = element.value
                                            m_token.properties:SetAuraDisplaySetting(routine.name, settings)
                                        end,
                                    }
                                end,
                            }
                        }
                    end,
                }

                local selected = (routinesSelected ~= nil and routinesSelected[routine.guid])
                if selected ~= panel.data.selected then
                    panel.data.selected = selected
                    panel:FireEvent("selectionChanged", selected)
                end

                children[#children+1] = panel
                newPanels[routine.guid] = panel
            end

            children[#children+1] = endDiv
            m_routinePanels = newPanels

            element.children = children
        end,
    }

    return resultPanel
end

local function AurasAffectingPanel(m_token)
    local resultPanel

    local m_panelsCache = {}

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        refreshToken = function(element, tok)
            m_token = tok
        end,

        refresh = function(element)
            if m_token == nil or not m_token.valid then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)
            local newPanelsCache = {}
            local children = {}
			local aurasTouching = m_token.properties:GetAurasAffecting(m_token) or {}
            for i,info in ipairs(aurasTouching) do
                local auraInstance = info.auraInstance

                local panel = m_panelsCache[auraInstance.guid] or gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    vmargin = 4,
                    bgimage = "panels/square.png",
                    bgcolor = "black",
                    opacity = 0.8,

                    hover = function(element)
						local tooltip = CreateAuraTooltip(auraInstance)
                        tooltip:MakeNonInteractiveRecursive()
                        element.tooltip = gui.TooltipFrame(tooltip)

						local area = auraInstance:GetArea()
						if area ~= nil then
							element.data.mark = {
								area:Mark{
									color = "white",
									video = "divinationline.webm",
								}
							}
						end
                    end,

					dehover = function(element)
						if element.data.mark ~= nil then
							for _,mark in ipairs(element.data.mark) do
								mark:Destroy()
							end
							element.data.mark = nil
						end
					end,



                    gui.DiamondButton{
                        bgimage = 'panels/square.png',
                        halign = "left",
                        width = 24,
                        height = 24,
                        hmargin = 6,
                        valign = "center",
                        icon = auraInstance.aura.iconid,
                        create = function(element)
                            element:FireEvent("display", auraInstance.aura.display)
                        end,
                    },

                    gui.Label{
                        height = "auto",
                        width = 120,
                        textWrap = false,
                        halign = "left",
                        valign = "center",
                        rmargin = 4,
                        fontSize = 14,
                        minFontSize = 8,
                        color = Styles.textColor,
                        text = string.format("%s (Aura)", auraInstance.aura.name),
                    },
                }

                newPanelsCache[auraInstance.guid] = panel

                children[#children+1] = panel
            end

            m_panelsCache = newPanelsCache
            element.children = children
        end,
    }

    return resultPanel
end

local function AurasEmittingPanel(m_token)

    local m_auraPanels = {}

    local resultPanel

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        refreshToken = function(element, tok)
            m_token = tok
        end,

        refresh = function(element)
            if m_token == nil or not m_token.valid then
                element:SetClass("collapsed", true)
                return
            end

            local creature = m_token.properties
            if creature == nil then
                element:SetClass("collapsed", true)
                return
            end

            local newChildren = {}
            local newPanels = {}
            local auras = creature:try_get("auras", {})
            for _,aura in ipairs(auras) do
                local auraid = aura.guid
                local panel = m_auraPanels[auraid] or gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    vmargin = 4,
                    bgimage = "panels/square.png",
                    bgcolor = "clear",

                    gui.DiamondButton{
                        bgimage = 'panels/square.png',
                        halign = "left",
                        width = 24,
                        height = 24,
                        hmargin = 6,
                        valign = "center",
                        icon = aura.aura.iconid,
                        create = function(element)
                            element:FireEvent("display", aura.aura.display)
                        end,
                    },

                    gui.Label{
                        height = "auto",
                        width = 120,
                        textWrap = false,
                        halign = "left",
                        valign = "center",
                        rmargin = 4,
                        fontSize = 14,
                        minFontSize = 8,
                        color = Styles.textColor,
                        text = string.format("%s (Aura)", aura.aura.name),
                    },

                    gui.DeleteItemButton{
                        width = 12,
                        height = 12,

                        lmargin = 24,
                        halign = "left",
                        valign = "center",
                        data = {
                            entry = nil,
                        },
                        press = function(element)
                            m_token:BeginChanges()
                            m_token.properties:RemoveAura(auraid)
                            m_token:CompleteChanges("Remove Aura")
                        end,
                    },
                }

                newPanels[aura.guid] = panel
                newChildren[#newChildren+1] = panel
            end

            local ongoingEffectsTable = dmhub.GetTable(CharacterOngoingEffect.tableName)
            local ongoingeffects = creature:try_get("ongoingEffects", {})
            for _, effect in ipairs(ongoingeffects) do
                local effectInfo = ongoingEffectsTable[effect.ongoingEffectid]
                for _, mod in ipairs(effectInfo.modifiers) do
                    if mod:has_key("aura") then
                        local auraid = mod.aura.guid
                        local panel = m_auraPanels[auraid] or gui.Panel{
                            width = "100%",
                            height = "auto",
                            flow = "horizontal",
                            vmargin = 4,
                            bgimage = "panels/square.png",
                            bgcolor = "clear",

                            gui.DiamondButton{
                                bgimage = 'panels/square.png',
                                halign = "left",
                                width = 24,
                                height = 24,
                                hmargin = 6,
                                valign = "center",
                                icon = mod.aura.iconid,
                                create = function(element)
                                    element:FireEvent("display", mod.aura.display)
                                end,
                            },

                            gui.Label{
                                height = "auto",
                                width = 120,
                                textWrap = false,
                                halign = "left",
                                valign = "center",
                                rmargin = 4,
                                fontSize = 14,
                                minFontSize = 8,
                                color = Styles.textColor,
                                text = string.format("%s (Aura)", mod.aura.name),
                            },

                            gui.VisibilityPanel{
                                valign = "center",
                                halign = "left",
                                opacity = 1,
                                visible = true,
                                bgcolor = "white",
                                margin = 3,
                                press = function(element)
                                    local settings = DeepCopy(m_token.properties:GetAuraDisplaySetting(mod.aura.name))
                                    settings.hide = not settings.hide

                                    m_token:ModifyProperties{
                                        description = tr("Set Aura Display Settings"),
                                        undoable = false,
                                        execute = function()
                                            m_token.properties:SetAuraDisplaySetting(mod.aura.name, settings)
                                        end,
                                    }
                                end,
                                refresh = function(element)
                                    if m_token == nil or not m_token.valid then
                                        return
                                    end

                                    element:FireEvent("visible", not m_token.properties:GetAuraDisplaySetting(mod.aura.name).hide)
                                end,
                            },

                            gui.PercentSlider{
                                valign = "center",
                                halign = "left",
                                hmargin = 6,
                                value = m_token.properties:GetAuraDisplaySetting(mod.aura.name).opacity,
                                refresh = function(element)
                                    if m_token == nil or not m_token.valid then
                                        return
                                    end

                                    element.value = m_token.properties:GetAuraDisplaySetting(mod.aura.name).opacity
                                end,
                                preview = function(element)
                                    local settings = DeepCopy(m_token.properties:GetAuraDisplaySetting(mod.aura.name))
                                    settings.opacity = element.value
                                    m_token.properties:SetAuraDisplaySetting(mod.aura.name, settings)
                                    m_token:UpdateAuras()
                                end,
                                confirm = function(element)
                                    --set it to off to force upload.
                                    m_token.properties:SetAuraDisplaySetting(mod.aura.name, nil)

                                    m_token:ModifyProperties{
                                        description = tr("Set Aura Display Settings"),
                                        undoable = false,
                                        execute = function()
                                            local settings = DeepCopy(m_token.properties:GetAuraDisplaySetting(mod.aura.name))
                                            settings.opacity = element.value
                                            m_token.properties:SetAuraDisplaySetting(mod.aura.name, settings)
                                        end,
                                    }
                                end,
                            },
                        }

                        newPanels[mod.aura.guid] = panel
                        newChildren[#newChildren+1] = panel
                    end
                end
            end

            m_auraPanels = newPanels
            element.children = newChildren
        end,
    }

    return resultPanel
end

local function InflictedConditionsPanel(m_token)

	local m_conditions
	local addConditionButton = nil
	local ongoingEffectPanels = {}

    local resultPanel

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        refreshToken = function(element, tok)
            m_token = tok
        end,

        refresh = function(element)
            if m_token == nil or not m_token.valid then
                for _,p in ipairs(ongoingEffectPanels) do
                    p:SetClass("collapsed", true)
                end
                return
            end

            local creature = m_token.properties
            if creature == nil then
                for _,p in ipairs(ongoingEffectPanels) do
                    p:SetClass("collapsed", true)
                end
                return
            end

            m_conditions = creature:try_get("inflictedConditions", {})
            local count = 0

            local newPanels = false

            for key,cond in pairs(m_conditions) do
                count = count+1
                local panel = ongoingEffectPanels[count]
    
                if panel == nil then

                    newPanels = true

                    local button = gui.DiamondButton{
                        bgimage = 'panels/square.png',
                        halign = "left",
                        width = 24,
                        height = 24,
                        hmargin = 6,
                        valign = "center",

                        click = function(element)

                            local items = {}

                            local duration = m_token.properties:ConditionDuration(element.parent.data.condid)
                            if duration and duration ~= "eot" and duration ~= "eoe" then
                                items[#items+1] = {
                                    text = "Roll Save",
                                    click = function()
                                        m_token.properties:RollConditionSave(element.parent.data.condid)
                                        element.popup = nil
                                    end,
                                }
                            end

                            local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)
                            local riders = {}
                            for key,rider in unhidden_pairs(ridersTable) do
                                if rider.condition == element.parent.data.condid then
                                    riders[#riders+1] = key
                                end
                            end

                            table.sort(riders, function(a,b) return ridersTable[a].name < ridersTable[b].name end)

                            for _,rider in ipairs(riders) do
                                local text
                                local alreadyHas = m_token.properties:ConditionHasRider(element.parent.data.condid, rider)
                                if alreadyHas then
                                    text = string.format("Remove %s", ridersTable[rider].name)
                                else
                                    text = string.format("Add %s", ridersTable[rider].name)
                                end

                                items[#items+1] = {
                                    text = text,
                                    click = function()
                                        m_token:BeginChanges()
                                        m_token.properties:SetConditionRider(element.parent.data.condid, rider, not alreadyHas)
                                        m_token:CompleteChanges("Apply Condition Rider")
                                        element.popup = nil
                                    end,
                                }
                            end

                            items[#items+1] = {
                                text = "Remove Condition",
                                click = function()
                                    m_token:BeginChanges()
                                    m_token.properties:InflictCondition(element.parent.data.condid, {purge = true})
                                    m_token:CompleteChanges("Apply Condition")
                                    element.popup = nil
                                end,
                            }

                            element.popup = gui.ContextMenu{
                                entries = items,
                            }
                            
                        end,
                    }

                    local descriptionLabel = gui.Label{
                        height = "auto",
                        width = 140,
                        textWrap = false,
                        halign = "left",
                        valign = "center",
                        rmargin = 4,
                        fontSize = 14,
                        minFontSize = 8,
                        color = Styles.textColor,
                    }

                    local quantityLabel = gui.Label{
                        width = "auto",
                        height = "auto",
                        minWidth = 80,
                        fontSize = 14,
                        bold = true,
                        halign = "left",
                        valign = "center",
                        color = Styles.textColor,
                        characterLimit = 2,
                        textAlignment = "left",

                        press = function(element)
                            if element.popup ~= nil then
                                element.popup = nil
                                return
                            end

                            local SetDuration = function(duration)
                                m_token:BeginChanges()
                                m_token.properties:InflictCondition(element.parent.data.condid, {force = true, duration = duration})
                                m_token:CompleteChanges("Set Condition Duration")
                            end

                            local entries = {}

                            entries[#entries+1] = {
                                text = "Save Ends",
                                click = function()
                                    SetDuration("save")
                                    element.popup = nil
                                end,
                            }

                            entries[#entries+1] = {
                                text = "EoT",
                                click = function()
                                    SetDuration("eot")
                                    element.popup = nil
                                end,
                            }
                            entries[#entries+1] = {
                                text = "EoE",
                                click = function()
                                    SetDuration("eoe")
                                    element.popup = nil
                                end,
                            }
                            element.popup = gui.ContextMenu{
                                halign = "center",
                                entries = entries,
                            }
                        end,

                        change = function(element)
                            local cond = m_conditions[element.parent.data.condid]
                            local stacks = tonumber(element.text)
                            if stacks == nil then
                                element.text = tostring(cond.stacks)
                                return
                            end

                            m_token:BeginChanges()
                            m_token.properties:InflictCondition(element.parent.data.condid, {stacks = stacks - cond.stacks})
                            m_token:CompleteChanges("Apply Condition")
                        end,
                    }

                    local trackCasterButton = gui.Button{
                        fontSize = 12,
                        width = 62,
                        height = "auto",
                        text = "Set Caster",
                        halign = "left",
                        press = function(element)
                            local ability = DeepCopy(MCDMUtils.GetStandardAbility("SetConditionCaster"))
                            ability.behaviors[1].condid = element.parent.data.condid
                            ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(m_token, ability, m_token, "prompt", {}, {})
                        end,
                        refresh = function(element)
                            if m_token == nil or not m_token.valid then
                                return
                            end

                            local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
                            local ongoingEffectInfo = conditionsTable[element.parent.data.condid]

                            if ongoingEffectInfo == nil or not ongoingEffectInfo.trackCaster then
                                element:SetClass("collapsed", true)
                                return
                            end

                            local conditions = m_token.properties:try_get("inflictedConditions", {})
                            local cond = conditions[element.parent.data.condid]
                            if cond == nil or cond.casterInfo ~= nil then
                                element:SetClass("collapsed", true)
                            else
                                element:SetClass("collapsed", false)
                            end
                        end,
                    }

                    panel = gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                        vmargin = 4,
                        bgimage = "panels/square.png",
                        bgcolor = "black",
                        opacity = 0.8,
                        data = {
                            targetingMarkers = {},
                        },

                        clearTargetingMarkers = function(element)
                            if #element.data.targetingMarkers == 0 then
                                return
                            end
                            for _, marker in ipairs(element.data.targetingMarkers) do
                                marker:Destroy()
                            end
                            element.data.targetingMarkers = {}
                        end,

                        button,

                        descriptionLabel,

                        quantityLabel,
                        trackCasterButton,

                        gui.DeleteItemButton{
                            width = 12,
                            height = 12,

                            lmargin = 8,
                            halign = "left",
                            valign = "center",
                            data = {
                                entry = nil,
                            },
                            press = function(element)
                                m_token:BeginChanges()
                                m_token.properties:InflictCondition(element.parent.data.condid, {purge = true})
                                m_token:CompleteChanges("Remove Condition")
                            end,
                        },


                        refresh = function(element)
                            if m_token == nil or not m_token.valid then
                                return
                            end

                            local cond = m_conditions[element.data.condid]
                            if cond == nil then
                                return
                            end

                            local ongoingEffectsTable = dmhub.GetTable(CharacterCondition.tableName)
                            local ongoingEffectInfo = ongoingEffectsTable[element.data.condid]

                            local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)
                            local text = ongoingEffectInfo.name
                            local riderDuration = false
                            for _,riderid in ipairs(m_token.properties:GetConditionRiders(element.data.condid) or {}) do
                                if ridersTable[riderid] then
                                    text = string.format("%s %s", text, ridersTable[riderid].name)
                                    if ridersTable[riderid].removeThisInsteadOfCondition then
                                        riderDuration = true
                                    end
                                end
                            end

                            descriptionLabel.text = text

                            local ongoingEffectsTable = dmhub.GetTable(CharacterCondition.tableName)
                            local ongoingEffectInfo = ongoingEffectsTable[element.data.condid]
                            button:FireEvent("icon", ongoingEffectInfo.iconid)
                            button:FireEvent("display", ongoingEffectInfo.display)

                            local duration = cond.duration
                            if duration == "eot" then
                                duration = "EoT"
                            elseif duration == "eoe" then
                                duration = "EoE"
                            else
                                duration = "Save"
                            end

                            quantityLabel.text = duration

                            quantityLabel:SetClass("hidden", ongoingEffectInfo.indefiniteDuration and (not riderDuration))
                        end,

                        dehover = function(element)
                            element:FireEvent("clearTargetingMarkers")
                        end,

                        linger = function(element)
                            element:FireEvent("clearTargetingMarkers")
                            local cond = m_conditions[element.data.condid]
                            if cond == nil then
                                return
                            end
                            local ongoingEffectsTable = dmhub.GetTable(CharacterCondition.tableName)
                            local ongoingEffectInfo = ongoingEffectsTable[element.data.condid]

                            local caster = cond.casterInfo
                            if caster ~= nil and type(caster.tokenid) == "string" then
                                local casterToken = dmhub.GetTokenById(caster.tokenid)
                                if casterToken ~= nil then

									element.data.targetingMarkers[#element.data.targetingMarkers+1] = dmhub.HighlightLine{
										color = "red",
										a = casterToken.pos,
										b = m_token.pos,
									}
                                end
                            end


                            local duration = cond.duration
                            if duration == "eot" then
                                duration = "EoT"
                            elseif duration == "eoe" then
                                duration = "EoE"
                            elseif type(duration) == "string" then
                                duration = string.upper(duration) .. " ends"
                            else
                                duration = "EoT"
                            end

                            local durationText = string.format(" (%s)", duration)
                            if ongoingEffectInfo.indefiniteDuration then
                                durationText = ""
                            end

                            local ridersText = ""
                            local riderids = m_token.properties:GetConditionRiders(element.data.condid)
                            if riderids ~= nil then
                                local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)
                                for _,riderid in ipairs(riderids) do
                                    local riderInfo = ridersTable[riderid]
                                    if riderInfo ~= nil then
                                        ridersText = string.format("%s\n\n<b>%s</b>: %s", ridersText, riderInfo.name, riderInfo.description)
                                    end
                                end
                            end

                            element.popupPositioning = "panel"
                            gui.Tooltip{halign = "left", valign = "center", text = string.format('<b>%s</b>%s: %s%s\n\n%s', ongoingEffectInfo.name, durationText, ongoingEffectInfo.description, ridersText, cond.sourceDescription or "")}(element)
                        end,
                    }

                    ongoingEffectPanels[count] = panel
                end

                panel.data.condid = key
            end

            for i,p in ipairs(ongoingEffectPanels) do
                p:SetClass("collapsed", i > count)
            end

            if addConditionButton == nil then
                newPanels = true

                addConditionButton = gui.DiamondButton{
                    width = 24,
                    height = 24,
                    halign = "left",
                    valign = "top",
                    hmargin = 6,
                    vmargin = 4,
                    valign = "center",
                    color = Styles.textColor,

                    hover = gui.Tooltip("Add a condition"),
                    press = function(element)
                        CharacterPanel.AddConditionMenu{
                            tokens = {m_token},
                            button = element,
                        }
                    end,
                }

            end

            if newPanels then
                local children = {}
                for _,child in ipairs(ongoingEffectPanels) do
                    children[#children+1] = child
                end
                children[#children+1] = addConditionButton
                element.children = children
            end


        end,



    }

    return resultPanel
end

CharacterPanel.CreateCharacterDetailsPanel = function(m_token)

    local newTacPanel = dmhub.GetSettingValue("newTacPanel") == true
    local oldTacPanel = not newTacPanel

    local m_effectEntryPanels = {}
    local m_customConditionPanels = {}

    local resultPanel = nil

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        styles = {
            {
                selectors = {"deleteItemButton"},
                opacity = 0,
            },
            {
                selectors = {"deleteItemButton", "parent:hover"},
                opacity = 1,
            },
        },

        refreshToken = function(element, tok)
            m_token = tok
        end,

        --add to combat button.
        oldTacPanel and gui.Button{
            classes = {"collapsed"},
            width = 320,
            height = 30,
            text = "Add to Combat",
            refreshToken = function(element, tok)
                local q = dmhub.initiativeQueue
                if q == nil or q.hidden then
                    element:SetClass("collapsed", true)
                    return
                end

                element:SetClass("collapsed", tok.properties:try_get("_tmp_initiativeStatus") ~= "NonCombatant")
            end,

            click = function(element)
                Commands.rollinitiative()
            end,
        } or nil,

        oldTacPanel and gui.Panel{
            classes = {"collapsed"},
            width = "100%",
            height = "auto",

            refreshToken = function(element)
                local creature = m_token.properties
                if creature == nil then
                    if m_token == nil then
                        if CharacterSheet.instance and CharacterSheet.instance.data and CharacterSheet.instance.data.info then
                            m_token = CharacterSheet.instance.data.info.token
                        end
                    end
                    if m_token then creature = m_token.properties end
                end
                if creature and creature:IsCompanion() then
                    creature:DisplayCharacterPanel(m_token, element)
                else
                    element:SetClass("collapsed", true)
                end
            end,
        } or nil,

        newTacPanel and TacPanel.Statistics() or nil,
        newTacPanel and TacPanel.Testing() or nil,
        newTacPanel and TacPanel.Routines() or nil,
        newTacPanel and TacPanel.AurasEmitting() or nil,
        newTacPanel and TacPanel.PersistentAbilities() or nil,
        newTacPanel and TacPanel.HeroicResources() or nil,
        newTacPanel and TacPanel.Conditions() or nil,
        newTacPanel and TacPanel.SkillLanguages() or nil,
        newTacPanel and TacPanel.Features() or nil,
        newTacPanel and TacPanel.Notes() or nil,

        --heroic resource panel.
        oldTacPanel and gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            styles = {
                {
                    classes = {"label"},
                    color = "white",
                },
                {
                    classes = {"label", "parent:consumed"},
                    transitionTime = 0.5,
                    color = "grey",
                },
                {
                    classes = {"strikethrough"},
                    bgimage = "panels/square.png",
                    bgcolor = "white",
                    halign = "left",
                    valign = "center",
                    height = 1,
                    width = "0%",
                },
                {
                    classes = {"strikethrough", "parent:consumed"},
                    transitionTime = 0.5,
                    width = "60%",
                    bgcolor = "grey",
                },
            },
            data = {
                panels = {},
                headingPanel = nil,
            },
            refreshToken = function(element)
                if element.data.headingPanel == nil then
                    element.data.headingPanel = element.children[1]
                end
                local creature = m_token.properties
                local checklist = creature:GetHeroicResourceChecklist()
                if checklist == nil or #checklist == 0 then
                    element:SetClass("collapsed", true)
                    element.children = {element.data.headingPanel}
                    element.data.panels = {}
                    return
                end

                element:SetClass("collapsed", false)

                local panels = element.data.panels
                local newPanels = {}

                local children = {element.data.headingPanel}
                for _,entry in ipairs(checklist) do

                    local consumed
                    local q = dmhub.initiativeQueue
                    local record = creature:try_get("heroicResourceRecord")
                    if q == nil or q.hidden or entry.mode == "recurring" or record == nil or record[entry.guid] == nil or record[entry.guid] ~= creature:GetResourceRefreshId(entry.mode or "encounter") then
                        consumed = false
                    else
                        consumed = true
                    end

                    local panel = panels[entry.guid] or gui.Panel{
                        classes = {cond(consumed, "consumed")},
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                        linger = gui.Tooltip(entry.details),
                        rightClick = function(element)
                            local q = dmhub.initiativeQueue
                            if q == nil or q.hidden then
                                return
                            end

                            local resourceName = m_token.properties:GetHeroicResourceName()

                            local entries = {}
                            if element:HasClass("consumed") then

                            else
                                entries[#entries+1] = {
                                    text = "Trigger Manually",
                                    click = function()
                                        element.popup = nil
                                        if m_token == nil or not m_token.valid then
                                            return
                                        end


                                        m_token:ModifyProperties{
                                            description = tr("Trigger resource gain"),
                                            execute = function()


                                                local updateid = m_token.properties:GetHeroicResourceChecklistRefreshId(entry.guid)
                                                if updateid == nil then
                                                    return
                                                end

                                                local record = m_token.properties:get_or_add("heroicResourceRecord", {})
                                                local checklistBefore = {}
                                                checklistBefore[entry.guid] = {record[entry.guid], updateid}
                                                record[entry.guid] = updateid

                                                local quantity = ExecuteGoblinScript(entry.quantity, GenerateSymbols(m_token.properties), 0, "Heroic Resource Amount")
                                                local amount = m_token.properties:RefreshResource(CharacterResource.heroicResourceId, "unbounded", quantity, entry.name)
                                                if amount > 0 then
                                                    chat.SendCustom(
                                                        ResourceChatMessage.new{
                                                            tokenid = m_token.charid,
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
                                }
                            end

                            if #entries > 0 then
                                element.popup = gui.ContextMenu{
                                    entries = entries
                                }
                            end
                        end,
                        gui.Panel{
                            classes = {"strikethrough"},
                            floating = true,
                        },
                        gui.Label{
                            height = "auto",
                            width = 160,
                            halign = "left",
                            lmargin = 6,
                            fontSize = 12,
                            minFontSize = 6,
                            text = entry.name,
                            textWrap = false,
                        },
                        gui.Label{
                            width = "auto",
                            height = "auto",
                            halign = "left",
                            lmargin = 12,
                            fontSize = 12,
                            text = string.format("+%d", tonumber(entry.quantity) or 1),
                            refreshToken = function(element)
                                if safe_toint(entry.quantity) then
                                    return
                                end
                                local creature = m_token.properties
                                local text = dmhub.EvalGoblinScript(entry.quantity, creature:LookupSymbol())
                                element.text = string.format("+%s", text)
                            end,
                        },
                        gui.Panel{
                            width = 10,
                            height = 10,
                            valign = "center",
                            halign = "right",
                            bgcolor = "white",
                            bgimage = "game-icons/clockwise-rotation.png",
                            rmargin = 4,
                        },
                        gui.Label{
                            width = 60,
                            height = "auto",
                            halign = "right",
                            fontSize = 12,
                            color = "white",
                            text = g_refreshChecklistName[entry.mode or "encounter"] or "always",
                        }
                    }

                    if consumed then
                        panel:SetClass("consumed", true)
                    else
                        panel:SetClassImmediate("consumed", false)
                    end

                    newPanels[entry.guid] = panel
                    children[#children+1] = panel
                end

                element.data.panels = newPanels
                element.children = children
            end,

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",

                hover = function(element)
                    local desc = m_token.properties:GetHeroicResourceName()
                    local negativeValue = m_token.properties:CalculateNamedCustomAttribute("Negative Heroic Resource")
                    local text = nil
                    if negativeValue > 0 then
                        text = string.format("%s may go as low as -%d", desc, negativeValue)
                    end
                    element.tooltip = gui.StatsHistoryTooltip{ text = text, description = desc, entries = m_token.properties:GetStatHistory(CharacterResource.heroicResourceId):GetHistory() }
                end,


                gui.Label{
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    fontSize = 16,
                    color = Styles.textColor,
                    text = "Heroic Resource",
                    refreshToken = function(element)
                        local creature = m_token.properties
                        if not creature:IsHero() then
                            return
                        end

                        element.text = string.format("<b>%s</b>:", creature:GetHeroicResourceName())
                    end,

                },

                gui.Label{
                    editable = true,
                    numeric = true,
                    lmargin = 8,
                    width = 40,
                    characterLimit = 3,
                    fontSize = 16,
                    height = "auto",

                    refreshToken = function(element)
                        local creature = m_token.properties
                        if not creature:IsHero() then
                            return
                        end

                        local resources = creature:GetHeroicOrMaliceResources()
                        element.text = tostring(resources)
                    end,

                    change = function(element)
                        local amount = tonumber(element.text)
                        if amount == nil then
                            element:FireEvent("refreshToken")
                            return
                        end
                        local diff = amount - m_token.properties:GetHeroicOrMaliceResources()
                        if diff == 0 then
                            return
                        end
                        m_token:ModifyProperties{
                            description = "Change Heroic Resource",
                            execute = function()
                                if diff > 0 then
                                    m_token.properties:RefreshResource(CharacterResource.heroicResourceId, "unbounded", diff)
                                else
                                    m_token.properties:ConsumeResource(CharacterResource.heroicResourceId, "unbounded", -diff)
                                end
                            end,
                        }
                    end,

                }
            },
        } or nil,

        --growing resource table, only relevant for characters that have growing resources.
        oldTacPanel and gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            bgimage = true,
            vmargin = 4,

            --title label.
            gui.Label{
                bold = true,
                width = "auto",
                height = "auto",
                fontSize = 16,
                color = Styles.textColor,
            },
            data = {
                children = {},
                title = nil,
            },
            styles = {
                {
                    selectors = {"label"},
                    fontSize = 12,
                    color = Styles.textColor,
                },
                {
                    selectors = {"label", "filled"},
                    color = "black",
                    bold = true,
                },
                {
                    selectors = {"label", "expiring"},
                    color = "black",
                    bold = true,
                },
                {
                    selectors = {"row"},
                    width = "100%",
                    height = "auto",
                    vpad = 2,
                },
                {
                    selectors = {"row", "even"},
                    bgcolor = "black",
                },
                {
                    selectors = {"row", "odd"},
                    bgcolor = "#222222",
                },
                {
                    selectors = {"row", "filled"},
                    bgcolor = "#ffaaaa",
                },
                {
                    selectors = {"row", "expiring"},
                    bgcolor = "#aa9999",
                },
            },
            refreshToken = function(element)
                local creature = m_token.properties
                if (not creature:IsHero()) and (not creature:IsCompanion()) then
                    element:SetClass("collapsed", true)
                    return
                end

                local growingResources = creature:GetGrowingResourcesTable()
                if growingResources == nil then
                    element:SetClass("collapsed", true)
                    return
                end

                if element.data.title == nil then
                    element.data.title = element.children[1]
                end

                element.data.title.text = growingResources.name

                local progression = growingResources.progression

                element:SetClass("collapsed", false)

                local characterLevel = creature:CharacterLevel()
                local characterResources = creature:GetProgressionResource()
                local resourcesHigh = creature:GetProgressionResourceHighWaterMark()


                local children = element.data.children
                local startingChildren = #children

                local index = 1

                for i,entry in ipairs(progression) do
                    if (tonumber(entry.level) or 0) <= characterLevel then
                        local row = children[index] or gui.Panel{
                            classes = {"row", cond(i%2 == 0, "even", "odd")},
                            bgimage = true,
                            flow = "horizontal",
                            data = {
                                entry = nil,
                            },
                            update = function(element, entry)
                                element.data.entry = entry
                            end,
                            hover = function(element)
                                if element.data.entry.tooltip ~= nil then
                                    gui.Tooltip(element.data.entry.tooltip)(element)
                                end
                            end,
                            gui.Label{
                                width = 16,
                                height = 16,
                                lmargin = 4,
                                update = function(element, entry)
                                    element.text = entry.resources
                                end,
                            },
                            gui.Label{
                                halign = "right",
                                width = "100%-24",
                                height = "auto",
                                update = function(element, entry)
                                    element.text = StringInterpolateGoblinScript(entry.description, creature)
                                end,
                            }
                        }

                        children[index] = row

                        index = index + 1

                        row:FireEventTree("update", entry)
                        row:SetClassTree("filled", entry.resources <= characterResources)
                        row:SetClassTree("expiring", entry.resources > characterResources and entry.resources <= resourcesHigh)
                    end
                end

                for i=1,#children do
                    children[i]:SetClass("collapsed", i >= index)
                end

                if #children > startingChildren then
                    local newChildren = {element.data.title}
                    for _,child in ipairs(children) do
                        newChildren[#newChildren+1] = child
                    end
                    element.children = newChildren
                end
            end,
        } or nil,

        oldTacPanel and RoutinesPanel(m_token) or nil,
        oldTacPanel and PersistencePanel(m_token) or nil,

        --custom effects.
        oldTacPanel and gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",


            gui.Input{
                width = "80%",
                height = "auto",
                halign = "left",
                fontSize = 12,
                characterLimit = 60,
                placeholderText = "Add Custom Condition...",
                change = function(element)
                    local text = trim(element.text)
                    if text ~= "" then

                        m_token:BeginChanges()
                        local customConditions = m_token.properties:get_or_add("customConditions", {})
                        local key = dmhub.GenerateGuid()
                        customConditions[key] = {
                            text = text,
                            timestamp = dmhub.serverTimeMilliseconds,
                        }
                        m_token:CompleteChanges("Add Custom Condition")
                    end

                    element.text = ""

                    --instantly refresh.
                    resultPanel:FireEventTree("refreshToken", m_token)
                end,
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                refreshToken = function(element)
                    local children = {}
                    local customConditionPanels = {}
                    for key,entry in pairs(m_token.properties:try_get("customConditions", {})) do
                        local panel
                        panel = m_customConditionPanels[key] or gui.Panel{
                            data = {
                                ord = entry.timestamp,
                            },
                            bgimage = "panels/square.png",
                            bgcolor = "clear",
                            width = "100%",
                            height = "auto",
                            flow = "horizontal",
                            valign = "center",
                            halign = "center",
                            vmargin = 4,
                            hmargin = 4,

                            gui.Label{
                                width = 280,
                                height = "auto",
                                halign = "left",
                                valign = "center",
                                characterLimit = 60,
                                editable = true,
                                fontSize = 14,
                                minFontSize = 8,
                                textWrap = false,
                                rmargin = 4,
                                color = Styles.textColor,
                                text = entry.text,
                                change = function(element)
                                    m_token:BeginChanges()
                                    local customConditions = m_token.properties:get_or_add("customConditions", {})
                                    local newKey = dmhub.GenerateGuid()
                                    local newEntry = DeepCopy(entry)
                                    newEntry.text = trim(element.text)
                                    customConditions[key] = nil
                                    if newEntry.text ~= "" then
                                        customConditions[newKey] = newEntry
                                    end
                                    m_token:CompleteChanges("Change Custom Condition")

                                    --instantly refresh.
                                    resultPanel:FireEventTree("refreshToken", m_token)
                                end,
                            },

                            gui.DeleteItemButton{
                                width = 12,
                                height = 12,

                                lmargin = 24,
                                halign = "left",
                                valign = "center",
                                press = function(element)
                                    m_token:BeginChanges()
                                    m_token.properties:get_or_add("customConditions", {})[key] = nil
                                    m_token:CompleteChanges("Remove Custom Condition")
                                    panel:DestroySelf() --update change immediately.
                                end,
                            },
                        }

                        children[#children+1] = panel
                        customConditionPanels[key] = panel
                    end

                    table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

                    m_customConditionPanels = customConditionPanels
                    element.children = children
                end,
            }
        } or nil,

        --auras.
        oldTacPanel and AurasEmittingPanel(m_token) or nil,

        --ongoing effects.
        oldTacPanel and gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",

            refreshToken = function(element)
                local creature = m_token.properties
				local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects")
				local activeOngoingEffects = creature:ActiveOngoingEffects()

                local index = 1
                for _,effectEntry in ipairs(activeOngoingEffects) do
                    local effectInfo = ongoingEffectsTable[effectEntry.ongoingEffectid]
                    if effectInfo ~= nil and effectInfo.statusEffect then

                        m_effectEntryPanels[index] = m_effectEntryPanels[index] or gui.Panel{
                            bgimage = "panels/square.png",
                            bgcolor = "clear",
                            width = "100%",
                            height = "auto",
                            flow = "horizontal",
                            valign = "center",
                            halign = "center",
                            vmargin = 4,
                            hmargin = 4,

                            data = {
                                info = nil,
                                entry = nil,
                            },

                            refreshStatus = function(element, info, entry)
                                element.data.info = info
                                element.data.entry = entry
                            end,

                            clearHighlights = function(element)
                                if element.data.highlights ~= nil then
                                    for i,highlight in ipairs(element.data.highlights) do
                                        highlight:Destroy()
                                    end
                                    element.data.highlights = nil
                                end
                            end,

                            destroy = function(element)
                                element:FireEvent("clearHighlights")
                            end,

                            dehover = function(element)
                                element:FireEvent("clearHighlights")
                            end,

                            linger = function(element)
                                local stacksText = ""
                                if element.data.info.stackable then
                                    stacksText = string.format(" (%d stacks)", element.data.entry.stacks)
                                end
                                local casterText = ""
                                local caster = element.data.entry:DescribeCaster()
                                if caster ~= nil then
                                    casterText = string.format("\nInflicted by %s", caster)
                                end
								gui.Tooltip(string.format('%s%s: %s%s\n%s', element.data.info.name, stacksText, StringInterpolateGoblinScript(element.data.info.description, m_token.properties), casterText, element.data.entry:DescribeTimeRemaining()))(element)

                                element:FireEvent("clearHighlights")

                                if element.data.entry.bondid then
                                    local tokens = creature.GetTokensWithBoundOngoingEffect(element.data.entry.bondid)
                                    element.data.highlights = {}
                                    for i,tok in ipairs(tokens) do
                                        for j=i+1,#tokens do
                                            element.data.highlights[#element.data.highlights+1] = dmhub.HighlightLine{
                                                color = "red",
                                                a = tokens[i].pos,
                                                b = tokens[j].pos,
                                            }
                                        end
                                    end
                                end
                            end,

                            children = {
                                gui.DiamondButton{
                                    width = 24,
                                    height = 24,
                                    hmargin = 6,
                                    valign = "center",
                                    halign = "left",

                                    refreshStatus = function(element, info, entry)
                                        element:FireEvent("icon", info:GetDisplayIcon())
                                        element:FireEvent("display", info:GetDisplayDisplay())
                                    end,

                                },

                                gui.Label{
                                    width = 120,
                                    height = "auto",
                                    halign = "left",
                                    valign = "center",
                                    fontSize = 14,
                                    minFontSize = 8,
                                    textWrap = false,
                                    rmargin = 4,
                                    color = Styles.textColor,
                                    refreshStatus = function(element, info, entry)
                                        local stacksText = ""
                                        if entry.stacks ~= nil and entry.stacks > 1 then
                                            stacksText = string.format(" x %d", entry.stacks)
                                        end
                                        element.text = info.name .. stacksText
                                    end,
                                },

                                --duration label
                                gui.Label{
                                    width = "auto",
                                    height = "auto",
                                    minWidth = 100,
                                    maxWidth = 160,
                                    fontSize = 14,
                                    bold = true,
                                    halign = "left",
                                    valign = "center",
                                    color = Styles.textColor,
                                    characterLimit = 2,
                                    textAlignment = "left",

                                    refreshStatus = function(element, info, entry)
                                        element.text = entry:DescribeTimeRemaining()
                                    end,
                                },

                                gui.DeleteItemButton{
                                    width = 12,
                                    height = 12,

                                    lmargin = 24,
                                    halign = "left",
                                    valign = "center",
                                    data = {
                                        entry = nil,
                                    },
                                    refreshStatus = function(element, info, entry)
                                        element.data.entry = entry
                                    end,
                                    press = function(element)
                                        m_token:BeginChanges()
                                        m_token.properties:RemoveOngoingEffect(element.data.entry.ongoingEffectid)
                                        m_token:CompleteChanges("Remove Ongoing Effect")
                                    end,
                                },

                            },
                        }

                        m_effectEntryPanels[index]:FireEventTree("refreshStatus", effectInfo, effectEntry)

                        index = index+1
                    end
                end

                while #m_effectEntryPanels >= index do
                    m_effectEntryPanels[#m_effectEntryPanels] = nil
                end

                element.children = m_effectEntryPanels

            end,

        } or nil,

        oldTacPanel and AurasAffectingPanel(m_token) or nil,

        --inflicted conditions.
        oldTacPanel and InflictedConditionsPanel(m_token) or nil,

		oldTacPanel and CharacterPanel.CharacteristicsPanel(m_token) or nil,
		oldTacPanel and CharacterPanel.ImportantAttributesPanel(m_token) or nil,

		oldTacPanel and gui.Panel{
			width = "100%",
			height = "auto",
            flow = "vertical",
            data = {
                children = {},
            },
			bmargin = 4,
            refreshToken = function(element)
                local children = element.data.children
                local creature = m_token.properties
				local entries = creature:ResistanceEntries()

                for i=1,#entries do
                    local label = children[i] or gui.Label{
                        data = {},
                        width = "auto",
                        height = "auto",
                        fontSize = 14,
                        bold = true,
			            color = Styles.textColor,
                        hover = function(element)
                            gui.Tooltip{text = element.data.tooltip, fontSize = 14}(element)
                        end,
                    }

                    label.data.tooltip = entries[i].entry.source
                    label.text = entries[i].text

                    children[i] = label
                end

                for i,child in ipairs(children) do
                    child:SetClass("collapsed", i > #entries)
                end

                element.children = children
			end,
		} or nil,

		oldTacPanel and CharacterPanel.SkillsPanel(m_token) or nil,
		oldTacPanel and CharacterPanel.LanguagesPanel(m_token) or nil,
        oldTacPanel and CharacterPanel.AbilitiesPanel(m_token) or nil,
        oldTacPanel and CharacterPanel.NotesPanel(m_token) or nil,
    }

    return resultPanel
end

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
			bgimage = "panels/square.png",
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
                end
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
                                    m_token.properties:SetHeroTokens(n, "Session Reset")
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
                            m_token.properties:SetHeroTokens(n, "Set manually")
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
				bgimage = "panels/square.png",
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

local multiEditBaseFunction = CharacterPanel.CreateMultiEdit

local g_nseq = 0

CharacterPanel.CreateMultiEdit = function()
	if mod.unloaded then
		return multiEditBaseFunction()
	end

	local newTacPanel = dmhub.GetSettingValue("newTacPanel") == true
	if newTacPanel then
		return TacPanel.MultiEdit()
	end

	g_nseq = g_nseq + 1
	local m_nseq = g_nseq


	local m_tokens
	local resultPanel

	local monsterSquadInput = gui.Input{
		fontSize = 16,
		placeholderText = "Enter name...",
		characterLimit = 24,
		selectAllOnFocus = true,
		width = 200,
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

	local m_selectedSquadId = nil
	local monsterSquadColorPicker = gui.ColorPicker{
		width = 24,
		height = 24,
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

			--notify the game to update to show the new color.
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

    local addToInitiativeButton = gui.Button{
        classes = {"collapsed"},
        width = 320,
        height = 30,
        text = "Add to Combat",
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

        click = function(element)
            Commands.rollinitiative()
        end,
    }

    local groupInitiativeButton = gui.Button{
        width = 320,
        height = 30,
        text = "Group Initiative",
        tokens = function(element)
            --don't show if tokens all share the same initiative already.
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

        click = function(element)
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
                --mark this initiativeid as being on the players side.
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
    }

    local ungroupInitiativeButton = gui.Button{
        width = 320,
        height = 30,
        text = "Ungroup Initiative",
        tokens = function(element)
            local tokens = dmhub.allTokens
            local haveInitiativeGrouping = false

            --only allow ungrouping of initiative if there are multiple tokens sharing the
            --same id that are from different squads.
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

        click = function(element)
            local guid = dmhub.GenerateGuid()
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
    }



	local makeCaptainButton = gui.Button{
		width = 320,
		height = 30,
		text = "Make Captain",
		click = function(element)
            local initiativeGrouping = nil
            local allTokens =dmhub.allTokens

            local charids = {}
            for _,tok in ipairs(m_tokens) do
                charids[tok.charid] = true
            end
            local initiativeGroupingsSeen = {}

            --find an initiativeid that is available
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

            if initiativeGrouping == false or element.text ~= "Make Captain" then
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
							if element.text == "Make Captain" then
								tok.properties.minionSquad = m_selectedSquadId
							else
								tok.properties.minionSquad = nil
							end
						end,
					}
                elseif tok.properties.initiativeGrouping ~= initiativeGrouping and element.text == "Make Captain" then
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
				--search the map for any other captain and remove it.
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
	}

	local formSquadButton = gui.Button{
        classes = {"collapsed"},
		width = 320,
		height = 30,
		text = "Form Squad",
		click = function(element)
            DrawSteelMinion.FormSquad(dmhub.selectedOrPrimaryTokens)
		end,
	}


	local monsterSquadPanel = gui.Panel{
		height = 30,
		width = "100%",
		flow = "horizontal",
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
					--this is already the captain. Can edit this squad.
					nminions = nminions + 1
					makeCaptainButton.text = "Remove Captain"
				else
					makeCaptainButton.text = "Make Captain"
					m_selectedSquadId = squadid
				end
			end

			makeCaptainButton:SetClass("collapsed", not showCaptainButton)

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
            formSquadButton:SetClass("collapsed", not haveFormSquad)
		end,
		gui.Label{
			width = 60,
			height = "auto",
			text = "Squad:",
			fontSize = 14,
			valign = "center",
		},

		monsterSquadInput,

		monsterSquadColorPicker,
	}

	local monsterEVPanel = gui.Panel{
		height = "auto",
		width = "100%",
		flow = "horizontal",
		gui.Label{
			width = "auto",
			height = "auto",
			text = "",
			fontSize = 14,

			multimonitor = "eds",
			monitor = function(element)
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
					return
				end

				local ev = 0
				for _,tok in ipairs(monsterTokens) do
                    if tok.properties.minion then
					    ev = ev + tok.properties.ev/GameSystem.minionsPerSquad
                    else
					    ev = ev + tok.properties.ev
                    end
				end

                ev = round(ev)

				local edsDescription
				local eds = g_edsSetting:Get()

				if ev <= eds/2 then
					edsDescription = "<color=#66ff66>Trivial</color>"
				elseif ev <= eds then
					local val = ev
					while val % 5 ~= 0 do
						val = val + 1
					end

					if val - eds/2 >= eds - val then
						edsDescription = "<color=#ffff66>Standard</color>"
					else
						edsDescription = "<color=#66ff66>Easy</color>"
					end
				elseif ev <= eds + 10 then
					edsDescription = "<color=#ff6666>Hard</color>"
				else
					edsDescription = "<color=#990000>Extreme</color>"
				end

				element.text = string.format("%d monsters selected, EV: %d (<b>%s</b>)", #monsterTokens, ev, edsDescription)
			end,
		},
	}

	resultPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
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

		multiEditBaseFunction(),

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",

            addToInitiativeButton,
            groupInitiativeButton,
            ungroupInitiativeButton,
			makeCaptainButton,
            formSquadButton,
			monsterSquadPanel,

			gui.Panel{
				flow = "horizontal",
				width = "auto",
				height = "auto",
				gui.Label{
					width = "auto",
					height = "auto",
					text = "EDS:",
					fontSize = 14,
				},
				gui.Label{
					editable = true,
					width = 100,
					height = "auto",
					fontSize = 14,
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
				}

			},
			monsterEVPanel,


		}
	}


	return resultPanel
end


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

function CharacterPanel.NotesPanel(token)
    local m_cache = nil
    local resultPanel
    resultPanel = gui.Label{
        width = "100%",
        height = "auto",
        fontSize = 12,
        tmargin = 8,
        markdown = true,
        links = true,
        press = function(element)
            if element.linkHovered ~= nil then
                dmhub.OpenTutorialVideo(element.linkHovered)
            end
        end,
        refreshToken = function(element, token)
            local creature = token.properties
            local notes = creature:try_get("notes")
            if dmhub.DeepEqual(m_cache, notes) then
                return
            end

            local text = ""
            m_cache = DeepCopy(notes)
            if notes ~= nil then
                for _,note in ipairs(notes) do
                    if note.text ~= nil and note.text ~= "" then
                        local s = ""
                        if text ~= "" then
                            s = "\n\n"
                        end

                        text = string.format("%s%s##### %s\n%s", s, text, note.title, note.text)
                    end
                end
            end

            element.text = text
        end,
    }

    return resultPanel
end

function CharacterPanel.AbilitiesPanel(token)
    local resultPanel

    local m_panels = {}

	resultPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		vmargin = 6,
		styles = {
			{
                selectors = {"notesLabel"},
				fontSize = 14,
                color = Styles.textColor,
                width = "90%",
                height = "auto",
                halign = "center",
			},
		},

        refreshToken = function(element, token)
            local creature = token.properties
            local features = creature:try_get("characterFeatures")
            if features == nil or #features == 0 then
                element:SetClass("collapsed", true)
            else
                element:SetClass("collapsed", false)

                local panelIndex = 1

                if creature.withCaptain and creature.minion then
                    local squad = creature:try_get("_tmp_minionSquad")
                    local hasCaptain = squad ~= nil and squad.hasCaptain
                    local panel = m_panels[panelIndex] or gui.Label{
                        classes = {"notesLabel"},
                        markdown = true,
                    }

                    local hasCaptainColor = cond(hasCaptain, "#ff", "#55")

                    local implemented = DrawSteelMinion.GetWithCaptainEffect(creature.withCaptain) ~= nil
                    local implementedColor = cond(implemented, "#ff", "#55")

                    panel.text = string.format("<b><alpha=%s>With Captain</b> <alpha=%s>%s<alpha=#ff>", hasCaptainColor, implementedColor, creature.withCaptain)

                    
                    panel:SetClass("collapsed", false)
                    m_panels[panelIndex] = panel
                    panelIndex = panelIndex + 1
                end

                for i,feature in ipairs(features) do
                    if feature.description ~= "" then
                        local panel = m_panels[panelIndex] or gui.Label{
                            classes = {"notesLabel"},
                            markdown = true,
                        }

                        local implemented = feature:try_get("implementation", 1) ~= 1
                        local implementedColor = cond(implemented, "#ff", "#55")

                        panel.text = string.format("<b>%s:</b> <alpha=%s>%s<alpha=#ff>", feature.name, implementedColor, feature.description)

                        panel:SetClass("collapsed", false)
                        m_panels[panelIndex] = panel
                        panelIndex = panelIndex + 1
                    end
                end

                for i=panelIndex,#m_panels do
                    m_panels[i]:SetClass("collapsed", true)
                end

                element.children = m_panels
            end
        end,
	}

    return resultPanel
end

function CharacterPanel.LanguagesPanel(token)
	local resultPanel

    resultPanel = gui.Label{
        width = "100%",
        height = "auto",
        textAlignment = "left",
        fontSize = 14,
		create = function(element)
			element:FireEvent("refreshToken", token)
		end,
		refreshToken = function(element, token)
            local text = "<b>Languages:</b> "
			local languagesTable = dmhub.GetTable(Language.tableName) or {}
            local first = true
            local languages = {}
            for langid,_ in pairs(token.properties:LanguagesKnown()) do
                local language = languagesTable[langid]
                if language then
                    languages[#languages+1] = language
                end
            end

            table.sort(languages, function(a,b)
                return a.name < b.name
            end)

            for _,language in ipairs(languages) do
                if not first then
                    text = text .. ", "
                end
                text = text .. language.name
                first = false
            end

            if first then
                text = text .. "None"
            end

            element.text = text
        end,
    }

    return resultPanel
end

function CharacterPanel.SkillsPanel(token)
	local resultPanel

	local panels = {}

	for _,cat in ipairs(Skill.categories) do
		local panel = gui.Label{
			width = "100%",
			height = "auto",
			textAlignment = "left",

			create = function(element)
				element:FireEvent("refreshToken", token)
			end,
			refreshToken = function(element, token)
				local proficiencyList = nil
				for i,skill in ipairs(Skill.SkillsInfo) do
					if skill.category == cat.id and token.properties:ProficientInSkill(skill) then
						if proficiencyList == nil then
							proficiencyList = skill.name
						else
							proficiencyList = proficiencyList .. ", " .. skill.name
						end
					end
				end
				
				if proficiencyList == nil then
					element:SetClass("collapsed", true)
				else
					element:SetClass("collapsed", false)
					element.text = string.format("<b>%s:</b> %s", cat.text, proficiencyList)
				end
			end,
		}

		panels[#panels+1] = panel
	end

	resultPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		vmargin = 6,
		styles = {
			{
				fontSize = 14,
			}
		},
		children = panels,
	}

	return resultPanel
end

--important attributes beyond characteristics
--e.g. things like stability etc.
function CharacterPanel.ImportantAttributesPanel(token)
    local m_tokenInfo = {
        token = token,
    }
	local m_token = token

    local resultPanel

    local movementPanel = gui.Label{
        text = "Speed",
        hover = GenerateAttributeCalculationTooltip(m_tokenInfo, "Speed", creature.GetBaseSpeed, creature.DescribeSpeedModifications),
       
		refreshToken = function(element)
            local movementSpeed = m_token.properties:CurrentMovementSpeed()
			local info = m_token.properties.movementTypeById[m_token.properties:CurrentMoveType()]
            local movementTypeInfo = ""
            if info ~= nil and info.id ~= "walk" then
                movementTypeInfo = string.format(" (%s)", info.name)
            end
            element.text = string.format("<b>Movement:</b> %d%s", movementSpeed, movementTypeInfo)
        end,
        press = function(element)
            gui.PopupOverrideAttribute {
                parentElement = element,
                token = m_token,
                attributeName = "Speed",
                baseValue = m_token.properties:GetBaseSpeed(),
                modifications = m_token.properties:DescribeSpeedModifications(),
            }
        end,
    }

    local disengageSpeedPanel = gui.Label{
        bgimage = true,
        bgcolor = "clear",
        text = "Disengage",
        hover = GenerateCustomAttributeCalculationTooltip(m_tokenInfo, "Disengage Speed"),
		refreshToken = function(element)
            local customAttr = CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"]
            if customAttr ~= nil then
                local result = m_token.properties:GetCustomAttribute(customAttr)
                element.text = string.format("<b>Disengage:</b> %s", tostring(result))
            else
                element.text = ""
            end
        end,
        press = function(element)
            gui.PopupOverrideAttribute {
                parentElement = element,
                token = m_token,
                attributeName = "Disengage Speed",
            }
        end,
    }


    local stabilityPanel = gui.Label{
        hover = GenerateAttributeCalculationTooltip(m_tokenInfo, "Stability",
        creature.BaseForcedMoveResistance,
        function(c)
            return c:DescribeModifications("forcedmoveresistance", c:BaseForcedMoveResistance())
        end),

        press = function(element)
            local baseStability = m_token.properties:BaseForcedMoveResistance()
            gui.PopupOverrideAttribute {
                parentElement = element,
                token = m_token,
                attributeName = "Stability",
                baseValue = baseStability,
                modifications = m_token.properties:DescribeModifications("forcedmoveresistance", baseStability),
            }
        end,
    }

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",

        styles = {
            {
                selectors = {"label"},
                fontSize = 14,
                width = "auto",
                height = "auto",
            },
        },

        movementPanel,
        disengageSpeedPanel,
        stabilityPanel,

		refreshToken = function(element, newToken)
            m_tokenInfo.token = newToken
            token = newToken
			m_token = newToken

            local stability = token.properties:Stability()
            stabilityPanel.text = string.format("<b>Stability:</b> %d", stability)
		end,
    }

    return resultPanel
end

function CharacterPanel.CharacteristicsPanel(token)

	local m_token = token

	local resultPanel

	local panels = {}

	for index,attrid in ipairs(creature.attributeIds) do
		local attrInfo = creature.attributesInfo[attrid]
		--local width = string.format("%.2f%%", (100/#creature.attributeIds))
		local halign = "center"
		if index == 1 then
			halign = "left"
		elseif index == #creature.attributeIds then
			halign = "right"
		end
		local panel = gui.Panel{
			width = "auto",
			height = "auto",
			halign = halign,
			flow = "vertical",
			bgimage = "panels/square.png",
			bgcolor = "clear",

			press = function(element)
				m_token.properties:ShowCharacteristicRollDialog(attrid)
			end,

            hover = function(element)
                if m_token == nil or (not m_token.valid) then
                    return
                end
                local text = ""
                local potency = m_token.properties:AttributeForPotencyResistance(attrid)
                if m_token.properties:GetAttribute(attrid):Modifier() ~= potency then
                    local attrName = creature.attributesInfo[attrid].description
                    text = string.format("Your %s counts as %s for resisting potencies.\nBasic %s Score: %d", attrName, ModifierStr(potency), attrName,  m_token.properties:GetAttribute(attrid):Value())
                    local modifications = m_token.properties:AttributeForPotencyResistanceDescription(attrid)
                    for _,modification in ipairs(modifications) do
                        text = string.format("%s\n%s: %s", text, modification.key, modification.value)
                    end
                end

                if text ~= "" then
                    gui.Tooltip(text)(element)
                end
            end,

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                gui.Label{
                    text = attrInfo.description,
                    height = 14,
                    width = "auto",
                    halign = "center",
                },
                gui.Label{
                    classes = {"asterisk"},
                    text = "*",
                    valign = "top",
                    width = "auto",
                    height = "auto",
                    create = function(element)
                        element:FireEvent("refreshToken", token)
                    end,
                    refreshToken = function(element, token)
                        element:SetClass("collapsed", token.properties:GetAttribute(attrid):Modifier() == token.properties:AttributeForPotencyResistance(attrid))
                    end,
                },
            },
			gui.Label{
				text = "0",
				width = "auto",
				height = 14,
				halign = "center",
				valign = "center",
				minWidth = 20,
				lmargin = 4,
				textAlignment = "left",
				create = function(element)
					element:FireEvent("refreshToken", token)
				end,
				refreshToken = function(element, token)
					element.text = ModifierStr(token.properties:GetAttribute(attrid):Modifier())
				end,

			},
		}

		panels[#panels+1] = panel
	end

	resultPanel = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = "auto",

		styles = {
			{
				height = 18,
				fontSize = 11,
				bold = true,
				uppercase = true,
			},
			{
				selectors = {"label"},
				color = "#dddddd",
			},
            {
                selectors = {"asterisk"},
                color = "#ff00ff",
            },
			{
				selectors = {"label", "parent:hover"},
				color = "#ffffff",
			},
		},

		children = panels,
		refreshToken = function(element, newToken)
            token = newToken
			m_token = newToken
		end,
	}

	return resultPanel

end

function CharacterPanel.SingleCharacterDisplaySidePanel(token)

    local newTacPanel = dmhub.GetSettingValue("newTacPanel") == true
    local oldTacPanel = not newTacPanel

	local characterDisplaySidebar

	local conditionsPanel = CharacterPanel.CreateConditionsPanel(token)

	local summaryPanel = oldTacPanel and gui.Panel{
		flow = "horizontal",
		styles = {
			{
				halign = "left",
				valign = "center",
				pad = 2,
				height = "auto",
				width = "100%",
				bgcolor = '#000000aa',
				borderColor = '#000000ff',
				borderWidth = 2,
				flow = 'horizontal',
			},
		},

		gui.Panel{
			id = "LeftPanel",
			valign = "top",
			width = string.format("%f%% height", Styles.portraitWidthPercentOfHeight),
			height = 140,
			bgimage = "panels/square.png",
			bgcolor = "white",
            borderWidth = 0,
			lmargin = 16,

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
                floating = true,
                width = "100%",
                height = "100%",
                bgcolor = "white",
			    borderWidth = 2,
			    borderColor = Styles.textColor,

                refreshCharacter = function(element, token)
                    local portrait = token.offTokenPortrait
                    element.bgimage = portrait

                    if portrait ~= token.portrait and not token.popoutPortrait then
                        element.selfStyle.imageRect = nil
                    else
                        element.selfStyle.imageRect = token:GetPortraitRectForAspect(Styles.portraitWidthPercentOfHeight*0.01, portrait)
                    end
                end,
            },

			CharacterPanel.DecoratePortraitPanel(token),

		},

		gui.Panel({
			id = 'RightPanel',
			valign = "top",
			style = {
				width = '60%',
				height = 'auto',
				halign = 'center',
				flow = 'vertical',
				vmargin = 0,
			},

			children = {

				CharacterPanel.ShowHitpoints(),
				conditionsPanel,
				CharacterPanel.CreateLookupPanel(),
                gui.Panel {

                    bgimage = true,
                    bgcolor = "clear",
                    height = 20,
                    width = "80%",
                    borderWidth = 0,
                    tmargin = 4,

                    flow = "horizontal",

                    refresh = function(element)
                        local tok = dmhub.currentToken
                        if tok ~= nil then
                            if (not tok.properties:CanFly()) and (not tok.canCurrentlyClimb) then
                                element:SetClass("collapsed", true)
                            else
                                element:SetClass("collapsed", false)
                            end
                        end
                    end,


                    gui.Label {

                        text = "Flying: ",
                        color = "white",
                        fontSize = 20,
                        fontFace = "newzald",
                        width = 80,

                        refresh = function(element)
                            local tok = dmhub.currentToken
                            if tok ~= nil then
                                if tok.properties:CanFly() then
                                    element.text = string.format("Flying: " .. tostring(tok.floorAltitude))
                                elseif tok.canCurrentlyClimb then
                                    element.text = string.format("Climb: " .. tostring(tok.floorAltitude))
                                end
                            end
                        end


                    },

                    gui.Button {
                        text = "-",
                        width = 16,
                        height = 16,


                        click = function()
                            local tok = dmhub.currentToken
                            if tok ~= nil then
                                if tok.properties:CanFly() then
                                    tok.properties:SetAndUploadCurrentMoveType("fly")
                                elseif tok.properties:CanClimb() then
                                    tok.properties:SetAndUploadCurrentMoveType("climb")
                                end

                                tok:MoveVertical(tok.floorAltitude - 1)
                            end
                        end

                    },

                    gui.Button {
                        text = "+",
                        width = 16,
                        height = 16,

                        click = function()
                            local tok = dmhub.currentToken
                            if tok ~= nil then
                                if tok.properties:CanFly() then
                                    tok.properties:SetAndUploadCurrentMoveType("fly")
                                elseif tok.properties:CanClimb() then
                                    tok.properties:SetAndUploadCurrentMoveType("climb")
                                end

                                tok:MoveVertical(tok.floorAltitude + 1)
                            end
                        end

                    }


                },

                gui.Button {
                    text = "Light",
                    width = 50,
                    height = "auto",
                    tmargin = 10,


                    refresh = function(element)
                        local tok = dmhub.currentToken

                        if tok == nil then
                            return
                        end

                        if tok.properties.selectedLoadout == 1 then
                            element.selfStyle.bgcolor = "white"
                            element.selfStyle.color = "black"
                        else
                            element.selfStyle.bgcolor = "clear"
                            element.selfStyle.color = "white"
                        end
                    end,

                    click = function()
                        Commands.light()
                    end

                },
			},
		}),
	} or nil

	characterDisplaySidebar = gui.Panel{
		id = 'sidebar',

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

        oldTacPanel and gui.Label{
            width = "100%",
            height = "auto",
            textAlignment = "center",
            fontSize = 16,
            minFontSize = 8,
            bold = true,
            halign = "center",
            vmargin = 4,

			refreshCharacter = function(element, token)
                local name = token:GetNameMaxLength(64)
                if name == nil or name == "" then
                    if token.properties:IsMonster() then
                        name = rawget(token.properties, "monster_type") or "Unknown Monster"
                    else
                        name = token.properties:RaceOrMonsterType()
                    end
                end
                element.text = name
            end,
        } or nil,
		summaryPanel,
        newTacPanel and TacPanel.Summary() or nil,
        newTacPanel and TacPanel.Stamina() or nil,
	}

	return characterDisplaySidebar
end
