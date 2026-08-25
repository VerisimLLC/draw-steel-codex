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

--- True when this element lives inside a character panel presented in
--- read-only mode (Party Member Controls = View: look but not touch).
--- The "readonly" class is set on the panel root by
--- CharacterPanel.CreatePinnedCharacterPanel and the sidebar character
--- list. Every handler in the tac panel that mutates game state (or
--- navigates to an editable surface) must call this first and bail out.
--- Checked at event time rather than build time because most chips and
--- rows are rebuilt on every refresh.
--- @param element Panel
--- @return boolean
function TacPanel.IsReadOnly(element)
    if not element.valid then
        return false
    end
    return element:HasClass("readonly") or element:FindParentWithClass("readonly") ~= nil
end

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
    -- Classic panel only: the reworked identity strip drops the whole ladder to
    -- monsterType / identRight so both halves share one scale.
    charLevel = 18,
    charClass = 26,
    charSubclass = 20,
    -- Second line of the identity strip's left column -- the monster's type
    -- ("SKELETON"), the hero's class ("CONDUIT"). A subheading, so it reads
    -- below the name rather than competing with it.
    monsterType = 15,
    -- Every line in the strip's right column -- EV, level/role, size, free
    -- strike -- is the same order of information, so they all share one size
    -- rather than the earlier ladder where EV shouted and the role whispered.
    -- 12pt fits the longest role ("LEVEL 1 HORDE ARTILLERY") in the column.
    identRight = 12,
    -- RESOURCES entries drop their label and show icon + number alone, so the
    -- number carries the whole entry and sizes up to match.
    resBadgeValue = 24,

    stamBoxTitle = 10,      -- Stamina panel
    stamBoxInput = 22,
    currentStamina = 24,
    maxStamina = 16,
    recoveryValue = 24,
    recoveryCount = 16,

    tempStamValue = 12,     -- Health bar: temp stam number
    tempStamLabel = 10,     -- Health bar: "TEMP" label
    tempStamClear = 8,      -- Health bar: clear button X

    barAdjustBtn = 14,      -- Health bar: the - / + hover buttons
    barAdjustTemp = 9,      -- Health bar: the TEMP hover button, and entry key
    barAdjustInput = 12,    -- Health bar: the adjust entry box

    movePanelTitle = 12,
    movePanelValue = 24,

    charTitle = 12,
    charValue = 30,

    -- Compact variants for the STATISTICS boxes. Same boxes and the same press
    -- handlers, just far less of the panel spent on them.
    --
    -- The values carry most of the bump and the labels almost none: measured on
    -- a 504px panel the row already fills ~457px, so there is about 10% of
    -- width to play with, and the labels ("ntuition") are what eat it. The row
    -- wraps rather than overflowing if a wider font or a narrower panel pushes
    -- it over.
    movePanelTitleCompact = 11,
    movePanelValueCompact = 18,
    charTitleCompact = 11,
    charValueCompact = 20,

    -- The resource strip and the RESOURCES badges were sized against the old
    -- compact numbers and should not follow them up; they have their own space
    -- constraints beside the stamina bar.
    resCompactTitle = 10,
    resCompactValue = 15,

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

--- The hero character-panel rework. OFF restores the panel as it stood before
--- it: see the CLASSIC CHARACTER PANEL block lower down.
---
--- Read at BUILD time, so a character panel already on screen keeps whatever it
--- was built with; close and reopen it after toggling.
local g_testCharPanel = setting{
    id = "dev:testcharpanel",
    description = "Use the reworked hero character panel.",
    default = false,
    storage = "preference",
    --The style rules resolve against the flag, so toggling has to re-resolve
    --them. Without this the panel kept whatever it was built with at load and
    --showed a mix: the reworked tree wearing the classic type scale.
    onchange = function()
        if TacPanel.RefreshStyles ~= nil then
            TacPanel.RefreshStyles()
        end
    end,
}

--- @return boolean
function TacPanel.UseTestPanel()
    return g_testCharPanel:Get() == true
end

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
--- How much to shrink a card's font ladder in this panel. The ability card's
--- sizes are tuned for it floating over the map at full size, and the trait /
--- perk cards copy that ladder to match it; repeated down a ~400px panel next
--- to 11-14px panel text they dwarf everything around them. Ability cards get
--- this through params.cardScale, trait and perk cards through the ms-* rules
--- inside BuildStyles, so the two card kinds stay the same size as each other.
---
--- Must stay OUT here: everything from BuildStyles' "function" line to its "end"
--- around line 2745 is one function body despite sitting at column 0, so a local
--- declared among the style tables is not visible to the card builders below.
local MS_CARD_SCALE = 0.8

function TacPanel.BuildStyles()
TacPanelStyles.TacPanel = ThemeEngine.MergeTokens{
    {   -- Portrait control icon chip: a clearly-visible rounded button over the
        -- portrait art, ringed with the bright accentHover color so it pops, and
        -- filled with the accent on hover.
        selectors = {"tpOutline"},
        bgcolor = "@bgAlt",
        borderColor = "@accentHover",
        border = 1,
        bgimage = true,
        pad = 4,
        cornerRadius = 6,
    },
    {   -- Quiet variant used by the monster portrait's button strip: no chrome
        -- at all, just the glyph. Boxing them made three outlined chips compete
        -- with the stat boxes beside them for a set of secondary controls.
        --
        -- Also tighter: tpOutline's pad of 4 put a 30px box around a 20px
        -- glyph, which is most of why the strip ate so much width. pad 2
        -- brings each button to 26 and lets the whole column narrow.
        selectors = {"tpOutline", "tp-outline-quiet"},
        bgcolor = "clear",
        border = 0,
        pad = 2,
        cornerRadius = 0,
    },
    {
        selectors = {"tpOutline", "tp-outline-quiet", "hover"},
        brightness = 1.4,
    },
    {
        selectors = {"tpOutline", "hover"},
        brightness = 2.0,
        -- bgcolor = "@accent",
        -- borderColor = "@accentHover",
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
    {   -- Drops a section's own bottom rule, for when something around it draws
        -- one instead. Used by the stamina section on monsters, whose column is
        -- narrower than the block it sits in.
        selectors = {"panel", "tacpanel", "no-rule"},
        border = 0,
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
    -- Portraits stand these buttons up as a vertical strip beside the image;
    -- that repositioning is applied directly in TacPanel.PortraitColumn because
    -- the panel declares its alignment inline. The bmargin here is the
    -- overlaid-across-the-bottom fallback, which PortraitColumn overrides.
    {
        selectors = {"panel", "portrait-buttons"},
        bmargin = 6,
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
    -- A dark plate behind the portrait image (added in
    -- TacPanel.PortraitColumn). portrait-body paints bgcolor "white" so the
    -- token art keeps its natural colours, which means anything the art does
    -- not cover reads as a pale hole; this backs it with the panel's own
    -- ground instead. It cannot go on portrait-body itself: bgcolor there
    -- tints the artwork.
    {
        selectors = {"panel", "portrait-backing"},
        width = "100%-2",
        height = "100%-2",
        valign = "center",
        halign = "center",
        bgimage = "panels/square.png",
        bgcolor = "@bg",
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
    -- Identity strip: two columns, the way the book heads a stat block.
    -- Monsters run name/type/keywords on the left and EV/level/size/free
    -- strike hard right; heroes run name/class/subclass against
    -- level/ancestry/kit. Pairing the lines saves two lines of panel height.
    {
        selectors = {"panel", "ident-left"},
        width = "54%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",
    },
    {
        --Roles run long ("HORDE ARTILLERY"), so the right column gets the
        --larger share and its labels shrink hard to stay inside it.
        selectors = {"panel", "ident-right"},
        width = "44%",
        height = "auto",
        halign = "right",
        valign = "top",
        flow = "vertical",
        --Right-aligned text otherwise ends exactly on the panel's right
        --edge and the last glyph gets shaved: measured at x=655 against a
        --panel edge of 655. This also has to clear the vertical scrollbar,
        --which sits inside that edge and was eating the breathing room.
        rmargin = 38,
        --The left column opens with a 28pt name, so its first line starts
        --well below the strip's top edge. At 12pt this column began flush
        --against it and read as crowded; drop it to sit nearer the name.
        tmargin = 6,
    },
    {
        selectors = {"label", "ident-right"},
        width = "100%",
        height = "auto",
        halign = "right",
        valign = "top",
        textAlignment = "right",
        textWrap = false,
        color = "@fgMuted",
        fontSize = TacPanelSizes.Fonts.identRight,
        minFontSize = 9,
    },
    {
        selectors = {"label", "summary-info", "char-name"},
        fontSize = TacPanelSizes.Fonts.charName,
        color = "@fgStrong",
    },
    {   -- Classic only: the hero's level, which the rework moved into the
        -- strip's right column.
        selectors = {"label", "summary-info", "level"},
        fontFace = "@label",
        fontSize = TacPanelSizes.Fonts.charLevel,
        color = "@fg",
    },
    {   -- Second line of the left column: the monster's type, the hero's
        -- class. Both labels are re-sized to fit in refreshCharacter; this is
        -- the size they start at. Classic sizes the hero's class far larger.
        selectors = {"label", "summary-info", "class"},
        fontSize = cond(TacPanel.UseTestPanel(),
            TacPanelSizes.Fonts.monsterType, TacPanelSizes.Fonts.charClass),
        color = "@fgMuted",
    },
    {   -- Third line: the hero's subclass, opposite the monster's keywords and
        -- the same size as them.
        selectors = {"label", "summary-info", "subclass"},
        fontSize = cond(TacPanel.UseTestPanel(),
            TacPanelSizes.Fonts.identRight, TacPanelSizes.Fonts.charSubclass),
        color = "@fgMuted",
    },
    {   -- Wraps the KIT label so the line has something hoverable. Auto width
        -- and halign right keeps it hard right like every other line here.
        selectors = {"panel", "ident-kit-row"},
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "top",
        flow = "horizontal",
    },
    {   -- Sizes to its text rather than the full column, so the hover target
        -- is the words themselves and not the empty space beside them.
        selectors = {"label", "ident-right", "hero-kit"},
        width = "auto",
        halign = "left",
    },
    {
        selectors = {"label", "summary-info", "monster-keywords"},
        fontSize = TacPanelSizes.Fonts.identRight,
        color = "@fgMuted",
    },
    {
        selectors = {"label", "summary-info", "ident-captain"},
        fontSize = TacPanelSizes.Fonts.identRight,
        color = "@fgMuted",
        textWrap = true,
        tmargin = 2,
    },
    {   -- The squad actually has a captain, so the bonus is live right now.
        selectors = {"label", "summary-info", "ident-captain", "captain-live"},
        color = "@accent",
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
        --@fgMuted like the other two. This was @fgPending, which is the
        --"provisional / not yet applied" token -- a different hue doing a job
        --it does not mean, so the three glyphs never matched at rest.
        selectors = {"character-sheet-btn"},
        bgimage = "icons/icon_app/icon_app_33.png",
        bgcolor = "@fgMuted",
    },
    {
        selectors = {"summoner-btn"},
        bgimage = "icons/icon_app/icon_app_2.png",
        bgcolor = "@fgMuted",
    },
    {   --lit when the monster currently has a summoner assigned.
        selectors = {"summoner-btn", "light-on"},
        bgcolor = "@accent",
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
    },

    -- Compact variant, used by the resource strip above the stamina bar: no
    -- frame, title and value on one line. The same treatment the characteristic
    -- boxes get in STATISTICS -- only the chrome goes, every handler stays.
    {
        selectors = {"panel", "tokenbox", "compact"},
        width = "auto",
        height = "auto",
        flow = "horizontal",
        bgcolor = "clear",
        border = 0,
        cornerRadius = 4,
        hpad = 5,
        vpad = 3,
        hmargin = 1,
        vmargin = 1,
        bmargin = 1,
    },
    {   -- hover wash carries the affordance the frame used to
        selectors = {"panel", "tokenbox", "compact", "hover"},
        bgcolor = "@bgAlt",
        brightness = 1,
    },
    {
        --No halign: in a horizontal flow an explicit halign PINS the child to
        --that edge instead of letting the flow sequence it, so the title and
        --the value land on top of each other.
        selectors = {"label", "tokenbox", "title", "parent:compact"},
        width = "auto",
        valign = "center",
        tmargin = 0,
        rmargin = 4,
        textAlignment = "left",
        fontSize = TacPanelSizes.Fonts.resCompactTitle,
    },
    {
        selectors = {"input", "tokenbox", "value", "parent:compact"},
        width = "auto",
        valign = "center",
        tmargin = 0,
        hmargin = 2,
        fontSize = TacPanelSizes.Fonts.resCompactValue,
    },
    {   -- Shrinks to sit on the line rather than tower over it.
        selectors = {"panel", "icon", "parent:compact"},
        width = 12,
        height = 12,
        valign = "center",
    },
    {   -- In RESOURCES the entry is its icon and number alone, so both grow
        -- back to full size; the label they replace is on the tooltip.
        selectors = {"panel", "icon", "parent:badge"},
        width = TacPanelSizes.TokenIcon.width,
        height = TacPanelSizes.TokenIcon.height,
        valign = "center",
    },
    {
        selectors = {"input", "tokenbox", "value", "parent:badge"},
        fontSize = TacPanelSizes.Fonts.resBadgeValue,
        valign = "center",
        hmargin = 4,
    },
    {
        selectors = {"panel", "tokenbox", "compact", "badge"},
        hpad = 8,
        vpad = 4,
    },
    {   -- Hero tokens' refresh button flows after the value rather than
        -- floating over the box's bottom-right corner. halign is explicit
        -- because a horizontal-flow child without one centres itself, and the
        -- base refresh-icon rule pins it right.
        selectors = {"refresh-icon", "parent:compact"},
        halign = "left",
        valign = "center",
        lmargin = 4,
        hmargin = 0,
        vmargin = 0,
    },
}
TacPanelStyles.Stamina = ThemeEngine.MergeTokens{
    {   -- Classic only: the row of DMG / STAMINA / HEAL / RECOVERIES / TEMP
        -- boxes above the bar. The rework folded those into the bar's hover
        -- controls and this rule went with them, which left the restored row
        -- with no width, flow or wrap at all.
        selectors = {"panel", "stamina-controls"},
        height = "auto",
        --Sits in the column beside the portrait rather than across the whole
        --panel, so it wraps: monsters fit on one line, heroes push the
        --recoveries box onto a second.
        width = "100%",
        wrap = true,
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
    -- The stamina BAR is the only thing in this area that carries status
    -- colour. These boxes were tinted red/green permanently, regardless of
    -- state, so the colour was decoration rather than signal -- and it made
    -- the one place that does signal (the bar) harder to read.
    --
    -- HEROES ONLY. Monsters fold these four into the bar's hover controls
    -- (TacPanel.BarAdjustControls) and collapse the boxes; heroes keep the
    -- row. See the gates in each builder below.
    {
        selectors = {"panel", "stamina-box", "harm"},
        borderColor = "@border",
    },
    {
        selectors = {"panel", "stamina-box", "stamina"},
        width = TacPanelSizes.Panels.stamBoxStam,
        borderColor = "@border",
    },
    {
        selectors = {"panel", "stamina-box", "heal"},
        borderColor = "@border",
    },
    {
        selectors = {"panel", "stamina-box", "recoveries"},
        width = TacPanelSizes.Panels.stamBoxRecoveries,
        borderColor = "@border",
    },
    {   -- Matches the tokenboxes beside it in the resource strip.
        selectors = {"panel", "stamina-box", "recoveries", "compact"},
        width = "auto",
        height = "auto",
        flow = "horizontal",
        border = 0,
        bgcolor = "clear",
        lmargin = 0,
        rmargin = 0,
        hpad = 5,
        vpad = 3,
        hmargin = 1,
        vmargin = 1,
    },
    {
        selectors = {"label", "stambox-title", "parent:compact"},
        width = "auto",
        valign = "center",
        halign = "left",
        rmargin = 4,
        textAlignment = "left",
        fontSize = TacPanelSizes.Fonts.resCompactTitle,
    },
    {
        selectors = {"label", "recovery-value", "parent:compact"},
        valign = "center",
        fontSize = TacPanelSizes.Fonts.resCompactValue,
    },
    {   -- The editable count: this is where you set how many recoveries the
        -- hero has left. minWidth keeps it a target you can click when it is
        -- empty; at "auto" alone an empty field has no width to hit.
        selectors = {"input", "recovery-count", "parent:compact"},
        width = "auto",
        minWidth = 14,
        valign = "center",
        textAlignment = "right",
        fontSize = TacPanelSizes.Fonts.resCompactValue,
    },
    {
        selectors = {"label", "recovery-max", "parent:compact"},
        valign = "center",
        lmargin = 2,
        fontSize = TacPanelSizes.Fonts.resCompactTitle,
    },
    -- Under the bar, recoveries reads as a key-value line in the same grammar
    -- as the IMMUNITY row below it: a bold muted key, then the values. The row
    -- carries the inset rather than the key, for the reason the cond-key rule
    -- gives -- padding on the label only inflates its box symmetrically.
    {
        selectors = {"panel", "stamina-box", "recoveries", "compact", "keyline"},
        hpad = 0,
        vpad = 0,
        hmargin = 0,
        vmargin = 0,
    },
    {   -- The same, for anything a mod registers into the strip.
        selectors = {"panel", "tokenbox", "compact", "keyline"},
        hpad = 0,
        vpad = 0,
        hmargin = 0,
        vmargin = 0,
    },
    {   -- The key, matched to TacPanel.Resistances and the conditions row.
        selectors = {"label", "stambox-title", "parent:keyline"},
        fontSize = TacPanelSizes.Fonts.resEntry,
        bold = true,
        color = "@fgMuted",
        rmargin = 6,
        hpad = 0,
    },
    {
        selectors = {"label", "tokenbox", "title", "parent:keyline"},
        fontSize = TacPanelSizes.Fonts.resEntry,
        bold = true,
        color = "@fgMuted",
        rmargin = 6,
        hpad = 0,
    },
    {   -- The values read at the same size as an immunity entry.
        selectors = {"label", "recovery-value", "parent:keyline"},
        fontSize = TacPanelSizes.Fonts.resEntry,
        color = "@fg",
    },
    {
        selectors = {"input", "recovery-count", "parent:keyline"},
        fontSize = TacPanelSizes.Fonts.resEntry,
        color = "@fg",
    },
    {
        selectors = {"label", "recovery-max", "parent:keyline"},
        fontSize = TacPanelSizes.Fonts.resEntry,
    },

    {   -- A row of compact resource readouts. Wraps, because how many entries
        -- a hero has depends on their class and on any mod that registers one.
        selectors = {"panel", "resource-strip"},
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "horizontal",
        wrap = true,
        bmargin = 4,
    },
    {   -- Centred across the RESOURCES section. Width auto plus halign center
        -- is the codebase idiom for centring a flow: at 100% the row would fill
        -- the section and its children would sequence from the left edge.
        --
        -- Auto width means this row does NOT wrap in practice, so a class that
        -- registers several more entries could outgrow the panel.
        selectors = {"panel", "resource-strip", "badges"},
        width = "auto",
        halign = "center",
    },
    {   -- Under the bar. The same inset the conditions row uses so the three
        -- key-value lines -- recoveries, immunity, conditions -- share a left
        -- edge; see the "cond-chips flush" rule.
        selectors = {"panel", "resource-strip", "under-bar"},
        width = "100%-12",
        lmargin = 12,
        halign = "left",
        valign = "top",
        tmargin = 4,
        bmargin = 0,
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
        color = "@fg",
    },
    {
        selectors = {"stambox-input", "heal"},
        color = "@fg",
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

    -- Adjust controls on the stamina bar itself: - / + / TEMP, each opening a
    -- small entry box in place. Hidden until the bar is hovered, so the bar
    -- reads as a bar until you go looking for the controls.
    {   -- Spans the bar so its three slots can sit left, centre and right. The
        -- clusters inside float, so they place themselves by halign and none of
        -- them pushes the others around.
        selectors = {"panel", "bar-adjust"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        hidden = 1,
    },
    {
        selectors = {"panel", "bar-adjust", "parent:hover"},
        hidden = 0,
    },
    {   -- Stays up while an entry box is open, wherever the pointer has gone.
        selectors = {"panel", "bar-adjust", "open"},
        hidden = 0,
    },
    {
        selectors = {"panel", "bar-adjust-row"},
        width = "auto",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "horizontal",
    },
    {
        selectors = {"panel", "bar-adjust-row", "left"},
        halign = "left",
        lmargin = 6,
    },
    {
        selectors = {"panel", "bar-adjust-row", "right"},
        halign = "right",
        rmargin = 6,
    },
    {   -- A panel wrapping a label rather than a bare label, matching every
        -- other small button in this panel.
        selectors = {"panel", "bar-adjust-btn"},
        width = 16,
        height = "100%",
        halign = "left",
        valign = "center",
        hmargin = 2,
        bgcolor = "clear",
    },
    {   -- "TEMP" is a word rather than a sign, so it sizes to its text.
        selectors = {"panel", "bar-adjust-btn", "temp"},
        width = "auto",
        hmargin = 4,
    },
    {
        selectors = {"label", "bar-adjust-glyph"},
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontSize = TacPanelSizes.Fonts.barAdjustBtn,
        color = "@fg",
    },
    {
        selectors = {"label", "bar-adjust-glyph", "temp"},
        width = "auto",
        fontSize = TacPanelSizes.Fonts.barAdjustTemp,
    },
    {
        selectors = {"label", "bar-adjust-glyph", "parent:hover"},
        color = "@accent",
        transitionTime = 0.2,
    },
    {
        selectors = {"label", "bar-adjust-glyph", "parent:press"},
        brightness = 0.5,
    },
    {   -- The entry box that replaces the buttons once one is picked.
        selectors = {"label", "bar-entry-key"},
        width = "auto",
        height = "auto",
        valign = "center",
        rmargin = 3,
        fontSize = TacPanelSizes.Fonts.barAdjustTemp,
        color = "@fgMuted",
    },
    {
        selectors = {"input", "bar-entry-input"},
        width = 42,
        height = 16,
        valign = "center",
        pad = 0,
        margin = 0,
        border = 1,
        borderColor = "@border",
        bgimage = true,
        bgcolor = "@bg",
        cornerRadius = 2,
        fontFace = "@number",
        fontSize = TacPanelSizes.Fonts.barAdjustInput,
        textAlignment = "center",
        color = "@fg",
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
        --Inline label-and-value cells are wider than the stacked ones, so the
        --five characteristics have to be able to fall to a second line at
        --larger font sizes. Heroes' fixed 16% cells never reach the edge.
        wrap = true,
        --Each column carries its own vertical padding, so 6 here sat on top of
        --it and left the row floating in the section.
        vpad = 2,
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
    },

    -- Compact (monster) variant: no frame, label and value on one line, and
    -- still pressable -- the press handler and hover/press feedback are
    -- untouched, only the chrome goes. The default box is "100% width" tall,
    -- i.e. square, which is what made these so big.
    {
        selectors = {"panel", "characteristic-box", "compact"},
        --One column per characteristic, value over name, five across the
        --section. 19% leaves the row a little slack so it does not wrap.
        --
        --NOT behind dev:testcharpanel: monsters carry the compact footprint
        --either way, and this look is theirs as much as the reworked hero
        --panel's. The "compact" class is the gate -- classic heroes never get
        --it, so they keep the full-size boxes.
        width = "19%",
        height = "auto",
        flow = "vertical",
        bgcolor = "clear",
        border = 0,
        cornerRadius = 4,
        hpad = 5,
        vpad = 1,
        hmargin = 1,
        vmargin = 0,
        --Without this the hpad is added ON TOP of the 19%, making each column
        --10px wider than declared -- five of them then came to ~530px in a
        --~496px section and Presence wrapped to a second line.
        borderBox = true,
    },
    {   -- hover wash carries the affordance the frame used to
        selectors = {"panel", "characteristic-box", "compact", "hover"},
        bgcolor = "@bgAlt",
        brightness = 1,
    },
    {
        --Stacked under the value, so no rmargin: the gap that separated label
        --from value side by side would push the name off centre.
        selectors = {"label", "char-title", "parent:compact"},
        width = "auto",
        valign = "center",
        tmargin = 0,
        rmargin = 0,
        fontSize = TacPanelSizes.Fonts.charTitleCompact,
    },
    {   -- The letter chip and the rest of the name, centred under the value.
        selectors = {"panel", "char-title-row", "parent:compact"},
        width = "auto",
        halign = "center",
        valign = "top",
    },
    {
        selectors = {"label", "char-title", "first", "parent:compact"},
        fontSize = TacPanelSizes.Fonts.charTitleCompact + 2,
    },
    {
        selectors = {"label", "char-value", "parent:compact"},
        width = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontSize = TacPanelSizes.Fonts.charValueCompact,
    },
}
TacPanelStyles.MovementPanel = ThemeEngine.MergeTokens{
    {
        selectors = {"panel", "movement-panel"},
        height = "auto",
        width = "100%",
        valign = "top",
        halign = "left",
        flow = "horizontal",
        wrap = true,
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

    -- Compact (monster) variant, matching the characteristic boxes: label and
    -- value on one line, no fixed cell. The altitude stepper inside
    -- AltitudeBox keeps working; it just has less room around it.
    {
        selectors = {"panel", "movement-box", "compact"},
        width = "auto",
        height = "auto",
        flow = "horizontal",
        tmargin = 2,
        rmargin = 10,
        pad = 2,
    },
    {
        --No halign here either -- same pinning trap as the characteristics.
        selectors = {"label", "movebox-title", "parent:compact"},
        width = "auto",
        valign = "center",
        textAlignment = "left",
        rmargin = 4,
        fontSize = TacPanelSizes.Fonts.movePanelTitleCompact,
    },
    {
        selectors = {"label", "movebox-value", "parent:compact"},
        width = "auto",
        valign = "center",
        tmargin = 0,
        fontSize = TacPanelSizes.Fonts.movePanelValueCompact,
    },
    {
        selectors = {"panel", "altitude-row"},
        flow = "horizontal",
        width = "100%",
        height = "auto",
    },
    {
        --Compact (monsters): a full-width row here claimed a whole line of the
        --wrapping movement panel, which is what pushed "On Ground" off the
        --Speed / Disengage / Stability line and stranded its number out to the
        --right. Sized to its contents it sits inline with the rest.
        --
        --Fixed rather than auto because the altitude stepper floats: it takes
        --no room of its own, so an auto row shrinks to the number alone and the
        --two buttons land on top of it. 44 is the 20-wide stepper on the right
        --plus room for the number on the left.
        selectors = {"panel", "altitude-row", "compact"},
        width = 44,
        valign = "center",
    },
    {
        --Centred (the movebox default) would put the number under the stepper
        --in the narrow compact row.
        selectors = {"label", "altitude-value", "parent:compact"},
        halign = "left",
        lmargin = 2,
    },
    {
        --A "+ / -" pair on one line rather than a stacked pair of chips: two
        --outlined boxes stood taller than the stat line they sit on and read as
        --the loudest thing in the section, which is not what a rarely-used
        --altitude stepper is.
        selectors = {"panel", "altitude-btn-stack"},
        flow = "horizontal",
        width = "auto",
        height = "auto",
        valign = "center",
    },
    {
        selectors = {"label", "altitude-btn"},
        width = "auto",
        height = "auto",
        valign = "center",
        fontSize = TacPanelSizes.Fonts.movePanelValueCompact,
        textAlignment = "center",
        color = "@fg",
    },
    {   -- The slash between them; not pressable, so it stays muted.
        selectors = {"label", "altitude-btn-sep"},
        width = "auto",
        height = "auto",
        valign = "center",
        hmargin = 3,
        fontSize = TacPanelSizes.Fonts.movePanelValueCompact,
        color = "@fgMuted",
    },
    {
        selectors = {"label", "altitude-btn", "hover"},
        color = "@accent",
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
        --No outline: the fill already separates the chip from the panel, and a
        --border around every step made the list read as a stack of buttons.
        border = cond(TacPanel.UseTestPanel(), 0, 1),
        borderColor = "@border",
        cornerRadius = 4,
        bgcolor = "@bgAlt",
    },
    {   -- Already taken this encounter or round. Classic marked this with the
        -- border colour alone -- both states painted the same fill -- so with
        -- the outline gone the chip recedes and its text dims instead.
        selectors = {"panel", "hr-chip", "completed"},
        bgcolor = cond(TacPanel.UseTestPanel(), "@bg", "@bgAlt"),
        borderColor = "@fgPending",
    },
    {   -- Reworked panel only: classic carries the completed state on the
        -- chip's border, so dimming the text there too would double the cue.
        selectors = {"label", "hr-chip-value", "parent:completed"},
        color = cond(TacPanel.UseTestPanel(), "@fgPending", "@fg"),
    },
    {
        selectors = {"label", "hr-chip-event", "parent:completed"},
        color = cond(TacPanel.UseTestPanel(), "@fgPending", "@fg"),
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
    -- "expiring": benefit was active earlier this turn but the resource has since
    -- been spent below its threshold. It still applies until end of turn, shown
    -- muted (no brightness boost; child labels fade their accent). See
    -- GrowingHRTable's high-water-mark logic.
    {
        selectors = {"panel", "gr-row", "expiring"},
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
        selectors = {"label", "gr-value", "parent:expiring"},
        color = "@accent",
        borderColor = "@accent",
        opacity = 0.6,
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
    },
    {
        selectors = {"label", "gr-text", "parent:expiring"},
        color = "@accent",
        opacity = 0.6,
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

    -- Monster-mode chip: exactly one mode is always selected, so the selected
    -- state gets a full accent fill (the drag-target pairing: @accent bg,
    -- @fgInverse text) rather than the routine chip's border-only selection.
    {
        selectors = {"panel", "mm-chip", "selected"},
        priority = 5,
        bgcolor = "@accent",
        borderColor = "@accent",
    },
    {
        selectors = {"label", "mm-chip", "parent:selected"},
        priority = 5,
        color = "@fgInverse",
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
-- Monster sheet: the card grammar for the Abilities / Triggers / Traits
-- sections. Follows the "Monster quick access sheet" design, expressed in
-- ThemeEngine tokens rather than the mock's literal palette so the sections
-- track the active colour scheme (see STYLE_GUIDE.md - never hex in panel
-- code).
--- One size off the card ladder, scaled. Rounded, and never below 1px.
--- @param n number
--- @return number
local function MSScale(n)
    return math.max(1, math.floor(n * MS_CARD_SCALE + 0.5))
end

TacPanelStyles.MonsterSheet = ThemeEngine.MergeTokens{
    {
        selectors = {"panel", "ms-stack"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        hpad = 8,
        vpad = 2,
        borderBox = true,
    },

    -- One ability / trigger / trait card. Padding lives on the header band
    -- and the body wrapper (not here) so the color-keyed header can bleed
    -- all the way to the card edges.
    {
        selectors = {"panel", "ms-card"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        bgimage = "panels/square.png",
        bgcolor = "@bgAlt",
        border = 1,
        borderColor = "@border",
        cornerRadius = 6,
        vmargin = 4,
        borderBox = true,
    },
    -- Everything below the header band gets the padding the card used to
    -- carry.
    {
        selectors = {"panel", "ms-card-body"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        hpad = MSScale(14),
        vpad = MSScale(8),
        borderBox = true,
    },
    -- A minion's With Captain bonus only applies while the squad actually
    -- has a captain. Accent edge marks that it is live right now, matching
    -- the chip treatment this replaced when FEATURES went away for monsters.
    {
        selectors = {"panel", "ms-card", "captain-live"},
        borderColor = "@accent",
    },
    {
        selectors = {"label", "ms-name", "parent:captain-live"},
        color = "@fgStrong",
    },

    -- Header strip across the top of a trait / perk / note card. Geometry
    -- copied from the floating ability card's band (abilityHeadBand) so the
    -- two card kinds line up when a section shows both; the color key rides on
    -- the name rather than the strip.
    {
        selectors = {"panel", "ms-head"},
        --Inset by 1px on the left, right and top: the card's own 1px border is
        --drawn inside its rect, so a full-bleed strip paints over the outline.
        width = "100%-2",
        height = "auto",
        flow = "horizontal",
        halign = "center",
        tmargin = 1,
        bgimage = "panels/square.png",
        bgcolor = "@bg",
        hpad = MSScale(14),
        vpad = MSScale(8),
        cornerRadius = {x1 = 5, y1 = 5, x2 = 0, y2 = 0},
        --Hairline dividing the header from the body. In this framework y1 is the
        --BOTTOM edge and y2 the top (x1 left, x2 right); always give all four,
        --and never add a blanket borderWidth -- it overrides the per-edge widths.
        border = {x1 = 0, x2 = 0, y1 = 1, y2 = 0},
        borderColor = "@border",
        borderBox = true,
    },
    --Follow the card outline when a minion's With Captain bonus is live, so the
    --divider does not read as a stray grey line inside an accented frame.
    {
        selectors = {"panel", "ms-head", "parent:captain-live"},
        borderColor = "@accent",
    },
    -- The ability card's title, copied property for property (Newzald at 24,
    -- Light weight with the name emboldened in markdown, shrinking to 14 before
    -- it wraps) so a trait card and an ability card read as the same object.
    {
        selectors = {"label", "ms-name"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        fontSize = MSScale(24),
        minFontSize = MSScale(14),
        fontFace = "Newzald",
        fontWeight = "Light",
        color = "@fgStrong",
    },
    -- Fallback for a header with no color-key class. The keyed colors are
    -- appended after this table (ActionColorKeyTextStyles) and win on priority.
    {
        selectors = {"label", "ms-name", "parent:ms-head"},
        color = "@fgStrong",
    },

    -- Trait / trigger body prose.
    {
        selectors = {"label", "ms-body"},
        width = "100%",
        height = "auto",
        halign = "left",
        fontSize = MSScale(14),
        color = "@fg",
        tmargin = 3,
    },
    {   -- Jump from a hero's trait to the same feature on the editable sheet,
        -- which is what the FEATURES chips used to offer.
        selectors = {"label", "ms-sheet-link"},
        width = "auto",
        height = "auto",
        halign = "right",
        tmargin = 4,
        bold = true,
        fontSize = MSScale(11),
        color = "@fgMuted",
    },
    {
        selectors = {"label", "ms-sheet-link", "hover"},
        color = "@accent",
    },

    -- Movement modes, sitting under the stat boxes. Muted and unbolded to
    -- match movebox-title: this is reference info, and the section's own
    -- grammar puts labels at @fgMuted rather than at full strength.
    --
    -- Sized and inset to match that row exactly: the compact title size, and a
    -- 2px inset that is the compact movement-box's own padding, so "Movement"
    -- starts on the same column as "Speed" above it.
    {
        selectors = {"label", "ms-profile"},
        width = "100%",
        height = "auto",
        halign = "left",
        fontSize = TacPanelSizes.Fonts.movePanelTitleCompact,
        color = "@fgMuted",
        tmargin = 4,
        lmargin = 2,
    },

    -- The row that carries the portrait alongside the stamina column. Its bottom
    -- border is the rule that closes the block off from STATISTICS below, and it
    -- runs the full panel width -- stamina's own section border is only as wide
    -- as its column, so that one is suppressed (see the "no-rule" class) rather
    -- than stopping dead at the portrait.
    {
        selectors = {"panel", "vitals-row"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        valign = "top",
        bgimage = true,
        --Same ground as the sections above and below. Left clear, this row was
        --the one hole in the panel: the stamina column inside it paints its own
        --@bg, but the portrait column and the gaps around it showed the map
        --straight through. Follows TRANSPARENT_BG so it flips with the rest.
        bgcolor = TRANSPARENT_BG and "clear" or "@bg",
        --Reworked panel only: every token has a portrait in this row, so it
        --owns both rules. Classic leaves them to the "monster" variant below,
        --because a hero's row has no portrait and its stamina section still
        --draws its own full-width rule.
        --
        --Both are PADDING, not margin. As a tmargin the 6 sat outside the
        --panel, so nothing painted it and a thin strip of map showed through
        --between the header's rule and the top of this block.
        tpad = cond(TacPanel.UseTestPanel(), 6, 0),
        bpad = cond(TacPanel.UseTestPanel(), 8, 0),
        borderColor = "@border",
        --y1 is the rule under the identity strip. y2 is the one closing the
        --block off from STATISTICS below: that used to come free from the first
        --section's own top rule, but the sections container is pulled up 26px
        --(see its tmargin) and this row got shorter when the stamina boxes left
        --it, so the overlap now swallows it. Owning the divider here does not
        --depend on what the section above happens to measure.
        border = cond(TacPanel.UseTestPanel(),
            { x1 = 0, y1 = 1, x2 = 0, y2 = 1 }, 0),
    },
    {   -- Classic only: the row draws its rule for monsters, who are the only
        -- tokens with a portrait beside the stamina column there.
        selectors = {"panel", "vitals-row", "monster"},
        tpad = 6,
        bpad = 8,
        borderColor = "@border",
        border = { x1 = 0, y1 = 1, x2 = 0, y2 = 0 },
    },

}

--The action color key (Main Action = red, Maneuver = blue, Triggered = green,
--Move = orange, No Action = grey, Traits/Other = purple, Malice = malice red)
--paints the card NAME now rather than a full-bleed band behind it -- same code,
--far less shouting. Defined once on ActivatedAbility and appended AFTER the
--merge, since these rules carry literal hex rather than @tokens.
for _, rule in ipairs(ActivatedAbility.ActionColorKeyTextStyles("ms-name")) do
    TacPanelStyles.MonsterSheet[#TacPanelStyles.MonsterSheet+1] = rule
end

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
    {   -- Monsters: indent the row so CONDITIONS starts on the same column as
        -- the WEAKNESS / IMMUNITIES line above it. It goes on the ROW because
        -- neither padding nor margin on the key label moves that label's text
        -- (they only inflate its box symmetrically). The 12 is measured, not
        -- derived: res-box's own hpad 6 + hmargin 4 does not account for all of
        -- the offset, so this was set by comparing the first inked pixel column
        -- of each line on screen until they matched.
        selectors = {"panel", "cond-chips", "flush"},
        lmargin = 12,
        width = "100%-12",
        --The resistance line above already leaves its own gap; the base
        --tmargin of 6 on top of that was the rest of the blank line.
        tmargin = cond(TacPanel.UseTestPanel(), 0, 6),
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
    -- A minion's "With Captain" bonus is a TEMPORAL modifier: it is only
    -- applied while the squad actually has a captain. Accent edge marks that
    -- it is live right now, per the style guide's "selected/current edge".
    {
        selectors = {"panel", "cond-chip", "captain-live"},
        borderColor = "@accent",
    },
    {
        selectors = {"label", "cond-name", "parent:captain-live"},
        color = "@fgStrong",
        bold = true,
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
    {   -- Search input: LAYOUT only. The look (frame, pill radius, font,
        -- colors, hpad) comes from DefaultStyles' canonical searchInput
        -- rules -- surfaces must not re-style it locally (Control Zoo
        -- decision 2026-08-20).
        selectors = {"input", "menu-search"},
        width = "90%",
        height = "auto",
        halign = "center",
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
    -- The key on the conditions row, matched to the bold muted key the
    -- resistance line uses so the two stack as a pair.
    {
        selectors = {"label", "cond-key"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        fontSize = TacPanelSizes.Fonts.resEntry,
        bold = true,
        color = "@fgMuted",
        rmargin = 6,
        hpad = 6,
    },
    {   -- The key adds no inset of its own. The whole row is indented
        -- instead -- see the "cond-chips flush" rule -- because padding and
        -- margin on THIS label only inflate its box symmetrically and leave the
        -- text where it was (measured both ways). rmargin is untouched: that is
        -- the gap before the chips.
        selectors = {"label", "cond-key", "parent:flush"},
        hpad = 0,
    },
    {   -- The "add a condition" plus. Drawn as text rather than as the app-wide
        -- addButton icon, which was a second, heavier plus a few lines below
        -- the HEAL box's one. That box has since moved onto the bar, but the
        -- size is still the one this panel's plus signs are cut at.
        selectors = {"label", "cond-add"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        fontFace = "@number",
        fontSize = TacPanelSizes.Fonts.stamBoxInput,
        color = "@fg",
    },
    {
        selectors = {"label", "cond-add", "hover"},
        color = "@accent",
        transitionTime = 0.2,
    },

    {
        selectors = {"panel", "res-container"},
        --The same inset the recoveries strip and the conditions row carry, so
        --all three key-value lines start on one edge. Classic left this at 0
        --and let the res-box hpad/hmargin stand in for it, which put these two
        --lines 2px inside the others.
        lmargin = cond(TacPanel.UseTestPanel(), 12, 0),
        width = cond(TacPanel.UseTestPanel(), "100%-12", "100%"),
        height = "auto",
        --Stacked, so WEAKNESS and IMMUNITIES read as their own lines in the
        --same column as the recoveries and conditions rows. Side by side they
        --were two half-width blocks of wrapped text that shared no left edge
        --with anything around them. Classic keeps the pair.
        flow = cond(TacPanel.UseTestPanel(), "vertical", "horizontal"),
        halign = "center",
        tmargin = 4,
    },

    -- Weakness box
    {
        selectors = {"label", "res-box", "weakness"},
        width = "47%",
        height = "auto",
        --Stacked, each line starts on the column's left edge like IMMUNITY's
        --neighbours; side by side they centre in their half.
        halign = cond(TacPanel.UseTestPanel(), "left", "center"),
        fontSize = TacPanelSizes.Fonts.resEntry,
        bold = false,
        color = "@fg",
        bgimage = true,
        --No outline: the words "WEAKNESS" and "IMMUNITIES" already say what
        --these are, and a box around one line of text was extra structure
        --for nothing.
        border = 0,
        cornerRadius = 4,
        --No insets of their own: the row above carries the indent now, and
        --padding here only pushed these two lines out of step with the rest.
        hpad = cond(TacPanel.UseTestPanel(), 0, 6),
        --No vertical padding either: with the outline gone there is no box for
        --it to hold off, and 4 each side made a one-line entry 33px tall.
        vpad = cond(TacPanel.UseTestPanel(), 0, 4),
        hmargin = cond(TacPanel.UseTestPanel(), 0, 4),
    },

    -- Immunity box
    {
        selectors = {"label", "res-box", "immunity"},
        width = "47%",
        height = "auto",
        --Stacked, each line starts on the column's left edge like IMMUNITY's
        --neighbours; side by side they centre in their half.
        halign = cond(TacPanel.UseTestPanel(), "left", "center"),
        fontSize = TacPanelSizes.Fonts.resEntry,
        bold = false,
        color = "@fg",
        bgimage = true,
        border = 0,
        cornerRadius = 4,
        --No insets of their own: the row above carries the indent now, and
        --padding here only pushed these two lines out of step with the rest.
        hpad = cond(TacPanel.UseTestPanel(), 0, 6),
        --No vertical padding either: with the outline gone there is no box for
        --it to hold off, and 4 each side made a one-line entry 33px tall.
        vpad = cond(TacPanel.UseTestPanel(), 0, 4),
        hmargin = cond(TacPanel.UseTestPanel(), 0, 4),
    },
    -- NOTE: a {res-box, <variant>, parent:flush} rule to zero these insets does
    -- NOT win over the two rules above -- a "parent:" selector does not carry
    -- the specificity its extra term suggests, so the pad and margin stay on.
    -- The CONDITIONS row mirrors this inset instead; see the cond-key rule.
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

-- Read-only mode (Party Member Controls = View): the "readonly" class sits
-- on the character panel root and descends via inherit_selectors, so any
-- control tagged "editOnly" collapses while the panel is read-only. The
-- styles only remove edit-only chrome; look-but-not-touch is actually
-- enforced by the TacPanel.IsReadOnly gates inside the mutating handlers.
TacPanelStyles.ReadOnly = {
    {
        selectors = {"editOnly", "readonly"},
        inherit_selectors = true,
        priority = 100,
        collapsed = 1,
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
        TacPanelStyles.MonsterSheet,
        TacPanelStyles.Conditions,
        TacPanelStyles.ReadOnly,
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

--- Rebuild the style tables and push them onto every live tac-panel root.
--- Shared by the theme hook and the dev:testcharpanel toggle: both change what
--- the rules resolve to, and neither can wait for the next panel to be built.
function TacPanel.RefreshStyles()
    TacPanel.BuildStyles()
    local live = {}
    for _, r in ipairs(g_roots) do
        if r ~= nil and r.valid then
            r.styles = TacPanel.AllStyles()
            live[#live + 1] = r
        end
    end
    g_roots = live
end

ThemeEngine.OnThemeChanged(mod, function()
    TacPanel.RefreshStyles()
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

    -- Portrait control icons. Sized to fit ~3 across the 90px-wide portrait while
    -- staying large enough to read; they wrap to a second row if more are shown.
    local visionBtnSize = 20

    local function outlineButton(params)
        local btn
        if type(params) ~= "table" then
            btn = params
            params = nil
        end
        local args = {
            classes = {"container", "tpOutline"},
            halign = "center",
            valign = "center",
            hmargin = 1,
            vmargin = 1,
            -- pad = 2,
            -- bgimage = true,
            -- border = 1,
            -- cornerRadius = "4",
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
            classes = {"toggle-btn", "light-btn", "editOnly"},
            hoverCursor = "pressbutton",
            bgimage = "ui-icons/codex-logo.png",
            bgcolor = "white",
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
                if TacPanel.IsReadOnly(element) then return end
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


        -- Control buttons at bottom of portrait. A full-width positioner is pinned
        -- to the bottom of the portrait; inside it an auto-width row is centered
        -- (width "auto" + halign center is the codebase idiom for centering a flow).
        -- Each icon carries its own clearly-visible chip, so no group backing needed.
        gui.Panel{
            classes = {"container", "portrait-buttons"},
            floating = true,
            flow = "vertical",
            width = "100%",
            height = "auto",
            halign = "center",
            valign = "bottom",
            --bmargin lives in the style rules, not here: an inline value
            --becomes selfStyle, which no selector can override.
            gui.Panel{
                classes = {"container"},
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
            outlineButton(gui.Panel{
                id = "char-panel-light-btn",
                classes = {"toggle-btn", "light-btn", "editOnly"},
                hoverCursor = "pressbutton",
                width = visionBtnSize,
                height = visionBtnSize,
                bgimage = "drawsteel/light-off.png",
                --The token this panel is showing. Captured here because the press
                --must act on it specifically: the /light macro (Commands.light)
                --reads the global selection instead, so going through it toggled
                --whatever token happened to be selected -- and did nothing at all
                --when nothing was selected and the player has no primary token.
                data = { token = nil },
                refreshCharacter = function(element, token)
                    element.data.token = token
                    local lightOn = token.properties.selectedLoadout == 1
                    element.selfStyle.bgimage = lightOn and "drawsteel/light-on.png" or "drawsteel/light-off.png"
                    element:SetClass("light-on", lightOn)
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                press = function(element)
                    if TacPanel.IsReadOnly(element) then return end
                    local token = element.data.token
                    if token == nil or not token.valid then return end
                    creature.ToggleLightSourceOnToken(token)

                    --instantly refresh the token.
                    game.Refresh{
                        tokens = {token.charid}
                    }
                end,
                linger = function(element)
                    gui.Tooltip("Toggle Light")(element)
                end,
            }),
            outlineButton(gui.Panel{
                classes = {"toggle-btn", "character-sheet-btn", "editOnly"},
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
                    if TacPanel.IsReadOnly(element) then return end
                    local token = element.data.token
                    if token ~= nil then
                        token:ShowSheet()
                    end
                end,
                linger = function(element)
                    gui.Tooltip("Open Character Sheet")(element)
                end,
            }),

            --DM-only: manually assign which hero counts as this monster's
            --summoner (for monsters placed outside a summon ability).
            outlineButton(gui.Panel{
                classes = {"toggle-btn", "summoner-btn", "collapsed"},
                hoverCursor = "pressbutton",
                width = visionBtnSize,
                height = visionBtnSize,
                data = { token = nil },
                refreshCharacter = function(element, token)
                    element.data.token = token
                    local props = nil
                    if token ~= nil and token.valid then
                        props = token.properties
                    end
                    local show = dmhub.isDM and props ~= nil and not props:IsHero()
                    element:SetClass("collapsed", not show)
                    if show then
                        element:SetClass("light-on", token.summonerid ~= nil)
                    end
                end,
                refreshToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                press = function(element)
                    local token = element.data.token
                    if token == nil or not token.valid then return end

                    --any creature on the map except the monster itself can be
                    --the summoner: heroes summon minions, but monsters can
                    --summon for other monsters too.
                    local candidates = {}
                    for _,tok in ipairs(dmhub.allTokens) do
                        if tok.valid and tok.properties ~= nil and tok.charid ~= token.charid then
                            candidates[#candidates+1] = tok
                        end
                    end

                    if #candidates == 0 then
                        gui.Tooltip("No other creatures on this map to assign as summoner.")(element)
                        return
                    end

                    local currentid = token.summonerid
                    local prompt = "Choose this monster's summoner"
                    if currentid ~= nil then
                        prompt = "Choose this monster's summoner (pick the current summoner to clear)"
                    end

                    --enter map targeting: candidates light up with the target
                    --reticule; clicking one assigns it, Escape cancels.
                    gamehud.actionBarPanel:FireEventTree("chooseTargetToken", {
                        sourceToken = token,
                        targets = candidates,
                        prompt = prompt,
                        choose = function(summonerTok)
                            local t = element.valid and element.data.token or token
                            if t == nil or not t.valid or summonerTok == nil or not summonerTok.valid then
                                return
                            end
                            if summonerTok.charid == t.summonerid then
                                --picking the current summoner clears the link.
                                DrawSteelMinion.SetSummoner(t, nil)
                            else
                                DrawSteelMinion.SetSummoner(t, summonerTok)
                            end
                            if element.valid then
                                element:FireEvent("refreshCharacter", t)
                            end
                        end,
                        cancel = function() end,
                    })
                end,
                linger = function(element)
                    local token = element.data.token
                    local text = "Assign Summoner"
                    if token ~= nil and token.valid and token.summonerid ~= nil then
                        local summonerTok = dmhub.GetTokenById(token.summonerid)
                        if summonerTok ~= nil and summonerTok.valid then
                            text = string.format("Summoner: %s (click to change; pick them again to clear)", summonerTok.description)
                        end
                    end
                    gui.Tooltip(text)(element)
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
        },
    }
end

--- Count heroes from the three sources the hero-token refresh button consults:
--- (a) the encounter builder's numheroes setting, (b) hero tokens deployed on
--- the current map, and (c) hero tokens in the default player party.
--- @return integer encounterCount
--- @return integer mapCount
--- @return integer partyCount
local function HeroTokenRefreshCounts()
    local encounterCount = dmhub.GetSettingValue("numheroes")

    local mapCount = 0
    for _, tok in ipairs(dmhub.allTokens) do
        local props = tok.properties
        if props ~= nil and props:IsHero() then
            mapCount = mapCount + 1
        end
    end

    local partyCount = 0
    local partyMembers = dmhub.GetCharacterIdsInParty(GetDefaultPartyID()) or {}
    for _, charid in ipairs(partyMembers) do
        local tok = dmhub.GetTokenById(charid)
        if tok ~= nil and tok.properties ~= nil and tok.properties:IsHero() then
            partyCount = partyCount + 1
        end
    end

    return encounterCount, mapCount, partyCount
end

--- Reset a token's hero tokens to n as a session reset (the refresh button's action).
--- @param token CharacterToken
--- @param n integer
local function RefreshHeroTokensTo(token, n)
    if token == nil then return end
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
                    if TacPanel.IsReadOnly(element) then
                        element.textNoNotify = string.format("%d", token.properties:GetHeroTokens())
                        return
                    end
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
                    --a game update must not stomp on what the user is currently typing.
                    if element.hasFocus then
                        return
                    end
                    element.editable = not TacPanel.IsReadOnly(element)
                    element.textNoNotify = tostring(token.properties:GetHeroTokens())
                end,
                defocus = function(element)
                    --catch up on anything we skipped while the field was being edited.
                    local token = element.parent.parent.data.token
                    if token ~= nil and token.valid then
                        element:FireEvent("refreshValue", token)
                    end
                end,
            },
        },

        -- Floating: refresh button
        gui.Button{
            classes = {"refresh-icon", "sizeS", "editOnly"},
            floating = true,
            icon = "icons/standard/Icon_App_Undo.png",
            press = function(element)
                if TacPanel.IsReadOnly(element) then return end
                local token = element.parent.data.token
                if token == nil then return end

                local encounterCount, mapCount, partyCount = HeroTokenRefreshCounts()

                -- All three sources agree: refresh directly, as before.
                if encounterCount == mapCount and mapCount == partyCount then
                    RefreshHeroTokensTo(token, encounterCount)
                    return
                end

                -- Sources disagree: let the user pick which count to refresh to,
                -- one entry per unique value.
                local seen = {}
                local entries = {}
                for _, n in ipairs({encounterCount, mapCount, partyCount}) do
                    if seen[n] == nil then
                        seen[n] = true
                        entries[#entries+1] = {
                            text = string.format("Refresh Hero Tokens (%d)", n),
                            click = function()
                                element.popup = nil
                                RefreshHeroTokensTo(token, n)
                            end,
                        }
                    end
                end

                element.popup = gui.ContextMenu{
                    entries = entries,
                }
            end,
            linger = function(element)
                local encounterCount, mapCount, partyCount = HeroTokenRefreshCounts()
                if encounterCount == mapCount and mapCount == partyCount then
                    gui.Tooltip(string.format("Reset Hero Tokens For Session (%d heroes)", encounterCount))(element)
                else
                    gui.Tooltip("Reset Hero Tokens")(element)
                end
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
                    if TacPanel.IsReadOnly(element) then
                        element.textNoNotify = tostring(token.properties:GetAvailableSurges())
                        return
                    end
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
                    --a game update must not stomp on what the user is currently typing.
                    if element.hasFocus then
                        return
                    end
                    local q = dmhub.initiativeQueue
                    if q == nil or q.hidden then
                        element.editable = false
                        element.textNoNotify = "--"
                    else
                        element.editable = not TacPanel.IsReadOnly(element)
                        element.textNoNotify = tostring(token.properties:GetAvailableSurges())
                    end
                end,
                defocus = function(element)
                    --catch up on anything we skipped while the field was being edited.
                    local token = element.parent.parent.data.token
                    if token ~= nil and token.valid then
                        element:FireEvent("refreshValue", token)
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

        --The only identification once RESOURCES drops the labels; the other
        --boxes in that row already had one.
        linger = gui.Tooltip("Victories"),

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
                    element.editable = not TacPanel.IsReadOnly(element)
                    element.textNoNotify = string.format("%d", token.properties:GetVictories())
                end,
                refreshToken = function(element, token)
                    --a game update must not stomp on what the user is currently typing.
                    element.data.token = token
                    if element.hasFocus then
                        return
                    end
                    element:FireEvent("refreshCharacter", token)
                end,
                defocus = function(element)
                    --catch up on anything we skipped while the field was being edited.
                    local token = element.data.token
                    if token ~= nil and token.valid then
                        element:FireEvent("refreshCharacter", token)
                    end
                end,
                change = function(element)
                    local token = element.data.token
                    if token == nil then return end
                    local n = tonum(element.text, -1)
                    if TacPanel.IsReadOnly(element) or n < 0 then
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
                    --a game update must not stomp on what the user is currently typing.
                    element.data.token = token
                    if element.hasFocus then
                        return
                    end
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
                        element.editable = not TacPanel.IsReadOnly(element)
                        element.textNoNotify = tostring(token.properties:GetHeroicOrMaliceResources())
                    end
                end,
                refreshToken = function(element, token)
                    --a game update must not stomp on what the user is currently typing.
                    element.data.token = token
                    if element.hasFocus then
                        return
                    end
                    element:FireEvent("refreshCharacter", token)
                end,
                defocus = function(element)
                    --catch up on anything we skipped while the field was being edited.
                    local token = element.data.token
                    if token ~= nil and token.valid then
                        element:FireEvent("refreshCharacter", token)
                    end
                end,
                change = function(element)
                    local token = element.data.token
                    if token == nil then return end
                    local n = tonum(element.text, nil)
                    if n == nil or TacPanel.IsReadOnly(element) then
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

--- The portrait as it sits in the vitals row, beside the stamina column.
---
--- Wraps TacPanel.Portrait() with the layout that row needs: the control
--- buttons stood up as a strip to its right, and a dark plate behind the
--- artwork. Both kinds of token get the same treatment.
--- @return Panel
function TacPanel.PortraitColumn()
    local portrait = TacPanel.Portrait()

    --The three control buttons stand up as a vertical strip to the RIGHT of
    --the portrait rather than overlaying them on the image.
    --
    --Set directly rather than through style rules: the buttons panel declares
    --halign, valign and width INLINE, and inline args become selfStyle, which
    --no selector can override.
    --30 reserves the strip: a 26px button (20 glyph + pad 2 + border 1 each
    --side) plus a little air off the portrait's edge.
    portrait.selfStyle.rmargin = 30
    --Clearance so the next section's rule reads as a line under the portrait
    --rather than one running into its rounded bottom edge.
    portrait.selfStyle.bmargin = 8

    --Dark plate behind the artwork. Prepended so it renders first, i.e.
    --behind everything else in the frame.
    local backing = gui.Panel{ classes = {"portrait-backing"} }
    local kids = { backing }
    for _, child in ipairs(portrait.children or {}) do
        kids[#kids+1] = child
    end
    portrait.children = kids

    for _, child in ipairs(portrait.children or {}) do
        if child:HasClass("portrait-buttons") then
            child.selfStyle.halign = "right"
            child.selfStyle.valign = "center"
            child.selfStyle.width = "auto"
            --Floating, so this pushes the strip out past the frame's
            --right edge into the room the rmargin above reserved.
            child.selfStyle.rmargin = -28
            child.selfStyle.bmargin = 0
            for _, row in ipairs(child.children or {}) do
                row.selfStyle.flow = "vertical"
                for _, btn in ipairs(row.children or {}) do
                    --Quiet the button outlines down to match the DMG box.
                    btn:SetClass("tp-outline-quiet", true)
                    --Air between them. The portrait is a fixed 120px and
                    --three 26px buttons only need 78, so the spacing is
                    --free -- and these are small targets. Set here because
                    --the wrapper declares vmargin inline.
                    btn.selfStyle.vmargin = 4
                end
            end
        end
    end

    return gui.Panel{
        classes = {"container"},
        width = "auto",
        height = "auto",
        flow = "horizontal",
        valign = "top",
        halign = "left",
        portrait,
    }
end

--- A minion's "With Captain" bonus text, or nil when there is nothing worth
--- showing. Non-minions never carry the field at all, and 22 of the 181
--- minions that do store a placeholder dash rather than a bonus -- "-" is
--- truthy in Lua, so it has to be filtered out explicitly.
---
--- Declared up here rather than beside its other callers because the identity
--- strip below is the first thing to need it; the monster TRAITS section, the
--- hero FEATURES chip and the feature search matcher all come later in the
--- file, so a query can never claim a hit on something the panel is not
--- displaying.
--- @param creature any
--- @return nil|string
local function WithCaptainText(creature)
    if not creature.minion then
        return nil
    end
    local raw = creature:try_get("withCaptain", false)
    if type(raw) ~= "string" then
        return nil
    end
    local trimmed = raw:match("^%s*(.-)%s*$")
    if trimmed == "" or trimmed == "-" or trimmed == "--" then
        return nil
    end
    return trimmed
end

--- The kit's stat line-up, for the KIT tooltip in the identity strip.
---
--- Mirrors the "<Kit> Kit Stats" feature that FEATURES lists below, minus the
--- zeros -- a kit with no reach has nothing to say about reach. Reads the kit's
--- own fields rather than the feature's description because a hero with two
--- kits carries a COMBINED kit (see character:Kit), and its fields are already
--- the totals.
--- @param kit any
--- @return string
local function KitStatsTooltip(kit)
    local rows = {
        { "Stamina", "health" },
        { "Speed", "speed" },
        { "Disengage", "disengage" },
        { "Stability", "stability" },
        { "Damage", "damage" },
        { "Range", "range" },
        { "Reach", "reach" },
        { "Area", "area" },
    }

    local lines = {}
    for _, row in ipairs(rows) do
        local value = kit:try_get(row[2], 0)
        if type(value) == "number" and value ~= 0 then
            lines[#lines+1] = string.format("%s %+d", row[1], value)
        end
    end

    local name = string.format("<b>%s Kit</b>", tostring(kit.name))
    if #lines == 0 then
        return string.format("%s\nNo stat bonuses.", name)
    end
    return string.format("%s\n%s", name, string.join(lines, "\n"))
end

--- The identity strip: name, class and subclass against level, ancestry and
--- kit (monsters: type and keywords against EV, level/role, size and free
--- strike). Runs the full panel width; the portrait sits in the vitals row
--- below it.
--- @return Panel
function TacPanel.Summary()

    return gui.Panel{
        classes = {"tacpanel"},
        --The strip tightens tacpanel's vpad of 8 at both ends. Most comes off
        --the top, which was leaving a wide gap between the panel's title bar
        --and the token name; half comes off the bottom and moves to the far
        --side of the rule, so the portrait below is not jammed against the
        --divider (see the portrait rows in
        --CharacterPanel.SingleCharacterDisplaySidePanel).
        tpad = 2,
        bpad = 4,

        gui.Panel{
            classes = {"container"},
            flow = "horizontal",

            gui.Panel{
                classes = {"summary-info"},
                --Both kinds of token get the book's full-width two-column
                --header strip. The portrait sits below it either way: for
                --monsters beside the stamina controls (see
                --CharacterPanel.SingleCharacterDisplaySidePanel), for heroes
                --on its own row further down this panel.
                --summary-info carries pad = 6; the top half of it is dropped
                --so the name sits closer to the panel's title bar.
                width = "100%",
                tpad = 0,
                flow = "horizontal",

                gui.Panel{
                classes = {"ident-left"},

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

                -- Monster type, e.g. ZOMBIE. Sits directly under the token
                -- name and above the keywords, so the identity block reads
                -- name -> what it is -> what it has -> what it costs.
                --
                -- A separate label rather than moving the "Class" slot up:
                -- that slot renders the CLASS for heroes, and reordering it
                -- would rearrange the hero panel too. This one collapses for
                -- heroes, and the class slot collapses for monsters.
                gui.Label{
                    classes = {"summary-info", "class"},
                    refreshCharacter = function(element, token)
                        local isMonster = false
                        pcall(function() isMonster = token.properties:IsMonster() end)
                        if not isMonster then
                            element:SetClass("collapsed", true)
                            element.text = ""
                            return
                        end
                        element:SetClass("collapsed", false)
                        local text = string.upper(token.properties:try_get("monster_type", "Monster"))
                        element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.monsterType, 14, #text)
                        element.text = text
                    end,
                    setToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                },

                -- Monster keywords, e.g. "Soulless, Undead". Left column,
                -- under the type, so the identity block reads top to bottom as
                -- name -> what it is -> what it has, with the right column
                -- carrying the numbers instead of a second stack of nouns.
                gui.Label{
                    classes = {"summary-info", "monster-keywords"},
                    refreshCharacter = function(element, token)
                        --This column is shared with heroes now that the label
                        --has moved out of the monster-only right column, so it
                        --collapses rather than rendering an empty line that
                        --would push the hero's own rows down.
                        local isMonster = false
                        pcall(function() isMonster = token.properties:IsMonster() end)
                        element:SetClass("collapsed", not isMonster)
                        if not isMonster then
                            element.text = ""
                            return
                        end
                        local keywords = token.properties.keywords or {}
                        local sorted = {}
                        for k, _ in pairs(keywords) do
                            sorted[#sorted+1] = ActivatedAbility.CanonicalKeyword(k)
                        end
                        table.sort(sorted)
                        local text = string.join(sorted, ", ")
                        --Fixed at the right column's size rather than fitted:
                        --keywords and the level/size/free-strike lines are the
                        --same order of information, and fitting made this line
                        --shrink with its own length so the two halves of the
                        --strip almost never matched.
                        element.selfStyle.fontSize = TacPanelSizes.Fonts.identRight
                        element.text = text
                    end,
                },

                -- A minion's "With Captain" bonus, under the type block. It is
                -- identity, not a trait: it says what this creature is worth
                -- while its captain lives. Accented when the squad actually
                -- HAS a captain (FillTemporalActiveModifiers in
                -- MCDMMonster.lua), muted when it is merely possible.
                gui.Label{
                    classes = {"summary-info", "ident-captain"},
                    refreshCharacter = function(element, token)
                        local text = nil
                        pcall(function() text = WithCaptainText(token.properties) end)
                        if text == nil then
                            element:SetClass("collapsed", true)
                            element.text = ""
                            return
                        end
                        element:SetClass("collapsed", false)
                        local squad = token.properties:try_get("_tmp_minionSquad")
                        element:SetClass("captain-live", squad ~= nil and squad.hasCaptain == true)
                        element.text = string.format("With Captain: %s", text)
                    end,
                    refreshToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                    setToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                },

                -- Class. Monsters show their type in the label above instead,
                -- so this collapses for them rather than repeating it here.
                gui.Label{
                    classes = {"summary-info", "class"},
                    refreshCharacter = function(element, token)
                        local isMonster = false
                        pcall(function() isMonster = token.properties:IsMonster() end)
                        if isMonster then
                            element:SetClass("collapsed", true)
                            element.text = ""
                            return
                        end
                        element:SetClass("collapsed", false)
                        local text = ""
                        if token.properties:IsHero() then
                            local classItem = token.properties:GetClass()
                            if classItem ~= nil then
                                text = string.upper(classItem.name)
                            end
                        end
                        --Same size the monster type uses on the line below
                        --the name, so both kinds of token step down from the
                        --name by the same amount.
                        element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.monsterType, 14, #text)
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
                        --Third line of the left column, the same size the
                        --monster's keywords sit at.
                        element.selfStyle.fontSize = TacPanelSizes.Fonts.identRight
                        element.text = text
                    end,
                    setToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                },

                },

                --RIGHT column of the identity strip. Monsters: EV on the
                --name's line, then level/role, size and free strike. Heroes:
                --level, ancestry and kit against name/class/subclass.
                --
                --Every label here is one kind's or the other's, so each one
                --collapses rather than blanking its text -- an empty label
                --still claims a line and would knock the two columns out of
                --step with each other.
                gui.Panel{
                    classes = {"ident-right"},

                    gui.Label{
                        classes = {"ident-right", "ident-ev"},
                        refreshCharacter = function(element, token)
                            local isMonster = false
                            pcall(function() isMonster = token.properties:IsMonster() end)
                            element:SetClass("collapsed", not isMonster)
                            if not isMonster then
                                return
                            end
                            element.text = string.format("EV %d", token.properties:EV())
                        end,
                        setToken = function(element, token)
                            element:FireEvent("refreshCharacter", token)
                        end,
                    },

                    gui.Label{
                        classes = {"ident-right", "ident-level"},
                        refreshCharacter = function(element, token)
                            local isMonster = false
                            pcall(function() isMonster = token.properties:IsMonster() end)
                            element:SetClass("collapsed", not isMonster)
                            if not isMonster then
                                return
                            end
                            local level = token.properties:CharacterLevel()
                            local role = token.properties:try_get("role", "")
                            local text
                            if role ~= "" then
                                text = string.format("LEVEL %d %s", level, string.upper(role))
                            else
                                text = string.format("LEVEL %d", level)
                            end
                            --No per-label sizing: the whole right column now
                            --shares one size from the "ident-right" rule, and
                            --shrinking just this line to fit was what made the
                            --column read as a hierarchy it does not have.
                            element.text = text
                        end,
                        setToken = function(element, token)
                            element:FireEvent("refreshCharacter", token)
                        end,
                    },

                    -- Size, at the foot of the strip. It used to sit down in
                    -- STATISTICS with the movement numbers; up here it leaves
                    -- that block as just the movement modes.
                    gui.Label{
                        classes = {"ident-right", "ident-size"},
                        refreshCharacter = function(element, token)
                            local isMonster = false
                            pcall(function() isMonster = token.properties:IsMonster() end)
                            local size = nil
                            if isMonster then
                                pcall(function() size = token.properties:SizeDescription() end)
                            end
                            if size == nil or size == "" then
                                element:SetClass("collapsed", true)
                                return
                            end
                            element:SetClass("collapsed", false)
                            element.text = string.format("SIZE %s", tostring(size))
                        end,
                        setToken = function(element, token)
                            element:FireEvent("refreshCharacter", token)
                        end,
                    },

                    -- Free strike. It sat in STATISTICS as a stat box, but it
                    -- is a fixed property of the creature rather than a number
                    -- that moves in play, so it belongs with size and role.
                    gui.Label{
                        classes = {"ident-right", "ident-freestrike"},
                        refreshCharacter = function(element, token)
                            local isMonster = false
                            pcall(function() isMonster = token.properties:IsMonster() end)
                            local freeStrike = nil
                            if isMonster then
                                pcall(function() freeStrike = token.properties:OpportunityAttack() end)
                            end
                            if freeStrike == nil then
                                element:SetClass("collapsed", true)
                                return
                            end
                            element:SetClass("collapsed", false)
                            element.text = string.format("FREE STRIKE %s", tostring(freeStrike))
                        end,
                        setToken = function(element, token)
                            element:FireEvent("refreshCharacter", token)
                        end,
                    },

                    -- Hero level, opposite the name. Level 1 heroes show which
                    -- encounter of their first level they are on instead --
                    -- that is what advances before the level number does.
                    gui.Label{
                        classes = {"ident-right", "hero-level"},
                        refreshCharacter = function(element, token)
                            local isHero = false
                            pcall(function() isHero = token.properties:IsHero() end)
                            element:SetClass("collapsed", not isHero)
                            if not isHero then
                                return
                            end
                            local level = token.properties:CharacterLevel()
                            local text
                            if level == 1 then
                                local extra = token.properties:ExtraLevelInfo()
                                local encounter = type(extra) == "table" and extra.encounter or nil
                                local mapping = {"FIRST ENCOUNTER", "SECOND ENCOUNTER", "THIRD ENCOUNTER", "FOURTH ENCOUNTER"}
                                text = mapping[encounter] or "LEVEL 1"
                            else
                                text = string.format("LEVEL %d", level)
                            end
                            element.text = text
                        end,
                        setToken = function(element, token)
                            element:FireEvent("refreshCharacter", token)
                        end,
                    },

                    -- Ancestry, opposite the class. RaceOrMonsterType is the
                    -- accessor that already folds the ancestry variant into
                    -- the name ("Elf, Wode"); DS does not use subraces.
                    gui.Label{
                        classes = {"ident-right", "hero-ancestry"},
                        refreshCharacter = function(element, token)
                            local isHero = false
                            pcall(function() isHero = token.properties:IsHero() end)
                            local text = nil
                            if isHero then
                                pcall(function() text = token.properties:RaceOrMonsterType() end)
                            end
                            if text == nil or text == "" then
                                element:SetClass("collapsed", true)
                                return
                            end
                            element:SetClass("collapsed", false)
                            element.text = string.upper(text)
                        end,
                        setToken = function(element, token)
                            element:FireEvent("refreshCharacter", token)
                        end,
                    },

                    -- Kit, opposite the subclass. Labelled rather than left as
                    -- a bare noun: kit names ("Panther", "Mountain") say
                    -- nothing about what they are on their own.
                    --
                    -- Hovering the name shows the kit's stats. The row exists
                    -- to BE that hover target: a panel with no background image
                    -- is not a hit target at all, and the label inside is
                    -- non-interactable so it cannot eat the hover first.
                    gui.Panel{
                        classes = {"ident-kit-row", "collapsed"},
                        bgimage = true,
                        bgcolor = "clear",
                        data = { kit = nil },

                        linger = function(element)
                            local kit = element.data.kit
                            if kit == nil then return end
                            gui.Tooltip(KitStatsTooltip(kit))(element)
                        end,

                        refreshCharacter = function(element, token)
                            local isHero = false
                            pcall(function() isHero = token.properties:IsHero() end)
                            local kit = nil
                            if isHero then
                                pcall(function() kit = token.properties:Kit() end)
                            end
                            element.data.kit = kit
                            if kit == nil or kit.name == nil or kit.name == "" then
                                element:SetClass("collapsed", true)
                                return
                            end
                            element:SetClass("collapsed", false)
                            element:FireEventTree("setKit", kit)
                        end,
                        setToken = function(element, token)
                            element:FireEvent("refreshCharacter", token)
                        end,

                        gui.Label{
                            classes = {"ident-right", "hero-kit"},
                            interactable = false,
                            setKit = function(element, kit)
                                element.text = string.format("KIT %s", string.upper(kit.name))
                            end,
                        },
                    },
                },

            },

        },

        -- Full-width "Add to Combat" button under the strip. Visible only when
        -- there is an active initiative queue and this token is not yet a
        -- combatant (same semantics as the old initiative icon button).
        gui.Button{
            classes = {"sizeM", "collapsed", "editOnly"},
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
                if TacPanel.IsReadOnly(element) then return end
                Commands.rollinitiative()
            end,
        },

    }
end



--- Display-only recovery pips, split into rows of 10
--- @param resolveRecovery fun(): string|nil, table|nil
--- @return Panel
function TacPanel.RecoveryPips(resolveRecovery)
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
            local recoveryid, recoveryInfo = resolveRecovery()
            if recoveryInfo == nil then return end
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
    -- The Recovery resource is found by name in characterResources, which is a live,
    -- user-editable table: the row can be absent because the table has not finished
    -- loading when this panel is built, or because it was soft-deleted or renamed in
    -- the compendium. Resolving it once at construction time left every handler below
    -- dereferencing a permanently-nil upvalue, and collapsing the box does not help --
    -- FireEventTree delivers to hidden and collapsed descendants alike. So resolve on
    -- demand, memoize only once found, and let each handler bail out when it is not.
    local recoveryid = nil
    local recoveryInfo = nil
    local function resolveRecovery()
        if recoveryInfo == nil then
            local resourcesTable = dmhub.GetTableVisible(CharacterResource.tableName)
            for k,v in pairs(resourcesTable) do
                if v.name == "Recovery" then
                    recoveryid = k
                    recoveryInfo = v
                    break
                end
            end
        end

        return recoveryid, recoveryInfo
    end

    -- Build and show the "spend an ally's shared recovery" context menu on the
    -- given element. Returns true if a menu was shown (i.e. there is at least
    -- one bonded ally with a spendable recovery), false otherwise.
    local function ShowSharingMenu(element, token)
        if token == nil or not token.valid or token.properties == nil then return false end

        local recoveryid, recoveryInfo = resolveRecovery()
        if recoveryInfo == nil then return false end

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
            local id = resolveRecovery()
            local showRecovery = id ~= nil and (token.properties:IsHero() or token.properties:IsRetainer() or token.properties:IsCompanion())
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
            local recoveryid, recoveryInfo = resolveRecovery()
            if recoveryInfo == nil then return end
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
            if TacPanel.IsReadOnly(element) then return end
            local token = element.data.token
            if token == nil then return end

            local recoveryid, recoveryInfo = resolveRecovery()
            if recoveryInfo == nil then return end

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
            if TacPanel.IsReadOnly(element) then return end
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
                            element.editable = not TacPanel.IsReadOnly(element)
                            local recoveryid, recoveryInfo = resolveRecovery()
                            if recoveryInfo == nil then return end
                            local quantity = max(0, (token.properties:GetResources()[recoveryid] or 0) - (token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
                            element.textNoNotify = string.format("%d", quantity)
                        end,
                        setToken = function(element, token)
                            element.data.token = token
                        end,
                        change = function(element)
                            local token = element.data.token
                            if token == nil then return end
                            local recoveryid, recoveryInfo = resolveRecovery()
                            if recoveryInfo == nil then return end
                            local n = tonum(element.text, -1)
                            if n < 0 or TacPanel.IsReadOnly(element) then
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
                            local recoveryid = resolveRecovery()
                            if recoveryid == nil then return end
                            local maxRec = token.properties:GetResources()[recoveryid] or 0
                            element.text = string.format("/ %d", maxRec)
                        end,
                    }
                },
                TacPanel.RecoveryPips(resolveRecovery),
            }
        },
    }
end

--- How often the bar's adjust panel polls the mouse wheel. It only needs to
--- while an entry box is open, so it idles at an interval that never fires in
--- practice rather than ticking a hundred times a second for nothing.
local BAR_ENTRY_THINK_IDLE = 3600
local BAR_ENTRY_THINK_OPEN = 0.01

--- How long the wheel has to be still before the value it landed on is applied.
local BAR_ENTRY_WHEEL_SETTLE = 0.3

--- The adjust controls that appear on the stamina bar while it is hovered:
--- "-" and "+" at the left, "TEMP" at the right, and the number in the middle
--- is itself a button. Picking one swaps that spot for a small entry box;
--- typing a number and pressing enter applies it and closes.
---
--- These do exactly what the DMG / STAMINA / HEAL / TEMP boxes above the bar
--- used to do -- the same TakeDamage / Heal / SetCurrentHitpoints /
--- SetTemporaryHitpoints calls, wrapped the same way.
--- @param labelPanel Panel The bar's own number, hidden while it is being edited
--- @return Panel panel, fun(): nil openStamina
function TacPanel.BarAdjustControls(labelPanel)
    local m_token = nil
    local m_tokenid = nil
    local m_mode = nil          -- "harm"|"heal"|"temp"|"stamina", nil when closed
    local m_focused = false     -- true once the entry field really has focus

    --Forward-declared: the handlers below close over them, and in Lua a local
    --is not in scope inside its own initializer.
    local adjustPanel
    local leftButtons
    local rightButtons
    local entryRow
    local entryKey
    local entryInput
    local NudgeEntry
    local ApplyValue

    --Set by the wheel, applied once it stops. nil when there is nothing waiting.
    local m_wheelPending = nil
    local m_wheelIdle = 0

    local function CloseEntry()
        m_mode = nil
        m_focused = false
        m_wheelPending = nil
        entryRow:SetClass("collapsed", true)
        leftButtons:SetClass("collapsed", false)
        rightButtons:SetClass("collapsed", false)
        labelPanel:SetClass("collapsed", false)
        adjustPanel:SetClass("open", false)
        --Only claim escape while the box is actually up, so a stray escape
        --anywhere else in the app still does what it always did.
        entryInput.captureEscape = false
        adjustPanel.thinkTime = BAR_ENTRY_THINK_IDLE
    end

    local function OpenEntry(mode)
        m_mode = mode

        local props = nil
        if m_token ~= nil and m_token.valid then
            props = m_token.properties
        end

        --The box opens where its control was, so the edit happens under the
        --pointer rather than jumping across the bar.
        if mode == "harm" then
            entryKey.text = "DMG"
            entryInput.text = ""
            entryRow.selfStyle.halign = "left"
        elseif mode == "heal" then
            entryKey.text = "HEAL"
            entryInput.text = ""
            entryRow.selfStyle.halign = "left"
        elseif mode == "temp" then
            entryKey.text = "TEMP"
            entryRow.selfStyle.halign = "right"
            --Temp stamina is a value rather than a delta, so it opens on what
            --the creature already has.
            local cur = 0
            if props ~= nil then
                cur = props:TemporaryHitpoints() or 0
            end
            entryInput.text = tostring(cur)
        else
            --Stamina replaces the number in place, so it needs no key label.
            entryKey.text = ""
            entryRow.selfStyle.halign = "center"
            local cur = 0
            if props ~= nil then
                cur = props:CurrentHitpoints()
            end
            entryInput.text = tostring(cur)
        end

        entryKey:SetClass("collapsed", mode == "stamina")
        --Both button clusters go while an entry is up: one edit at a time, and
        --a centred stamina box would otherwise run into them.
        leftButtons:SetClass("collapsed", true)
        rightButtons:SetClass("collapsed", true)
        labelPanel:SetClass("collapsed", mode == "stamina")
        entryRow:SetClass("collapsed", false)
        adjustPanel:SetClass("open", true)
        entryInput.captureEscape = true
        adjustPanel.thinkTime = BAR_ENTRY_THINK_OPEN

        --Focus a frame later: the field is still collapsed as far as the engine
        --is concerned when this runs, so focusing it here does not stick.
        m_focused = false
        dmhub.Schedule(0.01, function()
            if mod.unloaded then return end
            if m_mode ~= nil and entryInput.valid then
                gui.SetFocus(entryInput)
            end
        end)
    end

    --A wheel notch over an open entry nudges the value by one, which beats
    --typing for the small adjustments most of these are. It only edits the
    --field: enter still commits, so a wheel that overshoots costs nothing.
    NudgeEntry = function(delta)
        if m_mode == nil then return end
        --Only the modes that hold an absolute value. DMG and HEAL hold a delta
        --that is applied on commit, so a wheel that committed itself would keep
        --stacking damage every time it paused.
        if m_mode ~= "stamina" and m_mode ~= "temp" then return end

        local props = nil
        if m_token ~= nil and m_token.valid then
            props = m_token.properties
        end

        --One notch is one point. When several land in the same frame the engine
        --reports them together, so take them all rather than dropping the
        --extras -- a fast spin should not lose half its travel.
        local steps = cond(delta < 0, -1, 1)
        if math.abs(delta) >= 2 then
            steps = math.floor(math.abs(delta)) * cond(delta < 0, -1, 1)
        end

        local value = (tonumber(entryInput.text) or 0) + steps

        --Damage, healing and temp are never negative. Stamina can be, but only
        --for a hero, who keeps counting down while dying.
        local allowNegative = false
        if m_mode == "stamina" and props ~= nil then
            allowNegative = props:IsHero()
        end
        if value < 0 and not allowNegative then
            value = 0
        end

        --Nor can stamina be wheeled past the creature's maximum.
        if m_mode == "stamina" and props ~= nil then
            local maxHP = props:MaxHitpoints()
            if value > maxHP then
                value = maxHP
            end
        end

        --NOT .text: that fires change, which would commit and close the box on
        --every notch.
        entryInput.textNoNotify = tostring(value)
        m_wheelPending = tostring(value)
        m_wheelIdle = 0
    end

    local function AdjustButton(mode, text, extraClass)
        return gui.Panel{
            classes = {"bar-adjust-btn", extraClass},
            hoverCursor = "pressbutton",
            --A panel with no background image is not a hit target at all, so
            --clicks fell straight through it to the bar behind. bgimage is a
            --panel property; a style rule that sets it is ignored.
            bgimage = true,
            press = function(element)
                if TacPanel.IsReadOnly(element) then return end
                OpenEntry(mode)
            end,
            gui.Label{
                classes = {"bar-adjust-glyph", extraClass},
                text = text,
                --Otherwise the label sits on top of its own button and eats the
                --click, and the button's press never fires.
                interactable = false,
            },
        }
    end

    entryKey = gui.Label{
        classes = {"bar-entry-key"},
        text = "DMG",
    }

    entryInput = gui.Input{
        classes = {"bar-entry-input"},
        text = "",
        --Blank rather than the default "Enter text...", which is far wider than
        --the field and spilled across the bar.
        placeholderText = "",
        characterLimit = 8,
        selectAllOnFocus = true,
        hoverCursor = "text",
        captureEscape = false,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            CloseEntry()
            gui.SetFocus(nil)
        end,
        focus = function(element)
            m_focused = true
        end,
        defocus = function(element)
            --Only a real focus loss closes the box. Without the guard, the
            --defocus that fires while the field is still being opened shut it
            --again immediately.
            if not m_focused then return end
            m_focused = false

            --Closing is deferred a frame for two reasons. 'change' fires on
            --focus loss too, and closing on the spot cleared the mode before it
            --ran, so clicking away threw the edit away instead of committing
            --it. And clicking INSIDE the box to move the caret defocuses and
            --refocuses, which closed the box out from under the pointer.
            dmhub.Schedule(0.01, function()
                if mod.unloaded then return end
                if not entryInput.valid then return end
                --Focus came straight back, or the value already committed.
                if m_focused or m_mode == nil then return end
                CloseEntry()
            end)
        end,
        change = function(element)
            --Read everything BEFORE closing: change also fires when the field
            --loses focus, and closing must not eat the value being committed.
            local token = m_token
            local mode = m_mode
            local text = element.text
            m_wheelPending = nil
            CloseEntry()
            ApplyValue(mode, token, text, element)
        end,
    }

    --Shared by the enter/commit path and by the wheel, which applies on its own
    --rather than waiting for enter: a value written with textNoNotify leaves the
    --field looking unmodified to the engine, so enter fires no change event and
    --a wheeled number could never be committed by hand.
    ApplyValue = function(mode, token, text, element)
            local n = tonum(text, 0)

            if element ~= nil and TacPanel.IsReadOnly(element) then return end
            if mode == nil then return end
            if token == nil or not token.valid or token.properties == nil then return end

            if mode == "harm" then
                if n <= 0 then return end
                token:ModifyProperties{
                    description = "Apply Damage",
                    execute = function()
                        --A string, not the number: TakeDamage takes a formula.
                        token.properties:TakeDamage(text)
                    end,
                }
            elseif mode == "heal" then
                if n <= 0 then return end
                token:ModifyProperties{
                    description = "Apply Healing",
                    execute = function()
                        token.properties:Heal(n)
                    end,
                }
            elseif mode == "temp" then
                if text == "" then return end
                local before = tonum(token.properties:TemporaryHitpointsStr(), 0)
                if n == before then return end
                token:ModifyProperties{
                    description = "Apply Temp Stamina",
                    execute = function()
                        token.properties:SetTemporaryHitpoints(text)
                        token.properties:DispatchEvent("gaintempstamina", {})
                    end,
                }
            elseif mode == "stamina" then
                local value = tonumber(text)
                if value == nil then return end
                --Only heroes go below zero; they keep counting down while dying.
                if value < 0 and not token.properties:IsHero() then return end
                token:ModifyProperties{
                    description = "Set Stamina",
                    execute = function()
                        token.properties:SetCurrentHitpoints(value)
                    end,
                }
            end
    end

    leftButtons = gui.Panel{
        classes = {"bar-adjust-row", "left"},
        floating = true,
        AdjustButton("harm", "-"),
        AdjustButton("heal", "+"),
    }

    rightButtons = gui.Panel{
        classes = {"bar-adjust-row", "right"},
        floating = true,
        AdjustButton("temp", "TEMP", "temp"),
    }

    entryRow = gui.Panel{
        classes = {"bar-adjust-row", "collapsed"},
        floating = true,
        entryKey,
        entryInput,
    }

    adjustPanel = gui.Panel{
        --editOnly: these only apply changes, so they have no business showing
        --while the panel is read-only.
        classes = {"bar-adjust", "editOnly"},
        floating = true,
        leftButtons,
        rightButtons,
        entryRow,

        --Polled rather than handled: the engine's 'wheel' event never reaches
        --this subtree at all (verified at input, row and panel level), because
        --the scroll container the character panel sits in claims it first.
        --dmhub.mouseWheel reports the notch directly.
        --
        --Gated on the field having focus, so this only ever reads the wheel
        --while an entry box is actually up and being typed into.
        thinkTime = BAR_ENTRY_THINK_IDLE,
        think = function(element)
            if m_mode == nil then return end
            if not entryInput.valid or not entryInput.hasFocus then return end

            local notches = dmhub.mouseWheel
            if notches ~= 0 then
                NudgeEntry(notches)
                return
            end

            --A whole spin of the wheel settles into one change rather than one
            --per notch, so it is a single upload and a single undo step.
            if m_wheelPending ~= nil then
                m_wheelIdle = m_wheelIdle + BAR_ENTRY_THINK_OPEN
                if m_wheelIdle >= BAR_ENTRY_WHEEL_SETTLE then
                    local text = m_wheelPending
                    m_wheelPending = nil
                    ApplyValue(m_mode, m_token, text, element)
                end
            end
        end,

        refreshCharacter = function(element, token)
            local charid = nil
            if token ~= nil and token.valid then
                charid = token.charid
            end

            --Classic: monsters only. Heroes get the DMG / STAMINA / HEAL /
            --TEMP boxes in the row above instead.
            local barControls = TacPanel.UseTestPanel()
            if not barControls and token ~= nil and token.valid and token.properties ~= nil then
                pcall(function() barControls = token.properties:IsMonster() end)
            end
            element:SetClass("collapsed", not barControls)

            --A different creature mid-edit would apply the number to the wrong
            --one, so the entry closes rather than following along. Gated on the
            --charid CHANGING: refreshCharacter fires on every panel refresh,
            --not just on a new token, and closing unconditionally shut the box
            --again in the same frame it was opened. Losing the controls closes
            --it too, or the entry is stranded inside a collapsed panel.
            if m_mode ~= nil and (charid ~= m_tokenid or not barControls) then
                CloseEntry()
            end

            m_tokenid = charid
            m_token = token
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
    }

    return adjustPanel, function()
        OpenEntry("stamina")
    end
end

--- Display the health bar
--- @return Panel
function TacPanel.HealthBar()
    local m_tokenid = nil
    local m_token = nil

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

    --Resolved once: an inline token like this is not theme-reactive, matching
    --the other inline ResolveTokens sites in this file.
    local m_tempColor = ThemeEngine.ResolveTokens("@accent")

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

    --Forward-declared: labelPanel's press handler needs it, and it is not built
    --until the adjust controls are, which need labelPanel.
    local m_openStamina

    local icon = gui.Panel{
        classes = {"bgInverse"},
        width = 12,
        height = 12,
        valign = "center",
        halign = "left",
        hmargin = 4,
        lmargin = 50,
        --The whole cluster is one button; a child left interactable would eat
        --the press before its parent saw it.
        interactable = false,
    }
    local label = gui.Label{
        classes = {"fg", "sizeS", "number", "bold"},
        halign = "center",
        valign = "center",
        width = "auto",
        height = "auto",
        minWidth = 80,
        interactable = false,
    }

    local labelPanel = gui.Panel{
        width = "auto",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "horizontal",
        floating = true,
        --Click the number to set stamina outright. Needs a background image to
        --be a hit target at all, kept clear so nothing changes visually.
        bgimage = true,
        bgcolor = "clear",
        hoverCursor = "pressbutton",
        press = function(element)
            if TacPanel.IsReadOnly(element) then return end
            --Classic: monsters only, since heroes still have the STAMINA box
            --and the entry this opens lives inside the collapsed adjust panel.
            if not TacPanel.UseTestPanel() then
                local isMonster = false
                if m_token ~= nil and m_token.valid and m_token.properties ~= nil then
                    pcall(function() isMonster = m_token.properties:IsMonster() end)
                end
                if not isMonster then return end
            end
            if m_openStamina ~= nil then
                m_openStamina()
            end
        end,
        --The stamina history the STAMINA box used to show on hover.
        linger = function(element)
            local token = m_token
            if token ~= nil and token.valid and token.properties ~= nil then
                element.tooltip = gui.StatsHistoryTooltip{
                    description = "stamina",
                    entries = token.properties:GetStatHistory("stamina"):GetHistory()
                }
            end
        end,
        icon,
        label,
    }

    local adjustControls
    adjustControls, m_openStamina = TacPanel.BarAdjustControls(labelPanel)

    resultPanel = gui.Panel{
        classes = {"bordered"},
        --5% inset at each end so the bar stops short of the panel edges
        --rather than running the full width.
        width = "90%",
        flow = "horizontal",
        halign = "center",
        height = 20,
        cornerRadius = 0,
        bgcolor = "clear",
        fill,
        tempFill,
        labelPanel,
        --The adjust controls, revealed on hover. A direct child of the bar
        --because their reveal rule is "parent:hover", which only ever matches
        --the immediate parent.
        adjustControls,

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
            m_token = token

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

            --The TEMP box is gone -- it is a hover control on this bar now --
            --so without this the tempFill segment would show that there IS temp
            --stamina but not how much, and nothing else in the panel prints it.
            --Classic: heroes keep the TEMP box, which is the readout, so
            --printing it here too said the same number twice.
            local showTemp = TacPanel.UseTestPanel()
            if not showTemp then
                pcall(function() showTemp = props:IsMonster() end)
            end
            local staminaText = string.format("<b>%d/%d</b>", m_currentHP, m_maxHP)
            if showTemp and m_tempHP > 0 then
                staminaText = string.format("%s <color=%s>+%d</color>",
                    staminaText, m_tempColor, m_tempHP)
            end

            if m_dead then
                label.text = "DEAD"
                icon.bgimage = "ui-icons/Pin_Boss.png"
            elseif m_dying then
                label.text = staminaText
                icon.bgimage = "drawsteel/Icon_STA_Dying.png"
            elseif m_bloodied then
                label.text = staminaText
                icon.bgimage = "drawsteel/Icon_STA_Winded.png"
            else
                label.text = staminaText
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

            --Left-aligned so IMMUNITIES and the CONDITIONS line beneath it
            --share a left edge. Classic: only monsters have a portrait beside
            --this column, so only they left-align; heroes keep it centred.
            --
            --"flush" additionally drops the res-box padding and margin, which
            --between them pushed IMMUNITIES 10px in while CONDITIONS sat at
            --6px -- close enough to read as a misalignment rather than an
            --indent. Both now start on the bar's left edge.
            local flush = TacPanel.UseTestPanel()
            if not flush then
                pcall(function() flush = token.properties:IsMonster() end)
            end
            element.selfStyle.halign = cond(flush, "left", "center")
            element:SetClass("flush", flush)

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
                --Stacked they each take the full column; side by side they
                --split it, and a lone entry spans either way.
                local boxWidth = "94%"
                if not TacPanel.UseTestPanel() and hasWeak and hasImmune then
                    boxWidth = "47%"
                end
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

        --No section header: everything in this column labels itself -- the bar
        --prints its own numbers and each entry in the resource strip carries
        --its name -- so the header was chrome over nothing. tpad 0 takes back
        --the space it was holding.
        noTitle = true,
        tpad = 0,

        --This section's own bottom rule is dropped: it is only as wide as the
        --stamina column, so it stopped at the portrait and cut across the
        --middle of the block -- and the row around it already draws a
        --full-width one at the block's bottom edge.
        --
        --A class, not a selfStyle write: assigning a border table to selfStyle
        --at runtime does not take.
        classes = {"no-rule"},

        --DMG, STAMINA, HEAL and TEMP are the bar's own hover controls now (see
        --TacPanel.BarAdjustControls). Under it, recoveries reads as a key-value
        --line in the same grammar as IMMUNITY and the conditions row below --
        --it is the one pool spent directly ON stamina, so it belongs with the
        --bar rather than in a list of pools further down.
        TacPanel.HealthBar(),
        TacPanel.ResourceStrip(),
        TacPanel.Resistances(),
        TacPanel.ConditionsRow(),
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
            if TacPanel.IsReadOnly(element) then return end
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
            if TacPanel.IsReadOnly(element) then return end
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
            if TacPanel.IsReadOnly(element) then return end
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
                classes = {"movebox-value", "altitude-value"},
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
                    classes = {"altitude-btn", "editOnly"},
                    text = "+",
                    hoverCursor = "pressbutton",
                    data = { token = nil },
                    press = function(element)
                        if TacPanel.IsReadOnly(element) then return end
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
                    classes = {"altitude-btn-sep", "editOnly"},
                    text = "/",
                },
                gui.Label{
                    classes = {"altitude-btn", "editOnly"},
                    text = "-",
                    hoverCursor = "pressbutton",
                    data = { token = nil },
                    press = function(element)
                        if TacPanel.IsReadOnly(element) then return end
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

--- Put the stat boxes in a container onto their compact footprint: no frame,
--- label and value on one line. Applied to every token -- the boxes sit in the
--- column beside the portrait now, which has no room for the old square ones.
---
--- The class goes on each BOX rather than on the container because the
--- engine has no ancestor selector: a label inside a box can only see its
--- direct parent, so "parent:compact" has to find the class one level up.
--- @param element Panel The container whose children are stat boxes
--- @param token CharacterToken Unused; the signature is refreshCharacter's
function TacPanel.SetCompactBoxes(element, token)
    --Classic: the compact footprint is a monster thing, because only a monster
    --has a portrait taking a third of the row.
    local compact = TacPanel.UseTestPanel()
    if not compact and token ~= nil and token.valid and token.properties ~= nil then
        pcall(function() compact = token.properties:IsMonster() end)
    end

    for _, child in ipairs(element.children) do
        child:SetClass("compact", compact)
        --Characteristic boxes stack the value above the name when compact. A
        --no-op on the movement boxes, which have no such handler.
        child:FireEvent("setCompactOrder", compact)

        --SpeedBox wraps its value labels in an inner container so the
        --"hindered" variant can sit beside the base number. "parent:" matches
        --the DIRECT parent only, so those labels never saw the compact rule
        --and kept the 24pt full-size value while Disengage and Stability
        --shrank -- which is why Speed's number looked oversized. Tag the
        --wrapper too so the labels inside it match their neighbours.
        for _, grandchild in ipairs(child.children or {}) do
            if grandchild:HasClass("container") then
                grandchild:SetClass("compact", compact)

                --These wrappers declare valign="top" INLINE, and an inline arg
                --becomes selfStyle that no selector can override. Stacked
                --vertically top is right; side by side it pinned the small
                --label to the top of the row while the larger value centred,
                --which is why "+2" sat half a line below "Might". Set it
                --directly, since a rule cannot.
                grandchild.selfStyle.valign = cond(compact, "center", "top")
            end

            --AltitudeBox has the same problem one level deeper: its value sits
            --inside altitude-row, so "parent:compact" never reached it and the
            --altitude kept the 24pt hero-size number while everything beside it
            --shrank. Tagging the row fixes the size and lets the row size to its
            --contents so "On Ground" stays on the Speed line.
            if grandchild:HasClass("altitude-row") then
                grandchild:SetClass("compact", compact)
            end
        end
    end
end

--- Display the movement panel
--- @return Panel
function TacPanel.MovementPanel()
    return gui.Panel{
        classes = {"movement-panel"},
        refreshCharacter = TacPanel.SetCompactBoxes,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
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
    --The letter-chip and name, and the modifier, as separate locals. Which one
    --comes first is child order, not something a style rule can express, and it
    --follows the COMPACT state rather than the flag: compact stacks the value
    --above the name, the full-size box keeps the name on top.
    local titleRow = gui.Panel{
        classes = {"container", "char-title-row"},
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
    }

    local valueLabel = gui.Label{
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

    return gui.Panel{
        classes = {"characteristic-box"},
        hoverCursor = "pressbutton",
        data = { token = nil, valueOnTop = false },
        --Fired by TacPanel.SetCompactBoxes. Reassigns only on an actual flip:
        --that runs on every refreshCharacter, and rebuilding the child list each
        --time would churn for nothing.
        setCompactOrder = function(element, valueOnTop)
            if element.data.valueOnTop == valueOnTop then return end
            element.data.valueOnTop = valueOnTop
            element.children = cond(valueOnTop,
                {valueLabel, titleRow}, {titleRow, valueLabel})
        end,
        press = function(element)
            --rolling a characteristic acts as (and broadcasts for) the
            --character, so it counts as touching.
            if TacPanel.IsReadOnly(element) then return end
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
        --Matches data.valueOnTop above; setCompactOrder flips it from here.
        children = {titleRow, valueLabel},
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
        refreshCharacter = TacPanel.SetCompactBoxes,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
    }
end

--- The movement modes -- Fly, Burrow, Climb -- as a line under the movement
--- boxes. Collapses when the creature has none, which is most heroes.
---
--- Static text rather than more boxes: unlike Speed or Altitude there is
--- nothing to press here, and the row above already carries the numbers a
--- mode changes.
--- @return Panel
function TacPanel.MovementModes()
    return gui.Panel{
        classes = {"container", "collapsed"},
        width = "100%",
        height = "auto",
        halign = "left",
        flow = "vertical",
        --No horizontal padding: the movement boxes above sit on the container's
        --own left edge, and an inset here put "Movement" out of line with
        --"Speed". The label's own 2px lmargin matches the boxes' padding.
        hpad = 0,
        borderBox = true,

        refreshCharacter = function(element, token)
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                return
            end

            --Classic: monster-only. The line was part of the monster sheet's
            --reference block, not something a hero's STATISTICS carried.
            if not TacPanel.UseTestPanel() then
                local isMonster = false
                pcall(function() isMonster = token.properties:IsMonster() end)
                if not isMonster then
                    element:SetClass("collapsed", true)
                    return
                end
            end

            local props = token.properties

            local modes = {}
            for mode, speed in pairs(props:try_get("movementSpeeds", {})) do
                if speed > 0 then
                    --stored lower-case ("burrow"); title-case for display.
                    modes[#modes+1] = string.upper(string.sub(mode, 1, 1)) .. string.sub(mode, 2)
                end
            end
            table.sort(modes)

            local children = {}
            if #modes > 0 then
                children[#children+1] = gui.Label{
                    classes = {"ms-profile"},
                    text = string.format("Movement  %s", string.join(modes, ", ")),
                }
            end

            if #children == 0 then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)
            element.children = children
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
    }
end

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
            TacPanel.MovementModes(),
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
                if TacPanel.IsReadOnly(element) then
                    return
                end
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
            -- Growing-resource benefits (e.g. the Fury's Growing Ferocity) last
            -- until the end of the turn even after the resource is spent back below
            -- the threshold. Track the turn's high-water mark so a benefit that was
            -- active earlier this turn still shows -- in a muted "expiring" color --
            -- once the resource drops below it, instead of vanishing immediately.
            local resourcesHigh = creature:GetProgressionResourceHighWaterMark()

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
                    local available = entry.resources <= characterResources
                    row:SetClass("available", available)
                    row:SetClass("expiring", (not available) and entry.resources <= resourcesHigh)
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
--- @param args table {title, styles, classes, data, noTitle, ...} plus array children
--- @return Panel
function TacPanel.CollapsiblePanel(args)
    local title = args.title or ""
    local extraClasses = args.classes or {}
    local extraData = args.data or {}
    local altBg = args.altBg ~= false
    local sectionId = args.sectionId
    --For sections whose content labels itself, so a header would be a line of
    --chrome over nothing. The bar is still built -- it carries the collapse
    --arrow and drag handle -- just hidden.
    local noTitle = args.noTitle == true
    args.title = nil
    args.styles = nil
    args.classes = nil
    args.data = nil
    args.altBg = nil
    args.sectionId = nil
    args.noTitle = nil

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
        classes = cond(noTitle, {"tp-title-bar", "collapsed"}, {"tp-title-bar"}),
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
                    if TacPanel.IsReadOnly(el) then return end
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
                        if TacPanel.IsReadOnly(el) then return end
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
                                        if TacPanel.IsReadOnly(element) then return end
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
                                    if TacPanel.IsReadOnly(element) then return end
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
                                    if TacPanel.IsReadOnly(element) then return end
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

--- The monster modes section: shows only for creatures with a Monster Modes
--- modifier (see the monstermodes system in MCDMCreature.lua) and lets the
--- Director switch the creature's current mode. Chips mirror the Routines
--- section's look; exactly one mode is always selected (mode 1 by default).
--- The header takes the granting modifier's name (e.g. TRUE NAME) so the
--- section speaks the statblock's language rather than engine language.
--- @return Panel
function TacPanel.MonsterMode()
    return TacPanel.CollapsiblePanel{
        sectionId = "monstermode",
        classes = {"collapsed"},
        altBg = false,
        title = "MODES",
        data = { signature = nil },
        setCollapse = function(element)
            element:FireEvent("refreshCharacter", element.data.token)
        end,
        refreshCharacter = function(element, token)
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                element.data.signature = nil
                return
            end

            element.data.token = token

            local modes, sectionTitle = token.properties:GetMonsterModes()
            if modes == nil then
                element:SetClass("collapsed", true)
                element.data.signature = nil
                return
            end

            element:SetClass("collapsed", false)

            --header takes the granting trait's name (updates even while the
            --section is collapsed, since the title bar stays visible).
            local titleText = string.upper(sectionTitle or "Modes")
            local titleBar = element.children[1]
            if titleBar ~= nil then
                for _,child in ipairs(titleBar.children) do
                    if child:HasClass("panel-title") then
                        if child.text ~= titleText then
                            child.text = titleText
                        end
                        break
                    end
                end
            end

            if element.data.collapsed then
                return
            end

            local selected = token.properties:GetMonsterMode()
            if selected > #modes then
                selected = 1
            end

            --only rebuild the chips when the modes or selection actually change.
            local sigParts = {}
            for _,mode in ipairs(modes) do
                sigParts[#sigParts+1] = string.format("%s/%s", mode.name or "", mode.description or "")
            end
            local signature = string.format("%s#%d#%s", table.concat(sigParts, "|"), selected, token.charid)
            if signature == element.data.signature then
                return
            end
            element.data.signature = signature

            local children = {}
            for i,mode in ipairs(modes) do
                local classes = {"rt-chip", "mm-chip"}
                if i == selected then
                    classes[#classes+1] = "selected"
                end

                local hover = nil
                if mode.description ~= nil and mode.description ~= "" then
                    hover = gui.Tooltip(mode.description)
                end

                children[#children+1] = gui.Panel{
                    classes = classes,
                    hover = hover,
                    press = function(el)
                        if TacPanel.IsReadOnly(el) then
                            return
                        end
                        if i == selected then
                            --the creature is always in exactly one mode; no deselect.
                            return
                        end

                        local tok = element.data.token
                        if tok == nil or not tok.valid then
                            return
                        end

                        --a squad minion's mode change applies to its whole
                        --squad (never the captain); one combined undo step.
                        local squadToks = creature.GetMonsterModeChangeTokens(tok, i)
                        for _,squadTok in ipairs(squadToks) do
                            squadTok:ModifyProperties{
                                description = tr("Set Monster Mode"),
                                combine = true,
                                execute = function()
                                    squadTok.properties:SetMonsterMode(i)
                                end,
                            }
                        end

                        element:FireEvent("refreshCharacter", tok)
                    end,
                    gui.Label{
                        classes = {"rt-chip", "mm-chip"},
                        text = mode.name or string.format("Mode %d", i),
                    },
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
            classes = {"rt-container"},
            wrap = true,
            setContent = function(element, newChildren)
                element.children = newChildren
            end,
        },
    }
end

-- =====================================================================
-- Monster sheet sections: Abilities / Triggers / Traits
--
-- The panel already carries stamina, immunities, characteristics, speed,
-- disengage and stability. What it has no home for is what the monster
-- actually DOES: without these sections a director has to leave the panel
-- and open an action-bar button to read tier text mid-fight.
--
-- Monsters only -- every section below hides itself for heroes, who have
-- their own ability surfaces.
-- =====================================================================

--- Rewrite a CollapsiblePanel's title label in place, the way MonsterMode
--- does. The title bar stays visible while a section is collapsed, so a
--- count in the title has to update even when the body does not rebuild.
--- @param element Panel The CollapsiblePanel root
--- @param text string
local function SetSectionTitle(element, text)
    local titleBar = element.children[1]
    if titleBar == nil then return end
    for _, child in ipairs(titleBar.children) do
        if child:HasClass("panel-title") then
            if child.text ~= text then
                child.text = text
            end
            return
        end
    end
end

--- Categorizations that belong in the Triggers section rather than Abilities.
local g_msTriggerCategories = {
    ["Trigger"] = true,
    ["Triggered Ability"] = true,
}

--- Categorizations that belong in the Villain Actions section.
local g_msVillainCategories = {
    ["Villain Action"] = true,
}

--- Split a monster's activated abilities into the three display buckets.
--- @param props any The monster's creature properties
--- @return table abilities, table triggers, table villainActions
local function MonsterSheetAbilities(props)
    local abilities = {}
    local triggers = {}
    local villainActions = {}
    for _, ability in ipairs(props:GetActivatedAbilities{
        excludeGlobal = true, allLoadouts = true, bindCaster = true,
    }) do
        local cat = ability:try_get("categorization", "")
        if g_msTriggerCategories[cat] then
            triggers[#triggers+1] = ability
        elseif g_msVillainCategories[cat] or ability:has_key("villainAction") then
            villainActions[#villainActions+1] = ability
        else
            abilities[#abilities+1] = ability
        end
    end
    return abilities, triggers, villainActions
end

--- A hero's traits: every feature carrying real description text, from every
--- source the builder assigned -- ancestry, culture, career, class, kit.
---
--- Three kinds of entry are dropped. Those with no body text, which are a
--- heading over nothing. The CHOICE SLOTS -- "Purchased Dwarf Traits",
--- "Warden Language", "Censor Order" -- which are where a pick was made rather
--- than what was picked; typeName tells them apart, since everything resolved
--- to actual content comes back as a plain CharacterFeature. And the
--- boilerplate IsTraitBoilerplate rejects -- kit stat dumps, skill grants, and
--- the handful of fixed names below.
--- Names repeat across sources, so identical name+text pairs are shown once.
---
--- This overlaps the FEATURES section on purpose: that one groups by source and
--- filters, which is what makes 47 entries usable, while this one prints the
--- rules text the way the monster sheet does.
--- @param props any
--- @return table[] List of {name=, text=, live=}
--- Entries that survive the typeName test but say nothing worth a card: either
--- pure scaffolding, or a duplicate of something the panel already shows.
--- Keyed by exact name; the kit stats are matched by suffix because the name is
--- built from the kit's ("Panther Kit Stats", see Kit:StatsFeature).
local TRAIT_BOILERPLATE = {
    --Permission to wear a kit at all, not a trait.
    ["Kit"] = true,
    --The number of recoveries. Its description is the bare figure, and the
    --recoveries readout under the stamina bar carries it properly.
    ["Recoveries"] = true,
    --Boilerplate every hero with a culture has, word for word.
    ["Culture Lore Benefit"] = true,
}

--- True for an entry that adds nothing to TRAITS.
--- @param name string
--- @param text string
--- @return boolean
local function IsTraitBoilerplate(name, text)
    if TRAIT_BOILERPLATE[name] then return true end

    --The kit's stat dump ("Health: 6 Speed: 1 Disengage: 0 ..."), which is what
    --the KIT line in the identity strip shows on hover.
    if name:match(" Kit Stats$") ~= nil then return true end

    --Bare skill grants belong to SKILLS & LANGUAGES, which lists them by
    --category. They come in two shapes.
    --
    --Named for the skill they grant ("Nature Skill", "Perform Skill"). Caught
    --by name because the wording is not consistent -- "You have the Nature
    --skill.", "You are proficient with Perform.", and one that reads "You have
    --the Psionics." with the word skill missing altogether.
    if name:match(" [Ss]kills?$") ~= nil then return true end

    --Named for the skill alone ("Lead", "Sneak"), so only the text identifies
    --them. Anchored at BOTH ends so a trait that merely opens this way keeps
    --its card: "You gain the music skill and you wield an instrument" grants a
    --kit as well, and stays.
    local flat = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
    if flat:match("^You have the .+ [Ss]kill%.?$") ~= nil
        or flat:match("^You gain the .+ [Ss]kill%.?$") ~= nil
        or flat:match("^You are proficient with .+%.?$") ~= nil then
        return true
    end

    return false
end

--- Drop the builder's pick-one instruction from the front of a perk or trait's
--- text. Compendium entries often open with one -- "Choose one skill you
--- already have from the crafting skill group." -- which is written for the
--- character builder. By the time the entry reaches a play surface the pick has
--- been made (the panel only lists chosen entries), so the line is a question
--- the player already answered, sitting above the rules text that matters.
---
--- Deliberately narrow: only a LEADING sentence that opens with "Choose", and
--- only when rules text follows it. An entry whose instruction is all it says
--- ("Choose one of the following abilities.") is left alone rather than
--- reduced to a blank card.
--- @param text string
--- @return string
local function StripChoiceInstruction(text)
    if type(text) ~= "string" or text == "" then
        return text
    end
    --The instruction ends at its first full stop, which is normally also the
    --end of the first line.
    local rest = text:match("^%s*[Cc]hoose[^\n]-%.%s*(.+)$")
    if rest == nil or rest:match("^%s*$") ~= nil then
        return text
    end
    return rest
end

--- True when a feature's tags say it renders somewhere OTHER than a trait card:
--- "Hidden" is plumbing that is never shown, and "Ability" / "Trigger" features
--- display as an ability card or a trigger row instead. Without this they show
--- up twice, or show up at all when they were meant to be invisible. The pcall
--- guards entries that are not CharacterFeatures -- reading a method a type does
--- not define raises on a game-typed instance.
--- @param feature any
--- @return boolean
local function TraitRendersElsewhere(feature)
    local kind = "normal"
    pcall(function() kind = feature:DisplayKind() end)
    return kind ~= "normal"
end

local function HeroSheetTraits(props)
    local out = {}
    local seen = {}
    local entries = nil
    pcall(function() entries = props:GetClassFeaturesAndChoicesWithDetails() end)
    for _, entry in ipairs(entries or {}) do
        local feature = entry.feature or entry
        --Feature entries are a mix of CharacterFeature and
        --CharacterFeatureChoice, and reading a field one type does not define
        --raises rather than returning nil.
        local name, text, typeName = nil, nil, nil
        pcall(function() name = feature.name end)
        pcall(function() text = feature.description end)
        pcall(function() typeName = feature.typeName end)

        --A signature trait is real content even when it is a choice: several
        --ancestries phrase theirs as a pick (the Dwarf chooses which rune to
        --carve), so typeName alone would drop those and keep the rest.
        local isContent = typeName == "CharacterFeature"
            or (typeName == "CharacterFeatureChoice"
                and name ~= nil and name:match("^Signature Trait") ~= nil)

        if isContent
            and name ~= nil and name ~= "" and text ~= nil and text ~= ""
            and not TraitRendersElsewhere(feature)
            and not IsTraitBoilerplate(name, text) then
            local key = string.format("%s|%s", name, text)
            if not seen[key] then
                seen[key] = true
                --Stripped at emit, so the boilerplate and dedupe tests above
                --still see the entry's original wording.
                out[#out+1] = { name = name, text = StripChoiceInstruction(text), live = false }
            end
        end
    end
    return out
end

--- Every trait shown in print: group traits, the creature's own features and
--- its notes. Entries with no body are dropped -- monster:Render prints a bare
--- "Monster Notes:" heading for those, which reads as a bug.
--- @param props any
--- @return table[] List of {name=, text=, live=}
local function MonsterSheetTraits(props)
    local out = {}
    local function add(name, text, live)
        if name == nil or name == "" then return end
        if text == nil or text == "" then return end
        out[#out+1] = { name = name, text = text, live = live == true }
    end
    --Heroes take a different source entirely: they have no group traits and no
    --characterFeatures, so the monster sources would leave TRAITS holding
    --nothing but their notes, which the NOTES section already prints.
    local isMonster = false
    pcall(function() isMonster = props:IsMonster() end)
    if not isMonster then
        --Classic: a hero has no traits section at all, so nothing to gather.
        if not TacPanel.UseTestPanel() then return out end
        return HeroSheetTraits(props)
    end

    --Reading a method a type does not define RAISES on a game-typed instance,
    --and not every monster asset binds as monster.
    local groupTraits = nil
    pcall(function() groupTraits = props:GetTraitsFromGroup() end)
    for _, feature in ipairs(groupTraits or {}) do
        if not TraitRendersElsewhere(feature) then
            add(feature.name, feature.description)
        end
    end
    for _, feature in ipairs(props:try_get("characterFeatures", {})) do
        if not TraitRendersElsewhere(feature) then
            add(feature.name, feature.description)
        end
    end
    for _, note in ipairs(props:try_get("notes", {})) do
        add(note.title, note.text)
    end

    --With Captain is NOT here: it moved up into the identity strip, under the
    --monster type, because it describes what this creature is rather than
    --something it can do. Listing it in both places would double it.

    return out
end

--- Tallest an embedded ability card may grow before its body scrolls. A long
--- villain action would otherwise push the whole section off the panel; Render
--- puts the overflow in its own scroll frame, keeping the title visible.
local MS_ABILITY_CARD_MAXHEIGHT = 360

--- One ability card, rendered by the SAME code as the card the action-bar tray
--- shows on hover (ActivatedAbility:Render) rather than by a local lookalike.
---
--- This used to be a hand-built compact card: name band, keyword line, tier
--- rows. It drifted from the real card and had to re-derive tier text and
--- monster damage scaling itself. Reusing the renderer means the panel gets
--- the book layout, the power-roll block, potency gates and level scaling for
--- free, and cannot drift again.
---
--- quietTitleBand is the one deviation: the floating card wears a full-bleed
--- color band, which is far too loud repeated down a panel, so the band drops
--- to a palette surface and the action color moves onto the name.
--- @param ability any
--- @param token CharacterToken
--- @return Panel
local function MonsterSheetAbilityCard(ability, token)
    return ability:Render({
        width = "100%",
    }, {
        token = token,
        maxHeight = MS_ABILITY_CARD_MAXHEIGHT,
        quietTitleBand = true,
        hideTabs = true,
        cardScale = MS_CARD_SCALE,
    })
end

--- Build one trait / trigger card: bold name over its rules text.
--- @param name string
--- @param text string
--- @param props any
--- @param live? boolean Mark the card as currently in effect
--- @return Panel
--- One name-and-prose card in the monster-sheet grammar.
---
--- Heroes get an "Open on sheet" link in the corner: these cards replaced the
--- FEATURES chips, whose one affordance beyond reading was jumping to the
--- editable sheet. Monsters do not get it -- they have no features tab to land
--- on -- and it is hidden in read-only mode, where the sheet is not editable
--- anyway.
--- @param name string
--- @param text string
--- @param props any The creature, for GoblinScript interpolation
--- @param live boolean|nil Accent the card (a minion's live captain bonus)
--- @param token CharacterToken|nil Enables the sheet link when it is a hero
--- @return Panel
local function MonsterSheetTextCard(name, text, props, live, token)
    local classes = {"ms-card"}
    if live then
        classes[#classes+1] = "captain-live"
    end

    --Classic: the FEATURES chips carry this jump instead.
    local sheetLink = nil
    local isHero = false
    if TacPanel.UseTestPanel() then
        pcall(function() isHero = props:IsHero() end)
    end
    if isHero and token ~= nil and token.valid then
        local capturedId = token.id
        sheetLink = gui.Label{
            classes = {"ms-sheet-link", "editOnly"},
            text = "Open on sheet",
            hoverCursor = "hand",
            click = function(element)
                if TacPanel.IsReadOnly(element) then return end
                FeatureCategoriser.OpenSheetAtFeaturesTab(capturedId, name)
            end,
        }
    end

    return gui.Panel{
        classes = classes,
        gui.Panel{
            classes = {"ms-head", "ms-action-other"},
            --Markdown-emboldened rather than bold=true: this is exactly how the
            --ability card sets its title against the Light-weight Newzald face.
            gui.Label{
                classes = {"ms-name"},
                markdown = true,
                text = string.format("<b>%s</b>", name),
            },
        },
        gui.Panel{
            classes = {"ms-card-body"},
            gui.Label{
                classes = {"ms-body"},
                text = StringInterpolateGoblinScript(text, props),
            },
            sheetLink,
        },
    }
end

--- Shared builder for the three monster-sheet sections.
---
--- Each rebuild costs roughly 10ms of Lua plus engine layout, and
--- refreshCharacter fires on every property change on the token (each point
--- of damage, each condition). The signature guard means routine refreshes
--- cost a table walk instead of a rebuild -- the same pattern MonsterMode
--- uses.
---
--- A section with nothing in it hides completely rather than leaving an
--- empty header behind, and the header carries its item count so the number
--- is readable while the section is closed.
--- @param args table {sectionId=, title=, collapsed=, items=fun(props): any[], key=fun(item): string, card=fun(item, props, token): Panel}
--- @return Panel
local function MonsterSheetSection(args)
    return TacPanel.CollapsiblePanel{
        sectionId = args.sectionId,
        classes = {"collapsed"},
        altBg = false,
        title = args.title,
        data = { collapsed = args.collapsed == true, token = nil, signature = nil },

        setCollapse = function(element)
            element:FireEvent("refreshCharacter", element.data.token)
        end,

        refreshCharacter = function(element, token)
            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                element.data.token = nil
                element.data.signature = nil
                return
            end

            element.data.token = token

            --Classic: these sections are the monster sheet's. Heroes got
            --ABILITIES and TRAITS only with the rework.
            if not TacPanel.UseTestPanel() then
                local isMonster = false
                pcall(function() isMonster = token.properties:IsMonster() end)
                if not isMonster then
                    element:SetClass("collapsed", true)
                    element.data.signature = nil
                    return
                end
            end

            local props = token.properties
            local items = args.items(props)

            --Nothing to show: hide the whole section, header included.
            if #items == 0 then
                element:SetClass("collapsed", true)
                element.data.signature = nil
                return
            end

            element:SetClass("collapsed", false)
            SetSectionTitle(element, string.format("%s (%d)", args.title, #items))

            if element.data.collapsed then
                return
            end

            local parts = { token.charid }
            for _, item in ipairs(items) do
                parts[#parts+1] = args.key(item)
            end
            local signature = table.concat(parts, "|")
            if signature == element.data.signature then
                return
            end
            element.data.signature = signature

            local children = {}
            for _, item in ipairs(items) do
                children[#children+1] = args.card(item, props, token)
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
            classes = {"ms-stack"},
            setContent = function(element, newChildren)
                element.children = newChildren
            end,
        },
    }
end

--- Signature fragment for one ability: name plus guid, so a swapped loadout
--- or a renamed ability forces a rebuild but a damage tick does not.
--- @param ability any
--- @return string
local function MonsterSheetAbilityKey(ability)
    return string.format("%s/%s", ability.name or "", ability:try_get("guid", ""))
end

--- The monster's abilities, each with its power-roll tiers.
--- @return Panel
function TacPanel.MonsterAbilities()
    return MonsterSheetSection{
        sectionId = "monsterabilities",
        title = "ABILITIES",
        --Closed by default: a solo's eight abilities fill the dock several
        --times over, and the collapsed path skips the build entirely.
        collapsed = true,
        items = function(props)
            local abilities = MonsterSheetAbilities(props)
            return abilities
        end,
        key = MonsterSheetAbilityKey,
        card = function(ability, props, token)
            return MonsterSheetAbilityCard(ability, token)
        end,
    }
end

--- Villain actions, in their own section the way the book prints them.
--- @return Panel
function TacPanel.MonsterVillainActions()
    return MonsterSheetSection{
        sectionId = "monstervillainactions",
        title = "VILLAIN ACTIONS",
        collapsed = true,
        items = function(props)
            local _, _, villainActions = MonsterSheetAbilities(props)
            return villainActions
        end,
        key = MonsterSheetAbilityKey,
        card = function(ability, props, token)
            return MonsterSheetAbilityCard(ability, token)
        end,
    }
end

--- Triggered abilities, kept apart from main actions the way the book does.
--- @return Panel
function TacPanel.MonsterTriggers()
    return MonsterSheetSection{
        sectionId = "monstertriggers",
        title = "TRIGGERS",
        collapsed = true,
        items = function(props)
            local _, triggers = MonsterSheetAbilities(props)
            return triggers
        end,
        key = MonsterSheetAbilityKey,
        card = function(ability, props, token)
            return MonsterSheetAbilityCard(ability, token)
        end,
    }
end

--- Traits printed in full: for monsters its group traits, features and notes;
--- for heroes every feature that carries description text.
--- @return Panel
function TacPanel.MonsterTraits()
    return MonsterSheetSection{
        sectionId = "monstertraits",
        title = "TRAITS",
        collapsed = true,
        items = MonsterSheetTraits,
        key = function(trait)
            return trait.name
        end,
        card = function(trait, props, token)
            return MonsterSheetTextCard(trait.name, trait.text, props, trait.live, token)
        end,
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
                classes = {"sizeM", "editOnly"},
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
                    if TacPanel.IsReadOnly(element) then return end
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

            -- Opens the squad manager modal; the panel itself is read-only.
            gui.Button{
                classes = {"sizeS", "editOnly"},
                halign = "center",
                width = 150,
                height = 28,
                vmargin = 4,
                text = "Edit Squads",
                data = { token = nil },
                refreshToken = function(element, token)
                    element.data.token = token
                end,
                hover = function(element)
                    element.tooltip = gui.Tooltip("Open the squad manager to reassign, combine, split, rename, recolor, or delete your squads.")
                end,
                press = function(element)
                    if TacPanel.IsReadOnly(element) then return end
                    local token = element.data.token
                    if token == nil or not token.valid then return end
                    DrawSteelMinion.ShowSquadManager(token)
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

--- Register a heroic-resource display box.
---
--- `where` picks which of the two homes it renders in on the reworked panel:
--- "resources" (default) puts it at the top of RESOURCES, "strip" puts it in
--- the row under the stamina bar. Both render it compact.
---
--- `classic` opts the display into the pre-rework HEROIC RESOURCES section as
--- well; without it a display only appears on the reworked panel.
--- @param entry {id: string, create: fun(): Panel, ord: number, where: nil|string, classic: nil|boolean}
function TacPanel.RegisterHeroicResourceDisplay(entry)
    g_heroicResourceDisplays[entry.id] = entry
end

TacPanel.RegisterHeroicResourceDisplay{
    id = "victories",
    create = TacPanel.VictoriesBox,
    ord = 0,
    classic = true,
}

TacPanel.RegisterHeroicResourceDisplay{
    id = "heroic",
    create = TacPanel.HeroicResourcesBox,
    ord = 1,
    classic = true,
}

--Recoveries is the exception: it stays in the strip above the stamina bar,
--because what it does is put stamina back.
TacPanel.RegisterHeroicResourceDisplay{
    id = "recoveries",
    create = TacPanel.RecoveriesBox,
    ord = 0,
    where = "strip",
}

--Hero tokens and surges used to sit beside the portrait. They are the same
--kind of thing as victories and the heroic resource -- a pool you spend --
--so they belong with them, and moving them freed the top of the panel for the
--identity strip.
TacPanel.RegisterHeroicResourceDisplay{
    id = "herotokens",
    create = TacPanel.HeroTokenBox,
    ord = 3,
}

TacPanel.RegisterHeroicResourceDisplay{
    id = "surges",
    create = TacPanel.SurgesBox,
    ord = 2,
}

--- Put one resource box onto the strip's compact footprint: no frame, label
--- and value on one line, matching the characteristic boxes in STATISTICS.
---
--- Done here rather than purely in style rules because these boxes declare
--- halign, valign, width and border INLINE, and an inline arg becomes selfStyle
--- that no selector can override. The class still goes on every level a
--- "parent:" selector has to see, which is each box AND each container inside
--- it -- the engine has no ancestor selector.
--- @param box Panel
--- @param variant string|nil "keyline" renders a "KEY: values" line in the
---        grammar of the IMMUNITY row, for the strip under the stamina bar.
---        "badge" drops the label for icon and number alone, for RESOURCES.
--- @return Panel box The same panel, for inline use
function TacPanel.SetCompactResourceBox(box, variant)
    local keyline = variant == "keyline"
    local badge = variant == "badge"

    box:SetClass("compact", true)
    if variant ~= nil then
        box:SetClass(variant, true)
    end

    for _, child in ipairs(box.children or {}) do
        if child:HasClass("stambox-title") or child:HasClass("title") then
            --A badge is its icon and number; the name it drops is on the
            --tooltip. Collapsing holds even for the heroic resource, which
            --rewrites its own text every refresh but never its classes.
            if badge then
                child:SetClass("collapsed", true)
            end
            --The key wants the colon the resistance and conditions rows carry.
            if keyline and child.text ~= nil and child.text ~= "" and not child.text:match(":$") then
                child.text = child.text .. ":"
            end
        end
    end

    local function walk(panel, depth)
        if depth > 3 then return end
        for _, child in ipairs(panel.children or {}) do
            --Hero tokens' refresh button floats over the box's bottom-right
            --corner, which in a one-line box means on top of the value. Put it
            --back in the flow so it sequences after it. Reserving space for it
            --instead does not work: there is no rpad.
            if child:HasClass("refresh-icon") then
                child.floating = false
                --Half of what sizeS gives an icon button (20). Written to
                --selfStyle rather than a style rule because the sizeS rules in
                --DefaultStyles carry priority 5 and would win.
                child.selfStyle.width = 10
                child.selfStyle.height = 10
            end

            if child:HasClass("container") then
                --The pips are dropped in a compact box: the count and its max
                --say the same thing in a fraction of the width. Identify the
                --wrapper by what it holds, since it is a bare container like
                --the others.
                --
                --Collapsing the wrapper holds, where collapsing the rows would
                --not: updatePips reassigns the collapsed state of the two rows
                --inside it on every refresh, but never of this.
                local isPips = false
                for _, grandchild in ipairs(child.children or {}) do
                    if grandchild:HasClass("recovery-pip-row") then
                        isPips = true
                    end
                end

                if isPips then
                    child:SetClass("collapsed", true)
                    goto continue
                end

                child:SetClass("compact", true)
                --Tagged at every level: "parent:" reaches one down, and the
                --values sit two containers deep.
                if variant ~= nil then
                    child:SetClass(variant, true)
                end
                child.selfStyle.halign = "left"
                child.selfStyle.valign = "center"
                child.selfStyle.width = "auto"
                child.selfStyle.height = "auto"
                --Everything in a compact box reads left to right, including the
                --containers that stack their contents in the full-size one.
                child.selfStyle.flow = "horizontal"
                child.selfStyle.hmargin = 0
                --Recoveries rules its value off from its count with inline
                --borders. A style rule cannot clear them, and assigning a
                --border table to selfStyle does not take -- but the colour
                --does, so they are painted out instead.
                child.selfStyle.borderColor = "clear"

                --That divider was the only thing keeping the recovery AMOUNT
                --apart from the COUNT remaining; without it the two numbers ran
                --together and "+6" beside "8" read as "+68". A gap says the
                --same thing without a hairline this small.
                for _, grandchild in ipairs(child.children or {}) do
                    if grandchild:HasClass("recovery-value") then
                        child.selfStyle.rmargin = 8
                    end
                end

                walk(child, depth + 1)
            end

            ::continue::
        end
    end
    walk(box, 0)

    return box
end

--- The compact resource panes registered for one home, in display order.
--- @param where string "strip" or "resources"
--- @return Panel[]
local function BuildResourceDisplays(where)
    local displays = {}
    for _, entry in pairs(g_heroicResourceDisplays) do
        if (entry.where or "resources") == where then
            local pane = entry.create()
            pane.data.ord = entry.ord or 0
            --The strip reads as a key-value line under the bar; the RESOURCES
            --section shows each entry as an icon and a number.
            TacPanel.SetCompactResourceBox(pane, cond(where == "strip", "keyline", "badge"))
            displays[#displays + 1] = pane
        end
    end

    table.sort(displays, function(a, b)
        return (a.data.ord or 0) < (b.data.ord or 0)
    end)

    return displays
end

--- The resource strip above the stamina bar. Recoveries alone by default --
--- the other pools live at the top of HEROIC RESOURCES -- but anything
--- registered with where = "strip" joins it.
--- @return Panel
function TacPanel.ResourceStrip()
    local displays = BuildResourceDisplays("strip")

    return gui.Panel{
        classes = {"resource-strip", "under-bar", "collapsed"},
        children = displays,

        --Each box gates itself on what the creature actually has; this only
        --decides whether the row exists at all, so a monster does not carry its
        --padding for nothing.
        refreshCharacter = function(element, token)
            local show = false
            if token ~= nil and token.valid and token.properties ~= nil then
                local creature = token.properties
                pcall(function()
                    show = creature:IsHero() or creature:IsRetainer() or creature:IsCompanion()
                end)
            end
            element:SetClass("collapsed", not show)
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
    }
end

--- Display the heroic resources info
--- @return Panel
function TacPanel.HeroicResources()
    --Victories, hero tokens, surges and the heroic resource head the section as
    --one compact row -- what you currently have -- with the gain checklist and
    --the growing-resource table below saying how it moves.
    local displays = BuildResourceDisplays("resources")

    return TacPanel.CollapsiblePanel{
        sectionId = "heroicresources",
        classes = {"collapsed"},
        altBg = false,
        title = "RESOURCES",
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
            classes = {"resource-strip", "badges"},
            hpad = 4,
            borderBox = true,
            children = displays,
        },

        gui.Panel{
            classes = {"container"},
            width = "100%",
            valign = "top",
            halign = "left",
            pad = 4,
            flow = "horizontal",
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
function TacPanel.OtherResourceRow(token, resource, quantity, styleCache, readOnly)
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
            editable = not readOnly,
            text = string.format("%d/%d", remaining, quantity or 0),
            change = function(element)
                local rowData = element.parent.data
                local tok = rowData.token
                if tok == nil or not tok.valid then return end
                if TacPanel.IsReadOnly(element) then
                    local ro_expended = tok.properties:GetResourceUsage(rowData.resourceId, rowData.usageLimit) or 0
                    element.textNoNotify = string.format("%d/%d", math.max(0, (rowData.maxQuantity or 0) - ro_expended), rowData.maxQuantity or 0)
                    return
                end
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
        --Was "RESOURCES", which only worked while the heroic one was called
        --HEROIC RESOURCES. It has that name now, so this one takes the
        --qualifier or the panel carries two identical headers.
        title = "OTHER RESOURCES",
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
                local readOnly = TacPanel.IsReadOnly(element)
                local children = {}
                for _, entry in ipairs(info.entries) do
                    children[#children+1] = TacPanel.OtherResourceRow(
                        info.token, entry.resource, entry.quantity, resourceStyles, readOnly)
                end
                element.children = children
            end,
        },
    }
end

--- Languages a creature knows, sorted by name.
--- @param creature any
--- @return table[] Language table entries
local function KnownLanguages(creature)
    --Visible-only: a language the creature knows can have been hidden
    --(soft-deleted) in the compendium since, and a deleted language should not
    --keep showing on the panel.
    local languagesTable = dmhub.GetTableVisible(Language.tableName) or {}
    local languages = {}
    for langid, _ in pairs(creature:LanguagesKnown()) do
        local language = languagesTable[langid]
        if language then
            languages[#languages + 1] = language
        end
    end
    table.sort(languages, function(a, b) return a.name < b.name end)
    return languages
end

--- Display the Skills & Languages panel.
---
--- Monsters have no skills, so there is nothing here worth folding away: they
--- get a bare "Languages: ..." line with no header and no expander, hidden
--- entirely when they speak nothing. Heroes are untouched -- they keep their
--- skill proficiencies, the SKILLS & LANGUAGES title, the collapse arrow, and
--- the section stays put whether or not it has content.
--- @return Panel
function TacPanel.SkillLanguages()
    return TacPanel.CollapsiblePanel{
        sectionId = "skilllanguages",
        altBg = false,
        title = "SKILLS & LANGUAGES",

        --Without these forwards the outer panel never refreshes: the sections
        --are driven by setToken/refreshToken, not by a tree-wide
        --refreshCharacter, so everything below ran only on the body panel
        --(which has its own forwards) and this handler never fired at all.
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        refreshCharacter = function(element, token)
            if token == nil or not token.valid or token.properties == nil then
                return
            end

            local isMonster = false
            pcall(function() isMonster = token.properties:IsMonster() end)
            local titleBar = element.children[1]

            if not isMonster then
                element:SetClass("collapsed", false)
                if titleBar ~= nil then titleBar:SetClass("collapsed", false) end
                --Put back what the monster branch below zeroes. The panel is
                --reused across tokens, so without this a hero selected after a
                --monster kept the monster's headerless top edge. 8 is tacpanel's
                --vpad, which is what this would inherit untouched.
                element.selfStyle.tpad = 8
                SetSectionTitle(element, "SKILLS & LANGUAGES")
                return
            end

            local languages = KnownLanguages(token.properties)
            if #languages == 0 then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)
            --No header and no expander for monsters: one line of content does
            --not earn a section. The body has to be forced open as well as the
            --bar hidden, or a section left collapsed by an earlier click would
            --hide the line with no way to get it back.
            if titleBar ~= nil then titleBar:SetClass("collapsed", true) end
            element.data.collapsed = false
            element:FireEventTree("setCollapse", false)
            element.selfStyle.tpad = 0
        end,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            refreshCharacter = function(element, token)
                local creature = token.properties
                local children = {}

                local isMonster = false
                pcall(function() isMonster = creature:IsMonster() end)

                -- Skill categories: heroes only. Monsters show languages alone.
                if not isMonster then
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
                end

                -- Languages
                local names = {}
                for _, language in ipairs(KnownLanguages(creature)) do
                    names[#names + 1] = language.name
                end
                if #names > 0 then
                    --The prefix now carries the labelling for monsters too:
                    --they have no header above this line to name it.
                    local text = string.format("**<color=@fgMuted>Languages:</color>** %s",
                        string.join(names, ", "))
                    children[#children + 1] = gui.Label{
                        classes = {"skillslangs"},
                        textWrap = true,
                        markdown = true,
                        text = ThemeEngine.ResolveTokens(text),
                    }
                end
                element.children = children
            end,
            refreshToken = function(element, token) element:FireEvent("refreshCharacter", token) end,
            setToken = function(element, token) element:FireEvent("refreshCharacter", token) end,
        },
    }
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

--- The perks chosen in the character builder, printed in full.
---
--- Same card grammar as ABILITIES and TRAITS rather than the collapsed rows it
--- used to use, so the three sections read as one system and the rules text is
--- there without a click. A hero has one to three perks, so nothing is gained
--- by hiding them.
--- @return Panel
function TacPanel.Perks()
    return MonsterSheetSection{
        sectionId = "perks",
        title = "PERKS",
        items = function(props)
            if not props:IsHero() then
                return {}
            end

            local out = {}
            local seen = {}
            local levelChoices = props:GetLevelChoices() or {}
            local featTable = dmhub.GetTableVisible(CharacterFeat.tableName)
            -- Only surface perks tied to a LIVE CharacterFeatChoice feature.
            -- Iterating levelChoices directly would keep stale perks left behind
            -- by abandoned careers, whose choice guids linger in levelChoices even
            -- though they no longer map to any active feature. Reuse the categoriser
            -- index the Features section already builds this refresh (shared 1s memo)
            -- rather than recomputing the feature list here.
            local index = FeatureCategoriser.BuildIndexCached(props)
            for _, entry in ipairs(index.features) do
                local feature = entry.feature
                if feature ~= nil and feature.typeName == "CharacterFeatChoice" then
                    for _, guid in ipairs(levelChoices[entry.guid] or {}) do
                        if not seen[guid] then
                            seen[guid] = true
                            local featItem = featTable[guid]
                            if featItem then
                                out[#out+1] = {
                                    guid = guid,
                                    name = featItem.name,
                                    text = StripChoiceInstruction(featItem.description),
                                }
                            end
                        end
                    end
                end
            end
            return out
        end,
        key = function(perk)
            return perk.guid
        end,
        card = function(perk, props, token)
            return MonsterSheetTextCard(perk.name, perk.text, props, false, token)
        end,
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
            element:SetClass("collapsed", not DrawSteelMinion.CanGroupInitiative(m_tokens))
        end,
        gui.Button{
            classes = {"toggle-btn"},
            icon = "icons/icon_app/icon_app_18.png",
            width = TacPanelSizes.VisionBtn.size,
            height = TacPanelSizes.VisionBtn.size,
            press = function(element)
                DrawSteelMinion.GroupInitiativeForTokens(m_tokens)
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
                DrawSteelMinion.SetSquadCaptain(m_tokens, m_selectedSquadId, outer.data.mode == "Make Captain")
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
            --shared with the world-space "Make Captain" button so the two cannot drift.
            local captainInfo = DrawSteelMinion.EvaluateCaptainSelection(tokens)
            local nminions = captainInfo.nminions
            local squadid = captainInfo.squadid

            if captainInfo.show then
                makeCaptainBtn.data.mode = captainInfo.mode
                if captainInfo.mode == "Make Captain" then
                    m_selectedSquadId = squadid
                end
            end

            makeCaptainBtn:SetClass("collapsed", not captainInfo.show)

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
                    text = "ES:",
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
            if TacPanel.IsReadOnly(element) then
                element.text = args.label
                return
            end
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
            classes = {"panel", "cond-remove", "editOnly"},
            press = function(element)
                if TacPanel.IsReadOnly(element) then return end
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
                classes = {"sizeXxs", "cond-setCaster", "editOnly", showSetCaster and "" or "collapsed"},
                icon = "icons/icon_app/icon_app_4.png",
                press = function(element)
                    if TacPanel.IsReadOnly(element) then return end
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
        StringInterpolateGoblinScript(CharacterOngoingEffect.GetDisplayDescription(info), creature),
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

    --sub-aura views share their parent aura's chip; don't show duplicate chips for them.
    local auras = {}
    for _, a in ipairs(creature:GetAuras()) do
        if not a:try_get("isChildAura", false) then
            auras[#auras+1] = a
        end
    end
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
                classes = {"visDot", "editOnly"},
                opacity = 1,
                visible = not token.properties:GetAuraDisplaySetting(aura.name).hide,
                width = 12,
                height = 12,
                press = function(element)
                    if TacPanel.IsReadOnly(element) then return end
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
                classes = {"bordered", "editOnly"},
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
                    if TacPanel.IsReadOnly(element) then return end
                    local liveDisplay = auraInstance:try_get("display")
                    if liveDisplay == nil then
                        return
                    end
                    liveDisplay.bgcolor = element.value.tostring
                    token:UpdateAuras()
                end,
                confirm = function(element)
                    if TacPanel.IsReadOnly(element) then return end
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
                classes = {"panel", "cond-remove", "editOnly"},
                press = function(element)
                    if TacPanel.IsReadOnly(element) then return end
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
                classes = {"bordered", "editOnly"},
                valign = "center",
                halign = "right",
                hmargin = 6,
                width = 20,
                height = 20,
                hasAlpha = true,
                value = token.properties:GetAuraDisplaySetting(capturedAuraName).bgcolor
                    or (token.playerControlled and token.playerColor.tostring or "#AA0000"),
                change = function(element)
                    if TacPanel.IsReadOnly(element) then return end
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
                    if TacPanel.IsReadOnly(element) then return end
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

        --the canonical search field; menu-search keeps only the menu's
        --layout (width/align/margins), the look is the shared searchInput
        --style.
        gui.SearchInput{
            classes = {"searchInput", "menu-search"},
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
                            classes = {"panel", "cond-remove", "editOnly"},
                            press = function(el)
                                if TacPanel.IsReadOnly(el) then return end
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

            local casterClasses = token.properties:GetClassesAndSubClasses()
            local startOfTurnHeroicResource = 0
            for _, classInfo in pairs(casterClasses) do
                local heroicResource = classInfo.class:get_or_add("heroicResourceChecklist", {})
                for _, resourceInfo in pairs(heroicResource) do
                    if string.lower(resourceInfo.name or "") == "start of turn" then
                        startOfTurnHeroicResource = resourceInfo.quantity or 0
                    end
                end
            end

            local evaluatedGain = dmhub.EvalGoblinScript(startOfTurnHeroicResource, token.properties:LookupSymbol(), string.format("Calculating Start of Turn Resources"))

            --EvalGoblinScript reduces the formula as far as it can but returns a string;
            --dice-based gains (e.g. the talent's and troubadour's "1d3") don't reduce to
            --a plain number, so tonumber() yields nil. Fall back to the roll's expected
            --value so the comparison below always has a number. (For 1d3 classes this
            --matches the flat threshold of 2 this panel used before the checklist lookup.)
            startOfTurnHeroicResource = tonumber(evaluatedGain) or dmhub.RollExpectedValue(evaluatedGain)

            if totalCost > startOfTurnHeroicResource then
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

--- Auras, conditions and effects as a bare row inside the stamina block, under
--- the immunity line, with no section header of its own. This replaced the
--- separate AURAS, CONDITIONS, & EFFECTS section, which built the same chips a
--- long way from the creature they applied to.
--- @return Panel
function TacPanel.ConditionsRow()
    local m_token = nil

    --Explicit halign: {iconButton} supplies valign only, and a horizontal-flow
    --child with no alignment centres itself.
    --Built fresh per rebuild, never stashed: the non-monster branch below wipes
    --the row with children = {}, and a child dropped from a children assignment
    --is destroyed a frame later. Held references would be re-added dead on every
    --later refresh -- silently, so one look at a hero would strip the label and
    --the + from every monster for the rest of the session.
    local function MakeAddButton()
        return gui.Label{
            classes = {"cond-add", "editOnly"},
            text = "+",
            hoverCursor = "pressbutton",
            press = function(element)
                if TacPanel.IsReadOnly(element) then return end
                TacPanel.AddConditionMenu{
                    tokens = {m_token},
                    button = element,
                }
            end,
            linger = function(el)
                gui.Tooltip("Add a condition or effect")(el)
            end,
        }
    end

    --Keyed the same way the resistance line reads ("IMMUNITIES: ..."), and
    --left-aligned with it, so the two lines stack as a pair.
    local function MakeLabel()
        return gui.Label{
            classes = {"cond-key"},
            --Classic: heroes have the AURAS, CONDITIONS & EFFECTS section, so
            --this row is the monster's and says only what it holds there.
            text = cond(TacPanel.UseTestPanel(),
                "AURAS, CONDITIONS, & EFFECTS:", "CONDITIONS:"),
        }
    end

    return gui.Panel{
        --"flush" strips the key label's padding so the key starts on the same
        --line as the immunity line above it, which is the column's real left
        --edge.
        classes = {"panel", "cond-chips", "flush", "collapsed"},
        wrap = true,
        width = "100%",
        height = "auto",
        data = { token = nil },

        refreshCharacter = function(element, token)
            m_token = token
            element.data.token = token

            if token == nil or not token.valid or token.properties == nil then
                element:SetClass("collapsed", true)
                element.children = {}
                return
            end

            --Classic: monsters only; heroes get the separate section instead.
            if not TacPanel.UseTestPanel() then
                local isMonster = false
                pcall(function() isMonster = token.properties:IsMonster() end)
                if not isMonster then
                    element:SetClass("collapsed", true)
                    element.children = {}
                    return
                end
            end

            element:SetClass("collapsed", false)

            local creature = token.properties
            local children = {MakeLabel(), MakeAddButton()}

            for condid, cond in pairs(creature:try_get("inflictedConditions", {})) do
                children[#children + 1] = TacPanel.ConditionChip(condid, cond, token)
            end

            local ongoingTable = dmhub.GetTable("characterOngoingEffects")
            for _, entry in ipairs(creature:ActiveOngoingEffects()) do
                local effectInfo = ongoingTable[entry.ongoingEffectid]
                if effectInfo ~= nil and effectInfo.statusEffect then
                    children[#children + 1] = TacPanel.StatusEffectChip(entry, effectInfo, token)
                end
            end

            for key, entry in pairs(creature:try_get("customConditions", {})) do
                children[#children + 1] = TacPanel.CustomConditionChip(key, entry, token)
            end

            for _, auraInfo in ipairs(creature:GetAurasAffecting(token) or {}) do
                --our own auras come back here too, because we emit them.
                if rawget(auraInfo.auraInstance, "casterid") ~= token.charid then
                    children[#children + 1] = TacPanel.AuraChip(auraInfo.auraInstance, token)
                end
            end

            FillAurasEmittingPanels(token, children)

            element.children = children
        end,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        MakeLabel(),
        MakeAddButton(),
    }
end

--- Stub: conditions are rendered inline by TacPanel.ConditionsRow now.
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

            --the canonical search field; look comes from DefaultStyles'
            --searchInput rules, borderBox keeps its hpad 24 inside the width.
            gui.SearchInput {
                placeholderText = "Search...",
                hasFocus = true,
                borderBox = true,
                width = "70%",
                height = 20,
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

-- ============================================================================
-- CLASSIC CHARACTER PANEL
--
-- The panel as it stood before the hero rework, kept whole so the
-- dev:testcharpanel setting can switch back to it. Every function here is a
-- verbatim restore from commit 62c26479 apart from its name: the ones whose
-- reworked counterpart still owns the original name carry a Classic suffix.
--
-- Do NOT extend these. They exist to be switched to, not developed; when the
-- rework comes off its flag this whole block goes with it.
-- ============================================================================

--- Collapse one of the stamina row's action boxes when the token is a monster.
---
--- Monsters fold DMG / STAMINA / HEAL / TEMP into the health bar's hover
--- controls (TacPanel.BarAdjustControls), which is all the room their column
--- beside the portrait has. Heroes keep the boxes.
---
--- Each box has to forward setToken/refreshToken to refreshCharacter itself:
--- the panel tree is driven by setToken, and refreshCharacter only fires where
--- an element re-fires it.
--- @param element Panel
--- @param token CharacterToken
local function SetHeroOnlyBox(element, token)
    local isMonster = false
    if token ~= nil and token.valid and token.properties ~= nil then
        pcall(function() isMonster = token.properties:IsMonster() end)
    end
    element:SetClass("collapsed", isMonster)
end

--- Display the damage / harm box. Heroes only; see SetHeroOnlyBox.
--- @return Panel
function TacPanel.HarmBox()
    return gui.Panel{
        --pure action box (type damage to apply it): hidden entirely in
        --read-only mode.
        classes = {"stamina-box", "harm", "editOnly"},
        refreshCharacter = SetHeroOnlyBox,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
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
                if TacPanel.IsReadOnly(element) then
                    element.textNoNotify = ""
                    return
                end
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

--- Display the heal box. Heroes only; see SetHeroOnlyBox.
--- @return Panel
function TacPanel.HealBox()
    return gui.Panel{
        --pure action box (type healing to apply it): hidden entirely in
        --read-only mode.
        classes = {"stamina-box", "heal", "editOnly"},
        refreshCharacter = SetHeroOnlyBox,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
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
                if TacPanel.IsReadOnly(element) then
                    element.textNoNotify = ""
                    return
                end
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

--- Display the temp stamina box. Heroes only; see SetHeroOnlyBox.
--- @return Panel
function TacPanel.TempStamBox()
    return gui.Panel{
        classes = {"stamina-box", "temp"},
        refreshCharacter = SetHeroOnlyBox,
        refreshToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
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
                if TacPanel.IsReadOnly(element) then
                    if element.data.token ~= nil and element.data.token.valid then
                        element:FireEvent("refreshCharacter", element.data.token)
                    end
                    return
                end
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
                element.editable = not TacPanel.IsReadOnly(element)
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

--- Display the current stamina box. Heroes only; see SetHeroOnlyBox.
--- @return Panel
function TacPanel.StaminaBox()
    return gui.Panel{
        classes = {"stamina-box", "stamina"},
        halign = "center",
        valign = "center",
        data = { token = nil },

        refreshCharacter = function(element, token)
            SetHeroOnlyBox(element, token)
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
                    if TacPanel.IsReadOnly(element) then
                        if token ~= nil and token.valid then
                            element:FireEvent("refreshValue", token)
                        end
                        return
                    end
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
                    --a game update must not stomp on what the user is currently typing.
                    if element.hasFocus then
                        return
                    end
                    element.editable = not TacPanel.IsReadOnly(element)
                    local text = tostring(token.properties:CurrentHitpoints())
                    element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.currentStamina, 3, #text)
                    element.textNoNotify = text
                end,
                defocus = function(element)
                    --catch up on anything we skipped while the field was being edited.
                    local token = element.data.token
                    if token ~= nil and token.valid then
                        element:FireEvent("refreshValue", token)
                    end
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

--- A portrait that only shows for one kind of token.
---
--- Heroes keep the portrait beside the name column; monsters move it down
--- next to the stamina controls. A panel has a single parent, so rather than
--- reparent one portrait on every token change -- fragile, and it fires on
--- every property change -- both positions get their own instance and the
--- inactive one collapses.
--- @param forMonster boolean Which kind of token this instance serves
--- @return Panel
function TacPanel.GatedPortrait(forMonster)
    local portrait = TacPanel.Portrait()

    if forMonster then
        --Monsters stand the three control buttons up as a vertical strip to
        --the RIGHT of the portrait, between it and the stamina block, rather
        --than overlaying them on the image.
        --
        --Set directly rather than through style rules: the buttons panel
        --declares halign, valign and width INLINE, and inline args become
        --selfStyle, which no selector can override.
        --30 reserves the strip: a 26px button (20 glyph + pad 2 + border 1
        --each side) plus a little air off the portrait's edge.
        portrait.selfStyle.rmargin = 30
        --Clearance so the next section's rule reads as a line under the
        --portrait rather than one running into its rounded bottom edge.
        portrait.selfStyle.bmargin = 8

        --Dark plate behind the artwork. Prepended so it renders first, i.e.
        --behind everything else in the frame.
        local backing = gui.Panel{ classes = {"portrait-backing"} }
        local kids = { backing }
        for _, child in ipairs(portrait.children or {}) do
            kids[#kids+1] = child
        end
        portrait.children = kids
        for _, child in ipairs(portrait.children or {}) do
            if child:HasClass("portrait-buttons") then
                child.selfStyle.halign = "right"
                child.selfStyle.valign = "center"
                child.selfStyle.width = "auto"
                --Floating, so this pushes the strip out past the frame's
                --right edge into the room the rmargin above reserved.
                child.selfStyle.rmargin = -28
                child.selfStyle.bmargin = 0
                for _, row in ipairs(child.children or {}) do
                    row.selfStyle.flow = "vertical"
                    for _, btn in ipairs(row.children or {}) do
                        --Quiet the button outlines down to match the DMG box.
                        btn:SetClass("tp-outline-quiet", true)
                        --Air between them. The portrait is a fixed 120px and
                        --three 26px buttons only need 78, so the spacing is
                        --free -- and these are small targets. Set here because
                        --the wrapper declares vmargin inline.
                        btn.selfStyle.vmargin = 4
                    end
                end
            end
        end
    end

    return gui.Panel{
        classes = {"container"},
        width = "auto",
        height = "auto",
        flow = "horizontal",
        valign = "top",
        halign = "left",
        refreshCharacter = function(element, token)
            local isMonster = false
            if token ~= nil and token.valid and token.properties ~= nil then
                pcall(function() isMonster = token.properties:IsMonster() end)
            end
            element:SetClass("collapsed", isMonster ~= forMonster)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,
        portrait,
    }
end

--- Display the summary section with portrait, class, levels, etc.
--- @return Panel
function TacPanel.SummaryClassic()

    return gui.Panel{
        classes = {"tacpanel"},
        --Monsters tighten the strip's padding: half off the bottom (that space
        --moves to the far side of the rule, see the portrait row in
        --CharacterPanel.SingleCharacterDisplaySidePanel) and most off the top,
        --which was leaving a wide gap between the panel's title bar and the
        --token name. tacpanel's vpad is 8.
        refreshCharacter = function(element, token)
            local isMonster = false
            if token ~= nil and token.valid and token.properties ~= nil then
                pcall(function() isMonster = token.properties:IsMonster() end)
            end
            element.selfStyle.bpad = cond(isMonster, 4, 8)
            element.selfStyle.tpad = cond(isMonster, 2, 8)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        gui.Panel{
            classes = {"container"},
            flow = "horizontal",

            --Heroes only: monsters show their portrait beside the stamina
            --controls instead, so the identity strip can run full width.
            TacPanel.GatedPortrait(false),

            gui.Panel{
                classes = {"summary-info"},
                width = TacPanelSizes.Panels.summaryNames,
                flow = "horizontal",

                --MONSTERS get the book's full-width two-column header strip;
                --the portrait moves down beside the stamina controls (see
                --CharacterPanel.SingleCharacterDisplaySidePanel). HEROES keep
                --the original narrow name column beside their portrait.
                refreshCharacter = function(element, token)
                    local isMonster = false
                    pcall(function() isMonster = token.properties:IsMonster() end)
                    if isMonster then
                        element.selfStyle.width = "100%"
                        --summary-info carries pad = 6; drop the top half of it
                        --so the name sits closer to the panel's title bar.
                        element.selfStyle.tpad = 0
                    else
                        element.selfStyle.width = TacPanelSizes.Panels.summaryNames
                        element.selfStyle.tpad = 6
                    end
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,

                gui.Panel{
                classes = {"ident-left"},
                --Full width for heroes, who have no right column.
                refreshCharacter = function(element, token)
                    local isMonster = false
                    pcall(function() isMonster = token.properties:IsMonster() end)
                    if isMonster then
                        --54 + 44, not 100: summary-info carries pad = 6 with
                        --no borderBox, so its children's percentages resolve
                        --against a box 12px wider than the visible panel.
                        element.selfStyle.width = "54%"
                    else
                        element.selfStyle.width = "100%"
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

                -- Monster type, e.g. ZOMBIE. Sits directly under the token
                -- name and above the keywords, so the identity block reads
                -- name -> what it is -> what it has -> what it costs.
                --
                -- A separate label rather than moving the "Class" slot up:
                -- that slot renders the CLASS for heroes, and reordering it
                -- would rearrange the hero panel too. This one collapses for
                -- heroes, and the class slot collapses for monsters.
                gui.Label{
                    classes = {"summary-info", "class"},
                    refreshCharacter = function(element, token)
                        local isMonster = false
                        pcall(function() isMonster = token.properties:IsMonster() end)
                        if not isMonster then
                            element:SetClass("collapsed", true)
                            element.text = ""
                            return
                        end
                        element:SetClass("collapsed", false)
                        local text = string.upper(token.properties:try_get("monster_type", "Monster"))
                        element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.monsterType, 14, #text)
                        element.text = text
                    end,
                    setToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                },

                -- Monster keywords, e.g. "Soulless, Undead". Left column,
                -- under the type, so the identity block reads top to bottom as
                -- name -> what it is -> what it has, with the right column
                -- carrying the numbers instead of a second stack of nouns.
                gui.Label{
                    classes = {"summary-info", "monster-keywords"},
                    refreshCharacter = function(element, token)
                        --This column is shared with heroes now that the label
                        --has moved out of the monster-only right column, so it
                        --collapses rather than rendering an empty line that
                        --would push the hero's own rows down.
                        local isMonster = false
                        pcall(function() isMonster = token.properties:IsMonster() end)
                        element:SetClass("collapsed", not isMonster)
                        if not isMonster then
                            element.text = ""
                            return
                        end
                        local keywords = token.properties.keywords or {}
                        local sorted = {}
                        for k, _ in pairs(keywords) do
                            sorted[#sorted+1] = ActivatedAbility.CanonicalKeyword(k)
                        end
                        table.sort(sorted)
                        local text = string.join(sorted, ", ")
                        --Fixed at the right column's size rather than fitted:
                        --keywords and the level/size/free-strike lines are the
                        --same order of information, and fitting made this line
                        --shrink with its own length so the two halves of the
                        --strip almost never matched.
                        element.selfStyle.fontSize = TacPanelSizes.Fonts.identRight
                        element.text = text
                    end,
                },

                -- A minion's "With Captain" bonus, under the type block. It is
                -- identity, not a trait: it says what this creature is worth
                -- while its captain lives. Accented when the squad actually
                -- HAS a captain (FillTemporalActiveModifiers in
                -- MCDMMonster.lua), muted when it is merely possible.
                gui.Label{
                    classes = {"summary-info", "ident-captain"},
                    refreshCharacter = function(element, token)
                        local text = nil
                        pcall(function() text = WithCaptainText(token.properties) end)
                        if text == nil then
                            element:SetClass("collapsed", true)
                            element.text = ""
                            return
                        end
                        element:SetClass("collapsed", false)
                        local squad = token.properties:try_get("_tmp_minionSquad")
                        element:SetClass("captain-live", squad ~= nil and squad.hasCaptain == true)
                        element.text = string.format("With Captain: %s", text)
                    end,
                    refreshToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                    setToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                },

                -- Level. Monsters carry theirs in the strip's right column
                -- alongside EV, so this collapses for them.
                gui.Label{
                    classes = {"summary-info", "level"},
                    refreshCharacter = function(element, token)
                        local isMonster = false
                        pcall(function() isMonster = token.properties:IsMonster() end)
                        if isMonster then
                            element:SetClass("collapsed", true)
                            element.text = ""
                            return
                        end
                        element:SetClass("collapsed", false)
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
                        element.selfStyle.fontSize = _fitFontSize(TacPanelSizes.Fonts.charLevel, 12, #text)
                        element.text = text
                    end,
                    setToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,
                },

                -- Class. Monsters show their type in the label above instead,
                -- so this collapses for them rather than repeating it here.
                gui.Label{
                    classes = {"summary-info", "class"},
                    refreshCharacter = function(element, token)
                        local isMonster = false
                        pcall(function() isMonster = token.properties:IsMonster() end)
                        if isMonster then
                            element:SetClass("collapsed", true)
                            element.text = ""
                            return
                        end
                        element:SetClass("collapsed", false)
                        local text = ""
                        if token.properties:IsHero() then
                            local classItem = token.properties:GetClass()
                            if classItem ~= nil then
                                text = string.upper(classItem.name)
                            end
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

                --RIGHT column of the monster identity strip: EV on the name's
                --line, level/role on the type's. Collapsed for heroes, who
                --keep everything in the single left column.
                gui.Panel{
                    classes = {"ident-right"},
                    refreshCharacter = function(element, token)
                        local isMonster = false
                        pcall(function() isMonster = token.properties:IsMonster() end)
                        element:SetClass("collapsed", not isMonster)
                    end,
                    setToken = function(element, token)
                        element:FireEvent("refreshCharacter", token)
                    end,

                    gui.Label{
                        classes = {"ident-right", "ident-ev"},
                        refreshCharacter = function(element, token)
                            local isMonster = false
                            pcall(function() isMonster = token.properties:IsMonster() end)
                            if not isMonster then
                                element.text = ""
                                return
                            end
                            element.text = string.format("EV %d", token.properties:EV())
                        end,
                        setToken = function(element, token)
                            element:FireEvent("refreshCharacter", token)
                        end,
                    },

                    gui.Label{
                        classes = {"ident-right", "ident-level"},
                        refreshCharacter = function(element, token)
                            local isMonster = false
                            pcall(function() isMonster = token.properties:IsMonster() end)
                            if not isMonster then
                                element.text = ""
                                return
                            end
                            local level = token.properties:CharacterLevel()
                            local role = token.properties:try_get("role", "")
                            local text
                            if role ~= "" then
                                text = string.format("LEVEL %d %s", level, string.upper(role))
                            else
                                text = string.format("LEVEL %d", level)
                            end
                            --No per-label sizing: the whole right column now
                            --shares one size from the "ident-right" rule, and
                            --shrinking just this line to fit was what made the
                            --column read as a hierarchy it does not have.
                            element.text = text
                        end,
                        setToken = function(element, token)
                            element:FireEvent("refreshCharacter", token)
                        end,
                    },

                    -- Size, at the foot of the strip. It used to sit down in
                    -- STATISTICS with the movement numbers; up here it leaves
                    -- that block as just the movement modes.
                    gui.Label{
                        classes = {"ident-right", "ident-size"},
                        refreshCharacter = function(element, token)
                            local isMonster = false
                            pcall(function() isMonster = token.properties:IsMonster() end)
                            if not isMonster then
                                element.text = ""
                                return
                            end
                            local size = nil
                            pcall(function() size = token.properties:SizeDescription() end)
                            if size == nil or size == "" then
                                element.text = ""
                                return
                            end
                            element.text = string.format("SIZE %s", tostring(size))
                        end,
                        setToken = function(element, token)
                            element:FireEvent("refreshCharacter", token)
                        end,
                    },

                    -- Free strike. It sat in STATISTICS as a stat box, but it
                    -- is a fixed property of the creature rather than a number
                    -- that moves in play, so it belongs with size and role.
                    gui.Label{
                        classes = {"ident-right", "ident-freestrike"},
                        refreshCharacter = function(element, token)
                            local isMonster = false
                            pcall(function() isMonster = token.properties:IsMonster() end)
                            if not isMonster then
                                element.text = ""
                                return
                            end
                            local freeStrike = nil
                            pcall(function() freeStrike = token.properties:OpportunityAttack() end)
                            if freeStrike == nil then
                                element.text = ""
                                return
                            end
                            element.text = string.format("FREE STRIKE %s", tostring(freeStrike))
                        end,
                        setToken = function(element, token)
                            element:FireEvent("refreshCharacter", token)
                        end,
                    },
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
            classes = {"sizeM", "collapsed", "editOnly"},
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
                if TacPanel.IsReadOnly(element) then return end
                Commands.rollinitiative()
            end,
        },

    }
end

--- Display the stamina controls
--- @return Panel
function TacPanel.StaminaClassic()
    return TacPanel.CollapsiblePanel{
        title = "STAMINA",
        altBg = false,

        --Monsters drop the section header entirely: the stamina box now
        --carries its own STAMINA label like the boxes beside it, and losing
        --the header moves the whole block up.
        refreshCharacter = function(element, token)
            local isMonster = false
            if token ~= nil and token.valid and token.properties ~= nil then
                pcall(function() isMonster = token.properties:IsMonster() end)
            end
            local titleBar = element.children[1]
            if titleBar ~= nil then
                titleBar:SetClass("collapsed", isMonster)
            end
            element.selfStyle.tpad = cond(isMonster, 0, 8)

            --Monsters drop this section's own bottom rule. It is only as wide
            --as the stamina column, so it stopped at the portrait and cut
            --across the middle of the block -- and the row around it already
            --draws a full-width one at the block's bottom edge. Heroes have no
            --portrait beside them, so theirs still spans and stays.
            --
            --A class, not a selfStyle write: assigning a border table to
            --selfStyle at runtime does not take.
            element:SetClass("no-rule", isMonster)
        end,
        setToken = function(element, token)
            element:FireEvent("refreshCharacter", token)
        end,

        --HEROES keep the full row: DMG, STAMINA, HEAL, RECOVERIES, TEMP.
        --MONSTERS collapse all of it -- the three action boxes are their bar's
        --hover controls instead (see TacPanel.BarAdjustControls), and they have
        --no recoveries -- which leaves the row empty and the column beside the
        --portrait free for the bar. Each box gates itself; see SetHeroOnlyBox.
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
        --Monsters only; collapses itself for heroes, who keep the
        --AURAS, CONDITIONS & EFFECTS section instead. Renamed since this was
        --written -- it gates itself on the flag.
        TacPanel.ConditionsRow(),
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
    --A Title chip is named after the title, so its popup leads with the title's
    --own description and then names the benefit it granted (report GETSJ9FB).
    if entry.subName ~= nil and entry.subName ~= "" then
        local parts = {}
        local originDesc = nil
        pcall(function() originDesc = entry.origin:try_get("description") end)
        if originDesc ~= nil and originDesc ~= "" then parts[#parts+1] = originDesc end
        parts[#parts+1] = string.format("**%s**", entry.subName)
        if desc ~= nil and desc ~= "" then parts[#parts+1] = desc end
        return table.concat(parts, "\n\n")
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
    --The Title bucket's chips ARE the origin names, so appending the origin
    --here would just repeat the single title back in its own header.
    if group.bucket ~= nil and group.bucket.id == "title" then
        return group.bucket.name
    end
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
--- @param onOpen function|nil called when the popup opens (lets the owning
---        section lock its filter so a later title-bar search change does not
---        rebuild the list and tear this popup down)
--- @return Panel
-- A feature chip. Built to be REUSED across refreshes rather than rebuilt: the
-- acting token, description source, filter haystack, and label are all kept in
-- `data` and refreshed by the `update` event, so a single chip instance can be
-- retargeted to a new entry (or a new selected token) without reallocation.
function TacPanel.FeatureChip(token, name, descFn, onOpen)
    local chip
    local nameLabel
    nameLabel = gui.Label{
        classes = {"label", "cond-name"},
        text = name,
    }
    chip = gui.Panel{
        classes = {"panel", "cond-chip", "feature-chip"},
        data = {
            token = token,
            name = name,
            descFn = descFn,
            onOpen = onOpen,
            -- Pre-lowered filter haystack so applyFilter can use the hot-path
            -- Search.MatchesLoweredText without re-lowering on every keystroke.
            searchLower = string.lower(name or ""),
        },
        -- Retarget a reused chip in place: refresh the acting token, description
        -- source, filter haystack, and (only if it changed) the label text.
        update = function(element, tok, newName, newDescFn, newSearchText)
            element.data.token = tok
            element.data.descFn = newDescFn
            element.data.searchLower = string.lower(newSearchText or newName or "")
            if newName ~= element.data.name then
                element.data.name = newName
                nameLabel.text = newName or ""
            end
        end,
        click = function(element)
            local tok = element.data.token
            if tok == nil then return end
            if element.data.onOpen ~= nil then element.data.onOpen() end
            local capturedId = tok.id
            local displayName = element.data.name
            local descFnNow = element.data.descFn
            local desc = (descFnNow and descFnNow()) or "*No description.*"
            --the description popup is pure viewing, but the sheet link
            --leads to the fully editable character sheet: omit it in
            --read-only mode.
            local sheetLink = nil
            if not TacPanel.IsReadOnly(element) then
                sheetLink = gui.Label{
                    width = "auto", height = "auto",
                    halign = "right", tmargin = 6,
                    bold = true, fontSize = 12, color = "@accent",
                    text = "Open on sheet",
                    click = function(linkEl)
                        chip.popup = nil
                        FeatureCategoriser.OpenSheetAtFeaturesTab(capturedId, displayName)
                    end,
                }
            end
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
                    text = displayName,
                },
                gui.Label{
                    width = "100%", height = "auto",
                    markdown = true, fontSize = 12, color = "@fg",
                    tmargin = 4,
                    text = desc,
                },
                sheetLink,
            }
        end,
        nameLabel,
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

    --Panel-reuse caches. Building gui panels is expensive, so the Features list
    --keeps its group/level/chip panels alive across refreshes, updates them in
    --place, and only reassigns children when the ordered membership changes.
    local m_groupPanels = {}       -- bucketId -> group panel (reused)
    local m_withCaptainChip = nil  -- synthetic "With Captain" chip (reused)
    local m_withCaptainWrap = nil  -- its chip-wrap container (reused)
    local m_currentOrder = {}      -- bucket ids currently shown, in order
    local m_lastTotal = 0          -- feature count, for the count label

    --Opening a feature popup "locks" a title-bar-driven filter in place: we
    --promote it to a user-owned filter so applyGlobalQuery stops touching it.
    --Without this, clearing/changing the title-bar search rebuilds the list and
    --tears down the popup the moment the user clicks a chip. The filter box
    --still shows the term + the clear X, so it remains clearable by hand.
    local function lockFilterOnOpen()
        m_filterFromGlobal = false
    end

    --Key a feature entry for reuse. The index dedupes by bucket|name|subName, so
    --that pair is a stable, unique chip key within a single group/level (two
    --benefits of one title share a name and differ only in subName).
    local function entryKey(e)
        return string.format("%s|%s", e.name or "", e.subName or "")
    end

    --Generic keyed child reconciliation (mirrors DTProjectEditor._reconcile-
    --ProgressItemsList / DTHelpers.SyncArrays): reuse panels from `cache` by key,
    --build only the genuinely-new ones, update every panel in place, reorder to
    --match `items`, and reassign container.children ONLY when the ordered set
    --actually changed -- so a no-op refresh does no relayout. Returns the new
    --cache (dropping any panels whose keys are gone).
    local function reconcileChildren(container, cache, items, keyOf, buildFn, updateFn)
        local newCache = {}
        local children = {}
        for _,item in ipairs(items) do
            local key = keyOf(item)
            local panel = cache[key] or buildFn(item, key)
            updateFn(panel, item, key)
            newCache[key] = panel
            children[#children+1] = panel
        end
        local changed = #children ~= #container.children
        if not changed then
            for i = 1, #children do
                if container.children[i] ~= children[i] then
                    changed = true
                    break
                end
            end
        end
        if changed then
            container.children = children
        end
        return newCache
    end

    --An empty chip-wrap body that owns a name-keyed chip cache in its data, so its
    --chips persist across refreshes (syncChipBody reconciles, filterChipBody hides).
    local function buildChipBody()
        return gui.Panel{
            classes = {"panel", "cond-chips"},
            wrap = true,
            lmargin = 6,
            data = { chipCache = {}, visibleCount = 0 },
        }
    end

    --Reconcile a chip body's chips to `entries`, reusing chips by name.
    local function syncChipBody(body, entries)
        body.data.chipCache = reconcileChildren(
            body, body.data.chipCache, entries,
            entryKey,
            function(e)
                return TacPanel.FeatureChip(m_token, e.name or "Feature", nil, lockFilterOnOpen)
            end,
            function(chip, e)
                local captured = e
                chip:FireEvent("update", m_token, e.name or "Feature",
                    function() return FeatureTacDescription(captured) end, e.searchText)
            end)
    end

    --Show/hide a chip body's chips against a (normalised) needle -- no rebuild, just
    --collapse toggles. Empty needle shows all. Returns and stashes the visible count.
    local function filterChipBody(body, needle)
        local visible = 0
        for _,chip in ipairs(body.children) do
            local match = needle == "" or Search.MatchesLoweredText(chip.data.searchLower, needle)
            chip:SetClass("collapsed", not match)
            if match then visible = visible + 1 end
        end
        body.data.visibleCount = visible
        return visible
    end

    --A flat origin group: header (arrow + "Bucket - Origin (N)") over a chip body.
    --Expansion toggles in place via m_expanded[bid]; while filtering the group is
    --forced open + locked, and hidden entirely when nothing matches.
    local function buildFlatGroupShell(bid)
        local body = buildChipBody()
        --halign is explicit on both children: a horizontal-flow child with no
        --alignment centers itself in the run, which only shows outside the dock
        --(the icon rail's panel windows) where no ancestor supplies one.
        local arrow = gui.CollapseArrow{ width = 10, height = 10, valign = "center", halign = "left", hmargin = 4 }
        local titleLabel = gui.Label{
            width = "auto", height = "auto", valign = "center", halign = "left",
            fontSize = 12, bold = true, color = "@fg", text = "",
        }
        local header = gui.Panel{
            width = "100%", height = "auto", flow = "horizontal", valign = "center", vmargin = 2,
            data = { locked = false },
            press = function(element)
                if element.data.locked then return end
                local now = not (m_expanded[bid] == true)
                if now then m_expanded[bid] = true else m_expanded[bid] = nil end
                body:SetClass("collapsed", not now)
                arrow:SetClass("collapseSet", not now)
            end,
            arrow,
            titleLabel,
        }
        return gui.Panel{
            width = "100%", height = "auto", flow = "vertical",
            data = { bid = bid, body = body, arrow = arrow, header = header, titleLabel = titleLabel, visibleCount = 0 },
            syncGroup = function(element, grp)
                element.data.titleLabel.text = string.format("%s (%d)", FeatureGroupHeaderText(grp), #grp.items)
                syncChipBody(element.data.body, grp.items)
            end,
            filterGroup = function(element, needle, filtering)
                local visible = filterChipBody(element.data.body, needle)
                if filtering then
                    element.data.header.data.locked = true
                    element.data.body:SetClass("collapsed", false)
                    element.data.arrow:SetClass("collapseSet", false)
                    element:SetClass("collapsed", visible == 0)
                else
                    element.data.header.data.locked = false
                    element:SetClass("collapsed", false)
                    local expanded = m_expanded[element.data.bid] == true
                    element.data.body:SetClass("collapsed", not expanded)
                    element.data.arrow:SetClass("collapseSet", not expanded)
                end
                element.data.visibleCount = visible
            end,
            header,
            body,
        }
    end

    --A collapsible "Level N (count)" sub-group (Class bucket only). Chips reused by
    --name; toggles in place via m_expandedLevels[lvl]; forced open while filtering.
    local function buildLevelShell(lvl)
        local body = buildChipBody()
        local arrow = gui.CollapseArrow{ width = 9, height = 9, valign = "center", halign = "left", hmargin = 4 }
        local titleLabel = gui.Label{
            width = "auto", height = "auto", valign = "center", halign = "left",
            fontSize = 11, color = "@fgMuted", text = "",
        }
        local header = gui.Panel{
            width = "100%", height = "auto", flow = "horizontal", valign = "center", vmargin = 1,
            data = { locked = false },
            press = function(element)
                if element.data.locked then return end
                local now = not (m_expandedLevels[lvl] == true)
                if now then m_expandedLevels[lvl] = true else m_expandedLevels[lvl] = nil end
                body:SetClass("collapsed", not now)
                arrow:SetClass("collapseSet", not now)
            end,
            arrow,
            titleLabel,
        }
        return gui.Panel{
            width = "100%-8", halign = "right", height = "auto", flow = "vertical",
            data = { lvl = lvl, body = body, arrow = arrow, header = header, titleLabel = titleLabel, visibleCount = 0 },
            syncLevel = function(element, entries)
                element.data.titleLabel.text = string.format("%s (%d)",
                    cond(lvl > 0, string.format("Level %d", lvl), "Other"), #entries)
                syncChipBody(element.data.body, entries)
            end,
            filterLevel = function(element, needle, filtering)
                local visible = filterChipBody(element.data.body, needle)
                if filtering then
                    element.data.header.data.locked = true
                    element.data.body:SetClass("collapsed", false)
                    element.data.arrow:SetClass("collapseSet", false)
                    element:SetClass("collapsed", visible == 0)
                else
                    element.data.header.data.locked = false
                    element:SetClass("collapsed", false)
                    local expanded = m_expandedLevels[element.data.lvl] == true
                    element.data.body:SetClass("collapsed", not expanded)
                    element.data.arrow:SetClass("collapseSet", not expanded)
                end
                element.data.visibleCount = visible
            end,
            header,
            body,
        }
    end

    --The Class bucket group: header over a container of by-level sub-groups. Level
    --panels are reused by level number across refreshes.
    local function buildClassGroupShell(bid)
        local levels = gui.Panel{
            width = "100%", height = "auto", flow = "vertical", lmargin = 4,
            data = { levelCache = {} },
        }
        local arrow = gui.CollapseArrow{ width = 10, height = 10, valign = "center", halign = "left", hmargin = 4 }
        local titleLabel = gui.Label{
            width = "auto", height = "auto", valign = "center", halign = "left",
            fontSize = 12, bold = true, color = "@fg", text = "",
        }
        local header = gui.Panel{
            width = "100%", height = "auto", flow = "horizontal", valign = "center", vmargin = 2,
            data = { locked = false },
            press = function(element)
                if element.data.locked then return end
                local now = not (m_expanded[bid] == true)
                if now then m_expanded[bid] = true else m_expanded[bid] = nil end
                levels:SetClass("collapsed", not now)
                arrow:SetClass("collapseSet", not now)
            end,
            arrow,
            titleLabel,
        }
        return gui.Panel{
            width = "100%", height = "auto", flow = "vertical",
            data = { bid = bid, body = levels, arrow = arrow, header = header, titleLabel = titleLabel, visibleCount = 0 },
            syncGroup = function(element, grp)
                element.data.titleLabel.text = string.format("%s (%d)", FeatureGroupHeaderText(grp), #grp.items)
                --Sub-group the items by level (ascending; "Other" = 0).
                local byLevel, levelsSeen = {}, {}
                for _,e in ipairs(grp.items) do
                    local lvl = e.level or 0
                    if byLevel[lvl] == nil then
                        byLevel[lvl] = {}
                        levelsSeen[#levelsSeen+1] = lvl
                    end
                    local t = byLevel[lvl]
                    t[#t+1] = e
                end
                table.sort(levelsSeen)
                local lc = element.data.body
                lc.data.levelCache = reconcileChildren(
                    lc, lc.data.levelCache, levelsSeen,
                    function(lvl) return lvl end,
                    function(lvl) return buildLevelShell(lvl) end,
                    function(panel, lvl) panel:FireEvent("syncLevel", byLevel[lvl]) end)
            end,
            filterGroup = function(element, needle, filtering)
                local lc = element.data.body
                local visible = 0
                for _,levelPanel in ipairs(lc.children) do
                    levelPanel:FireEvent("filterLevel", needle, filtering)
                    visible = visible + (levelPanel.data.visibleCount or 0)
                end
                if filtering then
                    element.data.header.data.locked = true
                    lc:SetClass("collapsed", false)
                    element.data.arrow:SetClass("collapseSet", false)
                    element:SetClass("collapsed", visible == 0)
                else
                    element.data.header.data.locked = false
                    element:SetClass("collapsed", false)
                    local expanded = m_expanded[element.data.bid] == true
                    lc:SetClass("collapsed", not expanded)
                    element.data.arrow:SetClass("collapseSet", not expanded)
                end
                element.data.visibleCount = visible
            end,
            header,
            levels,
        }
    end

    --Whether the curated index (or the With-Captain synthetic) matches a needle.
    --Used to decide whether a title-bar search should drive this section's
    --filter at all (it only responds to queries it actually contains).
    local function indexHasMatch(creature, index, needle)
        for _,e in ipairs(index.features) do
            if Search.MatchesText(e.searchText or e.name or "", needle) then return true end
        end
        local captainText = WithCaptainText(creature)
        if captainText ~= nil then
            if Search.MatchesText("With Captain", needle)
                or Search.MatchesText(captainText, needle) then return true end
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

    --Apply the active filter to the ALREADY-BUILT group/chip panels by toggling
    --collapsed classes -- no index build, no panel allocation, no children churn.
    --This is the hot path: it runs on every filter keystroke.
    local function applyFilter()
        if section == nil then return end
        local token = m_token
        if token == nil or not token.valid or token.properties == nil then
            section:SetClass("collapsed", true)
            return
        end
        local filtering = m_filter ~= ""
        local needle = Search.Normalize(m_filter)
        local shown = 0

        --Minion "With Captain": a standalone chip outside the grouped list.
        if m_withCaptainWrap ~= nil then
            if m_withCaptainChip ~= nil and m_withCaptainChip.data ~= nil and m_withCaptainChip.data.active then
                local match = not filtering
                    or Search.MatchesLoweredText(m_withCaptainChip.data.searchLower, needle)
                m_withCaptainChip:SetClass("collapsed", not match)
                m_withCaptainWrap:SetClass("collapsed", not match)
                if match then shown = shown + 1 end
            else
                m_withCaptainWrap:SetClass("collapsed", true)
            end
        end

        for _,bid in ipairs(m_currentOrder) do
            local gp = m_groupPanels[bid]
            if gp ~= nil then
                gp:FireEvent("filterGroup", needle, filtering)
                shown = shown + (gp.data.visibleCount or 0)
            end
        end

        if shown == 0 then
            if filtering then
                countLabel.text = string.format("No matches in %d features", m_lastTotal)
                countLabel:SetClass("collapsed", false)
                section:SetClass("collapsed", false)
                return
            end
            section:SetClass("collapsed", true)
            return
        end

        section:SetClass("collapsed", false)
        if filtering then
            countLabel.text = string.format("Showing %d of %d features", shown, m_lastTotal)
        else
            countLabel.text = string.format("%d features", m_lastTotal)
        end
        countLabel:SetClass("collapsed", false)
    end

    --Reconcile the groups container from the curated index: reuse group/level/chip
    --panels, update them in place, and reassign children ONLY when the ordered set
    --changed. Runs on token switch / token-data change (NOT on filter keystrokes),
    --and finishes by applying the active filter to the refreshed panels.
    local function reconcile()
        if section == nil then return end
        local token = m_token
        if token == nil or not token.valid or token.properties == nil then
            section:SetClass("collapsed", true)
            return
        end
        local creature = token.properties
        local index = FeatureCategoriser.BuildTacIndexCached(creature)
        m_lastTotal = index.total

        local children = {}

        --Minion "With Captain": a standalone chip (not a characterFeatures entry,
        --so the categoriser never sees it). Built once, then reused.
        --
        local captainText = WithCaptainText(creature)
        if captainText ~= nil then
            -- Rebuild if the cached chip was destroyed/orphaned by a prior
            -- children reassignment: the engine clears .data on a dead panel, so
            -- a non-nil handle with nil .data would crash the .active write below.
            if m_withCaptainChip == nil or m_withCaptainChip.data == nil then
                m_withCaptainChip = TacPanel.FeatureChip(token, "With Captain",
                    function() return captainText end, lockFilterOnOpen)
                m_withCaptainWrap = gui.Panel{
                    classes = {"panel", "cond-chips"},
                    wrap = true,
                    lmargin = 6,
                    m_withCaptainChip,
                }
            end
            m_withCaptainChip:FireEvent("update", token, "With Captain",
                function() return captainText end, "With Captain " .. captainText)

            --The bonus only applies while the squad actually has a captain --
            --see FillTemporalActiveModifiers in MCDMMonster.lua. Mark the chip
            --so the panel says whether it is live rather than merely possible.
            local squad = creature:try_get("_tmp_minionSquad")
            local captainLive = squad ~= nil and squad.hasCaptain == true
            m_withCaptainChip:SetClass("captain-live", captainLive)

            m_withCaptainChip.data.active = true
            children[#children+1] = m_withCaptainWrap
        elseif m_withCaptainChip ~= nil then
            --The wrap is not in the new children set, so the children
            --reassignment below orphans it and the engine destroys it. Drop the
            --cached references (cache handoff, same as the group-panel cache
            --below) so the chip is rebuilt fresh if the captain returns.
            --Keeping the destroyed panel cached made the next reconcile (and
            --applyFilter) index nil .data and crash.
            m_withCaptainChip = nil
            m_withCaptainWrap = nil
        end

        --Group panels, reused by bucket id, in the index's bucket order.
        m_currentOrder = {}
        for _,bid in ipairs(index.order) do
            local gp = m_groupPanels[bid]
            if gp == nil then
                if bid == "class" then
                    gp = buildClassGroupShell(bid)
                else
                    gp = buildFlatGroupShell(bid)
                end
                m_groupPanels[bid] = gp
            end
            gp:FireEvent("syncGroup", index.groups[bid])
            children[#children+1] = gp
            m_currentOrder[#m_currentOrder+1] = bid
        end

        --Drop cached group panels no longer present (cache handoff).
        local present = {}
        for _,bid in ipairs(m_currentOrder) do present[bid] = true end
        for bid in pairs(m_groupPanels) do
            if not present[bid] then m_groupPanels[bid] = nil end
        end

        --Only reassign children when the ordered membership actually changed.
        local changed = #children ~= #groupsContainer.children
        if not changed then
            for i = 1, #children do
                if groupsContainer.children[i] ~= children[i] then
                    changed = true
                    break
                end
            end
        end
        if changed then
            groupsContainer.children = children
        end

        applyFilter()
    end

    --Set the filter (used by the title-bar search path). When it populates the
    --filter, ensure the section is open so the filtered result is visible even
    --if the user had it collapsed -- otherwise the filtering would be silent.
    local function setFilter(text, fromGlobal)
        m_filter = text or ""
        m_filterFromGlobal = fromGlobal == true
        syncFilterInput()
        applyFilter()
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
            local index = FeatureCategoriser.BuildTacIndexCached(token.properties)
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
        bgimage = "phosphor/x-bold.png",
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
            applyFilter()
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
            applyFilter()
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
            --Monsters do not show FEATURES at all: their traits, abilities,
            --triggers and villain actions each have their own section, and a
            --minion's With Captain bonus now rides along in TRAITS. Skipping
            --the reconcile also skips building chips nobody will see.
            local isMonster = false
            if token ~= nil and token.valid and token.properties ~= nil then
                pcall(function() isMonster = token.properties:IsMonster() end)
            end
            if isMonster then
                element:SetClass("collapsed", true)
                m_token = token
                return
            end

            m_token = token
            reconcile()
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

function TacPanel.Conditions()
    local m_token = nil

    -- Add button first
    --Explicit halign: {iconButton} supplies valign only, and a horizontal-flow
    --child with no alignment centers itself -- visible outside the dock (the
    --icon rail's panel windows). This is the row's first child, so without it
    --every chip after it is displaced too.
    --Built fresh per rebuild, never stashed: the monster and nil-token branches
    --below wipe the row with setContent{}, and a child dropped from a children
    --assignment is destroyed a frame later. A held reference would be re-added
    --dead on every later refresh -- silently, so the + would vanish for good
    --the first time the user clicked a monster and came back.
    local function MakeAddButton()
        return gui.Button{
            classes = {"addButton", "editOnly"} ,
            halign = "left",
            press = function(element)
                if TacPanel.IsReadOnly(element) then return end
                TacPanel.AddConditionMenu{
                    tokens = {m_token},
                    button = element,
                }
            end,
            linger = function(el)
                gui.Tooltip("Add a condition or effect")(el)
            end,
        }
    end

    return TacPanel.CollapsiblePanel{
        sectionId = "conditions",
        classes = {"collapsed"},
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

            --Monsters carry their conditions inline under the immunity line
            --instead (TacPanel.MonsterConditions), so this whole section goes.
            local isMonster = false
            pcall(function() isMonster = token.properties:IsMonster() end)
            element:SetClass("collapsed", isMonster)
            if isMonster then
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
            local children = {MakeAddButton()}

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

            MakeAddButton(),
        },

    }
end

--- Display the Perks panel (heroes only)
--- @return Panel
function TacPanel.PerksClassic()
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
            -- Only surface perks tied to a LIVE CharacterFeatChoice feature.
            -- Iterating levelChoices directly would keep stale perks left behind
            -- by abandoned careers, whose choice guids linger in levelChoices even
            -- though they no longer map to any active feature. Reuse the categoriser
            -- index the Features section already builds this refresh (shared 1s memo)
            -- rather than recomputing the feature list here.
            local index = FeatureCategoriser.BuildIndexCached(creature)
            for _,entry in ipairs(index.features) do
                local feature = entry.feature
                if feature ~= nil and feature.typeName == "CharacterFeatChoice" then
                    for _,guid in ipairs(levelChoices[entry.guid] or {}) do
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

--- Display the heroic resources info
--- @return Panel
function TacPanel.HeroicResourcesClassic()

    --Only the displays this section had before the rework. Hero tokens and
    --surges sit beside the portrait on the classic panel and recoveries is a
    --stamina box, so taking every registered display would double them up.
    local displays = {}
    for id, entry in pairs(g_heroicResourceDisplays) do
        if entry.classic then
            local pane = entry.create()
            pane.data.ord = entry.ord or 0
            displays[#displays + 1] = pane
        end
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

-- ======================= END CLASSIC CHARACTER PANEL ========================

--The reworked order: RESOURCES sits between the stats and the abilities --
--what you have to spend is read right before what you would spend it on -- and
--FEATURES and the conditions section are gone (their content moved into TRAITS
--and the vitals row).
local TACPANEL_DEFAULT_ORDER_TEST = {
    "statistics",
    "heroicresources",
    "monstermode",
    "monsterabilities",
    "monstervillainactions",
    "monstertriggers",
    "monstertraits",
    "summoner",
    "routines",
    "persistentabilities",
    "otherresources",
    "skilllanguages",
    "perks",
    "notes",
}

--The order as it stood before the rework.
local TACPANEL_DEFAULT_ORDER_CLASSIC = {
    "statistics",
    --Conditions sit directly under the stats and above the abilities: what
    --is currently ON the monster is read far more often mid-fight than what
    --it can do.
    "conditions",
    "monstermode",
    "monsterabilities",
    "monstervillainactions",
    "monstertriggers",
    "monstertraits",
    "summoner",
    "routines",
    "persistentabilities",
    "heroicresources",
    "otherresources",
    "skilllanguages",
    "features",
    "perks",
    "notes",
}

--- The section list for whichever panel the flag currently selects.
---
--- Resolved per call, NOT once at load. Picking at load meant a panel opened
--- after the flag was toggled still used the list from startup -- which showed
--- as the reworked panel carrying a FEATURES section it had dropped.
--- @return string[]
local function ActiveOrder()
    return cond(TacPanel.UseTestPanel(),
        TACPANEL_DEFAULT_ORDER_TEST, TACPANEL_DEFAULT_ORDER_CLASSIC)
end

local TACPANEL_FACTORIES = {
    statistics = TacPanel.Statistics,
    monstermode = TacPanel.MonsterMode,
    monsterabilities = TacPanel.MonsterAbilities,
    monstervillainactions = TacPanel.MonsterVillainActions,
    monstertriggers = TacPanel.MonsterTriggers,
    monstertraits = TacPanel.MonsterTraits,
    routines = TacPanel.Routines,
    persistentabilities = TacPanel.PersistentAbilities,
    heroicresources = cond(TacPanel.UseTestPanel(),
        TacPanel.HeroicResources, TacPanel.HeroicResourcesClassic),
    otherresources = TacPanel.OtherResources,
    skilllanguages = TacPanel.SkillLanguages,
    perks = cond(TacPanel.UseTestPanel(), TacPanel.Perks, TacPanel.PerksClassic),
    --Classic only; both are absent from the reworked order above, so they are
    --built but never placed.
    conditions = TacPanel.Conditions,
    features = TacPanel.Features,
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

    --Into BOTH lists: a mod registering a section should get it whichever
    --panel the flag is on.
    for _, order in ipairs({TACPANEL_DEFAULT_ORDER_TEST, TACPANEL_DEFAULT_ORDER_CLASSIC}) do
        for i,existing in ipairs(order) do
            if existing == id then
                table.remove(order, i)
                break
            end
        end

        local insertAt = #order + 1
        if opts.after then
            for i,existing in ipairs(order) do
                if existing == opts.after then
                    insertAt = i + 1
                    break
                end
            end
        elseif opts.before then
            for i,existing in ipairs(order) do
                if existing == opts.before then
                    insertAt = i
                    break
                end
            end
        end
        table.insert(order, insertAt, id)
    end
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
        for _, id in ipairs(ActiveOrder()) do
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
    for _, id in ipairs(ActiveOrder()) do
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
    for _, id in ipairs(ActiveOrder()) do
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
                sortChildren(element, ActiveOrder())
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
						--Members indent behind a vertical nesting rail: with
						--the header band running full width (below), the rail
						--is what marks this block as a subfolder.
						local contentPanel = gui.Panel{
							width = "100%-12",
							height = "auto",
							flow = "vertical",
							halign = "right",
							vmargin = 4,
							bgimage = "panels/square.png",
							bgcolor = "clear",
							styles = ThemeEngine.MergeTokens{
								{
									border = {x1 = 2, x2 = 0, y1 = 0, y2 = 0},
									borderColor = "@border",
								},
							},
						}

						folder = gui.TreeNode{
							text = squadid,
							contentPanel = contentPanel,
							--full width: the header's dark band runs edge to
							--edge like the party headers above it.
							width = "100%",
							halign = "left",
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

						--Bring the squad node onto the character list's grammar:
						--gui.TreeNode ships its own ATTACHED styles (the old
						--white bitmap triangle with a yellow hover, a white
						--hover flash on the header, a 70% label), and attached
						--styles outrank the panel cascade, so the instances
						--are restyled directly here.
						--header restyle FIRST: the label gains the "folder"
						--class below, and this loop matches by that class --
						--running it later would clobber the label's styles.
						local headers = folder:GetChildrenWithClassRecursive("folder")
						for _,header in ipairs(headers) do
							header.styles = ThemeEngine.MergeTokens{
								{
									borderWidth = 0,
									bgcolor = "clear",
								},
								{
									selectors = {"hover"},
									bgcolor = "@bgAlt",
									transitionTime = 0.1,
								},
							}
						end

						local labels = folder:GetChildrenWithClassRecursive("folderLabel")
						for _,label in ipairs(labels) do
							label:SetClass("folderLabel", false)
							label:SetClass("bestiaryLabel", true)
							label:SetClass("folder", true)
							--drop the attached 70% fontSize so the cascade's
							--section-header sizing applies.
							label.styles = {
								{
									width = "auto",
									height = "auto",
									halign = "left",
									valign = "center",
								},
							}
						end

						local triangles = folder:GetChildrenWithClassRecursive("triangle")
						for _,tri in ipairs(triangles) do
							tri.bgimage = "phosphor/caret-down-fill.png"
							tri.styles = ThemeEngine.MergeTokens{
								{
									selectors = {"triangle"},
									bgcolor = "@fgMuted",
									width = 10,
									height = 10,
									halign = "left",
									margin = 5,
									rotate = 90,
									valign = "center",
								},
								{
									selectors = {"triangle", "hover"},
									bgcolor = "@fgStrong",
									transitionTime = 0.1,
								},
								{
									selectors = {"triangle", "expanded"},
									rotate = 0,
									transitionTime = 0.2,
								},
							}
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

    --The two halves of the top of the panel, picked once at build time. The
    --reworked version runs the identity strip full width with the portrait in
    --the vitals row below it; the classic one keeps the portrait beside the
    --name and gates the row on the token being a monster.
    local summaryPanel, vitalsRow
    if TacPanel.UseTestPanel() then
        summaryPanel = TacPanel.Summary()
        vitalsRow = gui.Panel{
            --See the "vitals-row" rules in TacPanelStyles.MonsterSheet, which
            --carry this row's ground colour and its rules.
            classes = {"container", "vitals-row"},

            TacPanel.PortraitColumn(),
            gui.Panel{
                classes = {"container"},
                --Leaves room for the portrait column: the 90px frame plus the
                --30px strip its rmargin reserves for the control buttons, plus
                --slack. A wrapped row that fills to within ~3px phantom-wraps,
                --reserving two lines to render one.
                width = "100%-134",
                height = "auto",
                flow = "vertical",
                valign = "top",
                TacPanel.Stamina(),
            },
        }
    else
        summaryPanel = TacPanel.SummaryClassic()
        vitalsRow = gui.Panel{
            classes = {"container", "vitals-row"},
            refreshCharacter = function(element, token)
                local isMonster = false
                if token ~= nil and token.valid and token.properties ~= nil then
                    pcall(function() isMonster = token.properties:IsMonster() end)
                end
                element:SetClass("monster", isMonster)
            end,
            setToken = function(element, token)
                element:FireEvent("refreshCharacter", token)
            end,

            TacPanel.GatedPortrait(true),
            gui.Panel{
                classes = {"container"},
                width = "100%",
                height = "auto",
                flow = "vertical",
                valign = "top",
                refreshCharacter = function(element, token)
                    local isMonster = false
                    if token ~= nil and token.valid and token.properties ~= nil then
                        pcall(function() isMonster = token.properties:IsMonster() end)
                    end
                    element.selfStyle.width = cond(isMonster, "100%-134", "100%")
                end,
                setToken = function(element, token)
                    element:FireEvent("refreshCharacter", token)
                end,
                TacPanel.StaminaClassic(),
            },
        }
    end

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

        summaryPanel,
        vitalsRow,
	}

	return RegisterRoot(characterDisplaySidebar)
end
