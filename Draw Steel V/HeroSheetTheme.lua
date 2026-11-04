local mod = dmhub.GetModLoading()

--The Hero sheet's shared look. Everything the sheet draws takes its colours
--from here, so the sheet follows the active colour scheme with every text
--colour checked to 4.5:1 on the surfaces it sits on; "act now" highlights
--use the scheme's @info and status marks @success / @warning / @danger. Also
--here: frost on the window's backdrop only, honouring Transparent UI and
--High Contrast; hover cards that wait for a deliberate hover and pin on
--click; labels that show their full text when cut off; and the window
--buttons.
--
--Use: the window root takes HeroSheetTheme.RootStyles(); panels below it use
--the class names in HeroSheetTheme.Rules (heroSheetMuted, heroSheetInfo...),
--or read a colour from HeroSheetTheme.Palette().

HeroSheetTheme = rawget(_G, "HeroSheetTheme") or {}

--WCAG AA for normal text.
HeroSheetTheme.READABLE = 4.5

--Hover cards wait this long for a deliberate hover.
HeroSheetTheme.HOVER_DELAY = 0.4

--A hover card's content width: a 430-wide card less its 16 units of
--padding a side and its edge.
HeroSheetTheme.CARD_WIDTH = 396

--The backdrop's frost radius (the EotW sheet's backdrop value).
local FROST_RADIUS = 18

--The EotW sheet's see-through model: a lightly tinted frosted backdrop, and
--every text surface (plates, the title bar) a plate of at least 0.85
--opacity, so text stays readable on any table, the whitest included. With Transparent UI off: near-solid backdrop, solid plates.
HeroSheetTheme.BACKDROP_FROSTED = 0.35
HeroSheetTheme.BACKDROP_SOLID = 0.95
--The Builder darkens the frost with a 35% black shade over the same
--backdrop: about 58% in all.
HeroSheetTheme.BACKDROP_BUILDER = 0.58
HeroSheetTheme.PLATE_SEE = 0.86

----------------------------------------------------------------------
--Colour maths (WCAG 2 relative luminance and contrast).

--- "#rrggbb" or "#rrggbbaa" to {r, g, b, a} (0-255, a 0-1), or nil.
--- @param hex any
--- @return nil|{r: number, g: number, b: number, a: number}
function HeroSheetTheme.ParseHex(hex)
    if type(hex) ~= "string" then
        return nil
    end
    local digits = string.gsub(hex, "#", "")
    if #digits ~= 6 and #digits ~= 8 then
        return nil
    end
    local r = tonumber(string.sub(digits, 1, 2), 16)
    local g = tonumber(string.sub(digits, 3, 4), 16)
    local b = tonumber(string.sub(digits, 5, 6), 16)
    local a = 255
    if #digits == 8 then
        a = tonumber(string.sub(digits, 7, 8), 16)
    end
    if r == nil or g == nil or b == nil or a == nil then
        return nil
    end
    return {r = r, g = g, b = b, a = a / 255}
end

--- {r, g, b, a} to "#rrggbb" (or "#rrggbbaa" when alpha is given).
--- @param color {r: number, g: number, b: number, a: number}
--- @param alpha nil|number 0-1
--- @return string
function HeroSheetTheme.ToHex(color, alpha)
    local function byte(value)
        return math.max(0, math.min(255, math.floor(value + 0.5)))
    end
    if alpha ~= nil then
        return string.format("#%02x%02x%02x%02x", byte(color.r), byte(color.g), byte(color.b), byte(alpha * 255))
    end
    return string.format("#%02x%02x%02x", byte(color.r), byte(color.g), byte(color.b))
end

--- from mixed toward to by amount (0 = from, 1 = to).
--- @param from {r: number, g: number, b: number, a: number}
--- @param to {r: number, g: number, b: number, a: number}
--- @param amount number
--- @return {r: number, g: number, b: number, a: number}
function HeroSheetTheme.Mix(from, to, amount)
    return {
        r = from.r + (to.r - from.r) * amount,
        g = from.g + (to.g - from.g) * amount,
        b = from.b + (to.b - from.b) * amount,
        a = from.a + (to.a - from.a) * amount,
    }
end

--- @param color {r: number, g: number, b: number, a: number}
--- @return number
function HeroSheetTheme.Luminance(color)
    local function channel(value)
        value = value / 255
        if value <= 0.03928 then
            return value / 12.92
        end
        return ((value + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
end

--- The WCAG contrast ratio of two colours (1 to 21).
--- @param first {r: number, g: number, b: number, a: number}
--- @param second {r: number, g: number, b: number, a: number}
--- @return number
function HeroSheetTheme.Contrast(first, second)
    local la = HeroSheetTheme.Luminance(first)
    local lb = HeroSheetTheme.Luminance(second)
    if la < lb then
        la, lb = lb, la
    end
    return (la + 0.05) / (lb + 0.05)
end

local WHITE = {r = 255, g = 255, b = 255, a = 1}
local BLACK = {r = 0, g = 0, b = 0, a = 1}

--- The colour with its alpha set (0-1).
--- @param hex string
--- @param alpha number
--- @return {r: number, g: number, b: number, a: number}
function HeroSheetTheme.WithAlpha(hex, alpha)
    local color = HeroSheetTheme.ParseHex(hex) or {r = 0, g = 0, b = 0, a = 1}
    color.a = alpha
    return color
end

--A see-through colour as it shows over a surface.
--- @param color {r: number, g: number, b: number, a: number}
--- @param over {r: number, g: number, b: number, a: number}
--- @return {r: number, g: number, b: number, a: number}
local function Over(color, over)
    if color.a >= 1 then
        return color
    end
    local mixed = HeroSheetTheme.Mix(over, color, color.a)
    mixed.a = 1
    return mixed
end

--- The colour moved toward white (on a dark surface) or black (on a light
--- one) just far enough to reach the ratio on every surface given; its hue
--- is kept. The surfaces are hex strings.
--- @param hex string
--- @param surfaces string[]
--- @param ratio nil|number default 4.5
--- @return string
function HeroSheetTheme.Readable(hex, surfaces, ratio)
    ratio = ratio or HeroSheetTheme.READABLE
    local color = HeroSheetTheme.ParseHex(hex)
    if color == nil then
        return hex
    end
    local parsed = {}
    for _, surface in ipairs(surfaces) do
        local surfaceColor = HeroSheetTheme.ParseHex(surface)
        if surfaceColor ~= nil then
            parsed[#parsed+1] = surfaceColor
        end
    end
    if #parsed == 0 then
        return hex
    end
    local first = Over(color, parsed[1])
    local function Worst(col)
        local worst = 21
        for _, surfaceColor in ipairs(parsed) do
            worst = math.min(worst, HeroSheetTheme.Contrast(col, surfaceColor))
        end
        return worst
    end
    if Worst(first) >= ratio then
        return HeroSheetTheme.ToHex(first)
    end
    local toward = WHITE
    if HeroSheetTheme.Luminance(parsed[1]) > 0.2 then
        toward = BLACK
    end
    for step = 1, 20 do
        local col = HeroSheetTheme.Mix(first, toward, step / 20)
        if Worst(col) >= ratio then
            return HeroSheetTheme.ToHex(col)
        end
    end
    return HeroSheetTheme.ToHex(toward)
end

----------------------------------------------------------------------
--The palette: the active scheme's colours with the sheet's roles, every
--text colour guarded to 4.5:1. Rebuilt only when the scheme's colours change.

--- @class HeroSheetPalette
--- @field bg string the window's surface
--- @field plate string a raised block on it
--- @field border string
--- @field fg string body text
--- @field strong string headings
--- @field muted string secondary text, guarded on bg and plate
--- @field info string "act now" gold, guarded
--- @field success string guarded
--- @field warning string guarded
--- @field danger string guarded
--- @field accent string
--- @field highContrast boolean
--- @field rawSuccess string the scheme's own status colours, for fills (bars), not text
--- @field rawWarning string
--- @field rawDanger string
--- @field rawFg string
--- @field rawInfo string the scheme's "act now" colour, for fills (the level button)
--- @field card string the card's plate (near-black in the Default scheme)
--- @field cardStrong string text on the card's plate, guarded on it
--- @field cardFg string
--- @field cardSub string
--- @field cardInfo string
--- @field cardSuccess string
--- @field cardWarning string
--- @field cardDanger string
--- @field cardLabel string the small labels' colour: tan in Default, the scheme's accent in others (EotW's rule)
--- @field cardLab string the softer labels beside numbers ("Weak", "Average")
--- @field tile string a characteristic tile's see-through ground
--- @field tileBorder string a tile's edge
--- @field tierInk string words on a leveled treasure's reached Level block (filled with cardStrong)

--- @type nil|HeroSheetPalette
local g_palette = nil
local g_paletteSignature = nil

--- @return HeroSheetPalette
function HeroSheetTheme.Palette()
    local colors = ThemeEngine.GetColorSchemeColors(ThemeEngine.GetActiveColorScheme()) or {}
    local function get(key, fallback)
        local value = colors[key]
        if type(value) ~= "string" then
            return fallback
        end
        return value
    end
    local signature = table.concat({
        get("bg", ""), get("bgAlt", ""), get("bgRaised", ""), get("fg", ""), get("fgStrong", ""), get("fgMuted", ""),
        get("info", ""), get("success", ""), get("warning", ""), get("danger", ""), get("borderSolid", ""), get("accent", ""),
        get("accentHover", ""), get("border", ""),
    }, "|")
    if g_palette ~= nil and signature == g_paletteSignature then
        return g_palette
    end
    --The plates and the card-side text follow the EotW sheet's scheme rules,
    --so both sheets read the same: Default gives a near-black, cream and tan;
    --other schemes blend the plates toward their background and take small
    --labels from their accent. The mapping below (the scheme's colours as
    --they are) is the fallback.
    --- @type nil|EotwSheetPalette
    local eotw = nil
    local eotwSheet = rawget(_G, "EotwHeroSheet")
    if eotwSheet ~= nil and eotwSheet.Palette ~= nil then
        pcall(function() eotw = eotwSheet.Palette() end)
    end
    --EotW's plate is see-through already; ours takes its alpha from the
    --frost setting, so only its colour is used.
    local function Opaque(hex)
        local color = HeroSheetTheme.ParseHex(hex)
        if color == nil then
            return hex
        end
        return HeroSheetTheme.ToHex(color)
    end
    local bg = get("bg", "#0a0a0b")
    local plate = bg
    if eotw ~= nil then
        plate = Opaque(eotw.BLOCK)
    end
    --a see-through plate over the brightest table is the worst case for text.
    local plateOverWhite = HeroSheetTheme.ToHex(Over(HeroSheetTheme.WithAlpha(plate, HeroSheetTheme.PLATE_SEE), WHITE))
    local surfaces = {bg, plate, plateOverWhite}
    --The card's plate is the same plate, and its text is checked against
    --that plate alone (and over white), so the colours stay as strong as the
    --scheme made them.
    local card = plate
    local cardOverWhite = HeroSheetTheme.ToHex(Over(HeroSheetTheme.WithAlpha(card, HeroSheetTheme.PLATE_SEE), WHITE))
    local cardSurfaces = {card, cardOverWhite}
    local labelMix = HeroSheetTheme.Mix(HeroSheetTheme.ParseHex(get("fgMuted", "#8a8a8a")) or WHITE, HeroSheetTheme.ParseHex(get("info", "#e9c868")) or WHITE, 0.5)
    local strongSource = get("fgStrong", "#ffffff")
    local fgSource = get("fg", "#dfcfc0")
    local subSource = get("fgMuted", "#c6d0da")
    local labelSource = HeroSheetTheme.ToHex(labelMix)
    local labSource = subSource
    if eotw ~= nil then
        strongSource = eotw.CREAM_LIGHT
        fgSource = eotw.CREAM
        subSource = eotw.MUTED
        labelSource = eotw.TAN
        labSource = eotw.LAB
    end
    local cardStrong = HeroSheetTheme.Readable(strongSource, cardSurfaces)
    local cardFg = HeroSheetTheme.Readable(fgSource, cardSurfaces)
    local cardSub = HeroSheetTheme.Readable(subSource, cardSurfaces)
    local cardInfo = HeroSheetTheme.Readable(get("info", "#ffd66b"), cardSurfaces)
    local cardSuccess = HeroSheetTheme.Readable(get("success", "#4db88c"), cardSurfaces)
    local cardWarning = HeroSheetTheme.Readable(get("warning", "#e8a030"), cardSurfaces)
    local cardDanger = HeroSheetTheme.Readable(get("danger", "#c94040"), cardSurfaces)
    local cardLabel = HeroSheetTheme.Readable(labelSource, cardSurfaces)
    local cardLab = HeroSheetTheme.Readable(labSource, cardSurfaces)
    local border = get("borderSolid", get("border", "#66666c"))
    --a reached Level block is filled with cardStrong; its words in the background
    --colour, made readable on that fill (as a picked Builder card).
    local tierInk = HeroSheetTheme.Readable(bg, {cardStrong})
    g_palette = {
        bg = bg,
        plate = plate,
        border = border,
        fg = HeroSheetTheme.Readable(get("fg", "#e8e8e8"), surfaces),
        strong = HeroSheetTheme.Readable(get("fgStrong", get("fg", "#ffffff")), surfaces),
        muted = HeroSheetTheme.Readable(get("fgMuted", "#a5a5a5"), surfaces),
        info = HeroSheetTheme.Readable(get("info", "#e9c868"), surfaces),
        success = HeroSheetTheme.Readable(get("success", "#6fbf73"), surfaces),
        warning = HeroSheetTheme.Readable(get("warning", "#e0a030"), surfaces),
        danger = HeroSheetTheme.Readable(get("danger", "#d9534f"), surfaces),
        accent = get("accent", get("info", "#e9c868")),
        highContrast = ThemeEngine.GetAccessibility().highContrast == true,
        rawSuccess = get("success", "#4db88c"),
        rawWarning = get("warning", "#e8a030"),
        rawDanger = get("danger", "#c94040"),
        rawFg = get("fg", "#dfcfc0"),
        rawInfo = get("info", "#ffd66b"),
        card = card,
        cardStrong = cardStrong,
        cardFg = cardFg,
        cardSub = cardSub,
        cardInfo = cardInfo,
        cardSuccess = cardSuccess,
        cardWarning = cardWarning,
        cardDanger = cardDanger,
        cardLabel = cardLabel,
        cardLab = cardLab,
        tile = eotw ~= nil and eotw.TILE or "#0000003a",
        tileBorder = eotw ~= nil and eotw.BORDER or border,
        tierInk = tierInk,
    }
    g_paletteSignature = signature
    return g_palette
end

--- An action colour (ActivatedAbility.actionColorKey) for small text, such
--- as a tag: lifted to 4.5:1 on the sheet's surfaces, hue kept.
--- The title bands keep the key's own colours.
--- @param hex string
--- @return string
function HeroSheetTheme.ActionTextColor(hex)
    local palette = HeroSheetTheme.Palette()
    return HeroSheetTheme.Readable(hex, {palette.bg, palette.plate})
end

----------------------------------------------------------------------
--Frost: one frosted surface per window, its backdrop, on the shared
--path; blocks, cards and pop-ups are solid tints. Off with Transparent UI
--off or a High Contrast scheme: then solid, at no cost.

--- True when the sheet is see-through (frosted).
--- @return boolean
function HeroSheetTheme.SeeThrough()
    return dmhub.GetSettingValue("graphics:uiblur") ~= false and not ThemeEngine.GetAccessibility().highContrast
end

--- Frost the window's backdrop, or make it solid, for the current settings.
--- The backdrop's tint is the scheme's surface: light over the frost, nearly
--- opaque when solid.
--- @param panel Panel
function HeroSheetTheme.ApplyBackdrop(panel)
    local palette = HeroSheetTheme.Palette()
    local bg = HeroSheetTheme.ParseHex(palette.bg) or BLACK
    local see = HeroSheetTheme.SeeThrough()
    --frost and frostShared are engine fields the stubs do not list.
    local any = panel --[[@as any]]
    pcall(function()
        if see then
            any.frost = FROST_RADIUS
            any.frostShared = true
        else
            any.frost = 0
            any.frostShared = false
        end
    end)
    local alpha = cond(see, HeroSheetTheme.BACKDROP_FROSTED, HeroSheetTheme.BACKDROP_SOLID)
    --a window showing the Builder (HeroSheetWindow's data.builder).
    local data = panel.data
    if see and type(data) == "table" and data.builder == true then
        alpha = HeroSheetTheme.BACKDROP_BUILDER
    end
    panel.selfStyle.bgcolor = HeroSheetTheme.ToHex(bg, alpha)
end

----------------------------------------------------------------------
--The sheet's rules, with the palette's colours.

--- @return table[]
function HeroSheetTheme.Rules()
    local palette = HeroSheetTheme.Palette()
    local plateAlpha = cond(HeroSheetTheme.SeeThrough(), HeroSheetTheme.PLATE_SEE, 1)
    --the background mixed toward a colour by amount (0-1), solid: see-through
    --fills blend lighter than they look. Used for chips and raised rows.
    --- @param hex string
    --- @param amount number
    --- @return string
    local function ChipMix(hex, amount)
        return HeroSheetTheme.ToHex(HeroSheetTheme.Mix(HeroSheetTheme.ParseHex(palette.bg) or BLACK, HeroSheetTheme.ParseHex(hex) or WHITE, amount))
    end
    --the background lifted toward white by amount: a solid step lighter.
    --- @param amount number
    --- @return string
    local function Lift(amount)
        return ChipMix("#ffffff", amount)
    end
    --a palette colour at an alpha (0-1).
    --- @param hex string
    --- @param alpha number
    --- @return string
    local function Tint(hex, alpha)
        return HeroSheetTheme.ToHex(HeroSheetTheme.WithAlpha(hex, 1), alpha)
    end
    --white at an alpha (0-1) over the background, as the solid colour the
    --engine shows (it blends in linear light). For bordered rounded buttons:
    --a see-through fill puts a light fringe on their corners.
    --- @param alpha number
    --- @return string
    local function SolidWhite(alpha)
        local bg = HeroSheetTheme.ParseHex(palette.bg) or BLACK
        local function channel(value)
            local srgb = value / 255
            local linear = cond(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ^ 2.4)
            linear = linear + (1 - linear) * alpha
            srgb = cond(linear <= 0.0031308, linear * 12.92, 1.055 * linear ^ (1 / 2.4) - 0.055)
            return srgb * 255
        end
        return HeroSheetTheme.ToHex({r = channel(bg.r), g = channel(bg.g), b = channel(bg.b), a = 1})
    end
    local rules = {
        {selectors = {"heroSheetTitle"}, color = palette.strong},
        {selectors = {"heroSheetText"}, color = palette.fg},
        {selectors = {"heroSheetMuted"}, color = palette.muted},
        {selectors = {"heroSheetInfo"}, color = palette.info},
        {selectors = {"heroSheetSuccess"}, color = palette.success},
        {selectors = {"heroSheetWarning"}, color = palette.warning},
        {selectors = {"heroSheetDanger"}, color = palette.danger},
        --solid blocks and cards on the backdrop (one frosted surface per window).
        --a plate shows a little of the frost when see-through, none when solid.
        {selectors = {"heroSheetPlate"}, bgcolor = Tint(palette.plate, plateAlpha), borderColor = palette.border},
        {selectors = {"heroSheetPopup"}, bgcolor = palette.bg, borderColor = palette.border},
        {selectors = {"heroSheetCard"}, bgcolor = palette.plate, borderColor = palette.border},
        {selectors = {"heroSheetCard", "heroSheetCardPinned"}, borderColor = palette.cardStrong},
        --the switcher: the open Hero has a gold edge in the "act now"
        --colour and a light ring just outside it; the others a dark edge.
        {selectors = {"heroSheetRing"}, borderColor = palette.info},
        {selectors = {"heroSheetRingOuter"}, borderColor = palette.strong},
        {selectors = {"heroSheetThumbRest"}, borderColor = "#000000ff"},
        {selectors = {"heroSheetSwitcherBadge"}, bgcolor = Tint(palette.strong, 0.92), color = palette.bg},
        {selectors = {"heroSheetTokenPill"}, bgcolor = "clear", borderColor = "#ffffff24"},
        {selectors = {"heroSheetDivider"}, bgcolor = palette.border},
        --the top bar's buttons on a faint fill; the tabs one joined group;
        --the open tab (and Done) filled in the scheme's text colour.
        {selectors = {"heroSheetButton"}, bgcolor = SolidWhite(0.05), borderColor = palette.border},
        {selectors = {"heroSheetButton", "hover"}, borderColor = palette.strong},
        {selectors = {"heroSheetButton", "selected"}, bgcolor = palette.rawFg, borderColor = palette.rawFg},
        {selectors = {"heroSheetSegments"}, bgcolor = "clear", borderColor = palette.border},
        {selectors = {"heroSheetSegment"}, bgcolor = "#ffffff0d"},
        {selectors = {"heroSheetSegment", "hover"}, bgcolor = "#ffffff17"},
        {selectors = {"heroSheetSegment", "selected"}, bgcolor = palette.rawFg},
        {selectors = {"heroSheetSegmentLine"}, bgcolor = palette.border},
        {selectors = {"heroSheetButtonLabel"}, color = palette.fg},
        {selectors = {"heroSheetButtonLabel", "selected"}, color = palette.bg, bold = true},
        {selectors = {"heroSheetButtonIcon"}, bgcolor = palette.fg},
        {selectors = {"heroSheetButtonIcon", "selected"}, bgcolor = palette.bg},
        --the needed bar: ink on the scheme's "act now" gold.
        {selectors = {"heroSheetNeedBar"}, bgcolor = palette.info},
        {selectors = {"heroSheetNeedText"}, color = palette.bg},
        {selectors = {"heroSheetNeedDot"}, bgcolor = palette.bg},
        {selectors = {"heroSheetNeedClose"}, bgcolor = palette.bg},
        {selectors = {"heroSheetNeedButton"}, color = palette.bg, bgcolor = "#00000020", borderColor = palette.bg},
        --the card: a near-black plate, strong text, the scheme's own colours
        --for the bars.
        {selectors = {"heroSheetCardPlate"}, bgcolor = Tint(palette.card, plateAlpha)},
        {selectors = {"heroSheetCardStrong"}, color = palette.cardStrong},
        {selectors = {"heroSheetCardText"}, color = palette.cardFg},
        {selectors = {"heroSheetCardSub"}, color = palette.cardSub},
        {selectors = {"heroSheetCardInfo"}, color = palette.cardInfo},
        {selectors = {"heroSheetCardSuccess"}, color = palette.cardSuccess},
        {selectors = {"heroSheetCardWarning"}, color = palette.cardWarning},
        {selectors = {"heroSheetCardDanger"}, color = palette.cardDanger},
        {selectors = {"heroSheetCardLabel"}, color = palette.cardLabel},
        --the blocks under the card: a faint edge.
        {selectors = {"heroSheetBlock"}, borderColor = "#ffffff1a"},
        {selectors = {"heroSheetKitPick"}, bgcolor = "clear", borderColor = palette.border},
        {selectors = {"heroSheetKitPick", "selected"}, bgcolor = palette.cardStrong, borderColor = palette.cardStrong},
        {selectors = {"heroSheetKitPickText"}, color = palette.bg},
        {selectors = {"heroSheetInfoIcon"}, bgcolor = palette.cardInfo},
        {selectors = {"heroSheetMutedIcon"}, bgcolor = palette.cardSub},
        {selectors = {"heroSheetFg"}, bgcolor = palette.cardFg},
        {selectors = {"heroSheetDisabled"}, opacity = 0.5},
        {selectors = {"heroSheetPlateButton"}, bgcolor = SolidWhite(0.08), borderColor = palette.cardFg, color = palette.cardStrong},
        {selectors = {"heroSheetCardAppear"}, bgcolor = "#000000b0", borderColor = palette.cardFg, color = palette.cardStrong, hidden = 1},
        {selectors = {"heroSheetCardAppear", "parent:hover"}, hidden = 0},
        {selectors = {"heroSheetXpTrack"}, bgcolor = "#ffffff1f"},
        {selectors = {"heroSheetXpFill"}, bgcolor = palette.rawFg},
        {selectors = {"heroSheetXpBanked"}, bgcolor = Tint(palette.rawFg, 0.3)},
        --banked experience on the XP bar: cream stripes on a faint cream
        --ground (a hatch, drawn as EotW draws it).
        {selectors = {"heroSheetHatchGround"}, bgcolor = Tint(palette.rawFg, 0.25)},
        {selectors = {"heroSheetHatchStripe"}, bgcolor = Tint(palette.rawFg, 0.9)},
        --the level line's button: dark with a gold edge, filled gold when
        --there is something to do (the scheme's @info).
        {selectors = {"heroSheetLevelButton"}, bgcolor = "#00000059", borderColor = Tint(palette.rawInfo, 0.55), color = palette.cardStrong},
        {selectors = {"heroSheetLevelButton", "hover"}, borderColor = palette.rawInfo, color = "#ffffffff"},
        {selectors = {"heroSheetLevelButton", "heroSheetLevelReady"}, bgcolor = palette.rawInfo, borderColor = palette.rawInfo, color = palette.bg},
        --the dotted underline under click-to-type numbers.
        {selectors = {"heroSheetDot"}, bgcolor = "#ffffff73"},
        --the card's faint rule above Recoveries.
        {selectors = {"heroSheetCardRule"}, bgcolor = "#ffffff1a"},
        {selectors = {"heroSheetXpNotch"}, bgcolor = "#000000ff"},
        {selectors = {"heroSheetCardFrame"}, borderColor = "#ffffff26"},
        --the Treasures block: item rows, their small buttons and the
        --carried pill (@warning past three).
        {selectors = {"heroSheetItemRow"}, bgcolor = "#00000033", borderColor = palette.border},
        {selectors = {"heroSheetSmallButton"}, bgcolor = SolidWhite(0.06), borderColor = palette.border, color = palette.cardFg},
        {selectors = {"heroSheetSmallButton", "hover"}, borderColor = palette.cardStrong, color = palette.cardStrong},
        {selectors = {"heroSheetSmallButton", "heroSheetOff"}, opacity = 0.5},
        {selectors = {"heroSheetSmallButton", "heroSheetOff", "hover"}, borderColor = palette.border, color = palette.cardFg},
        {selectors = {"heroSheetPill"}, borderColor = palette.border, color = palette.cardSub},
        {selectors = {"heroSheetPill", "heroSheetPillWarn"}, borderColor = Tint(palette.rawWarning, 0.6), color = palette.cardWarning},
        {selectors = {"heroSheetRing2"}, bgcolor = "#000000a0", borderColor = Tint(palette.rawFg, 0.6)},
        {selectors = {"heroSheetRing2", "hover"}, borderColor = palette.cardStrong},
        --the Stamina bar: the fill in the scheme's own status colour.
        {selectors = {"heroSheetHpBar"}, bgcolor = "#00000066", borderColor = palette.rawSuccess},
        {selectors = {"heroSheetHpBar", "winded"}, borderColor = palette.rawWarning},
        {selectors = {"heroSheetHpBar", "dying"}, borderColor = palette.rawDanger},
        {selectors = {"heroSheetHpClip"}, bgcolor = "clear"},
        {selectors = {"heroSheetHpFill"}, bgcolor = palette.rawSuccess},
        {selectors = {"heroSheetHpFill", "winded"}, bgcolor = palette.rawWarning},
        {selectors = {"heroSheetHpFill", "dying"}, bgcolor = palette.rawDanger},
        {selectors = {"heroSheetHpTemp"}, bgcolor = "#e4ddd0ff"},
        {selectors = {"heroSheetHpSheen"}, bgcolor = "#ffffff1c"},
        {selectors = {"heroSheetHpZones"}, hidden = 1},
        {selectors = {"heroSheetHpZones", "parent:hover"}, hidden = 0},
        --the bar keeps its dark zones in every scheme, so its text is a
        --fixed light colour.
        {selectors = {"heroSheetHpZone"}, bgcolor = "#0d0d0cff", color = "#f3ede7ff"},
        {selectors = {"heroSheetHpNumber"}, color = "#ffffffff"},
        {selectors = {"heroSheetHpZone", "hover"}, bgcolor = "#2c2a25ff"},
        {selectors = {"heroSheetHpDmg", "hover"}, bgcolor = "#4a1c1aff"},
        {selectors = {"heroSheetHpHeal", "hover"}, bgcolor = "#18402fff"},
        {selectors = {"heroSheetHpField"}, bgcolor = "#0b0b0aff"},
        --a number being typed: a small field, sized to the value, so nothing
        --around it moves.
        {selectors = {"heroSheetNumberInput"}, bgcolor = "#000000ff", borderColor = palette.cardStrong, border = 1, color = "#ffffffff", bold = true, textAlignment = "center", pad = 0, cornerRadius = 3},
        {selectors = {"heroSheetHush"}, hidden = 1},
        --sheet windows: the header's rule, small headings (the warm
        --label colour) and Save as the window's main button (a cream edge).
        {selectors = {"heroSheetDialogRule"}, bgcolor = Tint(palette.cardLabel, 0.4)},
        {selectors = {"heroSheetFooterRule"}, bgcolor = "#ffffff14"},
        {selectors = {"heroSheetFieldLabel"}, color = palette.cardLabel},
        --buttons in a window are solid: a see-through white fill blends in
        --linear light and reads far lighter over a window's black.
        {selectors = {"heroSheetButton", "heroSheetSolid"}, bgcolor = Lift(0.1)},
        {selectors = {"heroSheetButton", "heroSheetSolid", "hover"}, bgcolor = Lift(0.15)},
        {selectors = {"heroSheetButton", "heroSheetPrimary"}, borderColor = palette.strong},
        {selectors = {"heroSheetButtonLabel", "heroSheetPrimary"}, color = palette.strong},
        --a popover's list (Controlled by): a row lights on hover, the
        --current one stays lit and bold.
        {selectors = {"heroSheetPopRow"}, bgcolor = "clear"},
        {selectors = {"heroSheetPopRow", "hover"}, bgcolor = "#ffffff12"},
        {selectors = {"heroSheetPopRow", "selected"}, bgcolor = "#ffffff12"},
        {selectors = {"heroSheetPopRowText"}, color = palette.cardFg},
        {selectors = {"heroSheetPopRowText", "selected"}, color = palette.cardStrong, bold = true},
        --the card's name row in Edit mode: the dashed line under the
        --name (gone while it is typed into), the name's field in the click-to-
        --type numbers' look and the name's own face, the eye and dice, and
        --the Director's Controlled by pill.
        {selectors = {"heroSheetNameEdit"}, borderColor = Tint(palette.rawFg, 0.7)},
        {selectors = {"heroSheetNameEdit", "heroSheetTyping"}, borderColor = "#00000000"},
        --a dashed box around a link to another tab (the Inventory's craft line).
        {selectors = {"heroSheetDashedBox"}, borderColor = Tint(palette.rawFg, 0.35)},
        {selectors = {"heroSheetNameField"}, bgcolor = "#000000ff", borderColor = palette.cardStrong, border = 1, color = "#ffffffff", cornerRadius = 3, fontFace = "@label"},
        {selectors = {"heroSheetIconButton"}, bgcolor = "clear", borderColor = "#ffffff2e"},
        {selectors = {"heroSheetIconButton", "hover"}, borderColor = palette.cardFg},
        {selectors = {"heroSheetIconButtonIcon"}, bgcolor = palette.cardFg},
        --the stats band: characteristic tiles and Medium's cells on a
        --faint dark ground, the faint rules between its parts, the Potency
        --pill's warm edge, and the line under each row of a hover card.
        {selectors = {"heroSheetTile"}, bgcolor = palette.tile, borderColor = palette.tileBorder},
        {selectors = {"heroSheetCardLab"}, color = palette.cardLab},
        {selectors = {"heroSheetBandRule"}, bgcolor = "#ffffff14"},
        {selectors = {"heroSheetBandEdge"}, bgcolor = "clear", borderColor = "#ffffff14"},
        {selectors = {"heroSheetPotency"}, bgcolor = "clear", borderColor = Tint(palette.cardLabel, 0.35)},
        {selectors = {"heroSheetCardRowLine"}, bgcolor = "clear", borderColor = "#ffffff12"},
        {selectors = {"heroSheetCtrlPill"}, bgcolor = "clear", borderColor = "#ffffff2e", color = palette.cardFg},
        {selectors = {"heroSheetCtrlPill", "hover"}, borderColor = palette.cardFg, color = palette.cardStrong},
        --Edit mode in the band: a dashed frame on what can be edited,
        --solid and light while hovered (heroSheetLit); a tile's own edge
        --turns dashed instead. Out of Edit mode the frame's edge is clear.
        {selectors = {"heroSheetEditFrame"}, bgcolor = "clear", borderColor = "#00000000", borderStyle = "dashed"},
        {selectors = {"heroSheetEditFrame", "heroSheetEditOn"}, borderColor = Tint(palette.rawFg, 0.6)},
        {selectors = {"heroSheetEditFrame", "heroSheetEditOn", "heroSheetLit"}, borderColor = palette.cardStrong, borderStyle = "solid"},
        {selectors = {"heroSheetTile", "heroSheetEditTile"}, borderColor = Tint(palette.rawFg, 0.6), borderStyle = "dashed"},
        {selectors = {"heroSheetTile", "heroSheetEditTile", "heroSheetLit"}, borderColor = palette.cardStrong, borderStyle = "solid"},
        --a stat's editor in its pinned card: black fields with the card's
        --edge, lit by the strong text colour while typed into.
        {selectors = {"input", "heroSheetField"}, bgcolor = "#000000ff", borderColor = palette.border, color = palette.cardStrong, fontSize = 14},
        {selectors = {"input", "heroSheetField", "hover"}, bgcolor = "#000000ff", borderColor = palette.cardSub},
        {selectors = {"input", "heroSheetField", "focus"}, bgcolor = "#000000ff", borderColor = palette.cardStrong},
        {selectors = {"dropdown", "heroSheetField"}, bgcolor = "#000000ff", borderColor = palette.border, border = 1, cornerRadius = 5},
        {selectors = {"dropdown", "heroSheetField", "hover"}, bgcolor = "#000000ff", borderColor = palette.cardSub},
        {selectors = {"label", "dropdownLabel", "parent:heroSheetField"}, fontSize = 14, color = palette.cardStrong},
        {selectors = {"label", "dropdownLabel", "parent:heroSheetField", "parent:hover"}, color = palette.cardStrong},
        {selectors = {"dropdownTriangle", "parent:heroSheetField"}, priority = 5, bgcolor = palette.cardFg},
        --an open choice lists its options at the fields' size.
        {selectors = {"dropdownOption"}, fontSize = 14},
        --the x on a row that can be removed: reddish on hover.
        {selectors = {"heroSheetXButton"}, bgcolor = "clear", borderColor = palette.border},
        {selectors = {"heroSheetXButton", "hover"}, borderColor = palette.cardDanger},
        {selectors = {"heroSheetXIcon"}, bgcolor = palette.cardFg},
        {selectors = {"heroSheetXIcon", "parent:hover"}, bgcolor = palette.cardDanger},
        --"+ Add" by a word heading: a cream edge at about half strength and a
        --faint fill (kept low: see-through fills blend lighter here), the
        --icon in the text's colour.
        {selectors = {"heroSheetHeadPill"}, bgcolor = Tint(palette.rawFg, 0.04), borderColor = Tint(palette.rawFg, 0.55)},
        {selectors = {"heroSheetHeadPill", "hover"}, bgcolor = Tint(palette.rawFg, 0.12)},
        {selectors = {"heroSheetHeadPillIcon"}, bgcolor = palette.cardStrong},
        --Speed's movement types: a small box, ticked when the Hero has it.
        {selectors = {"heroSheetCheck"}, bgcolor = "#000000ff", borderColor = palette.cardSub},
        {selectors = {"heroSheetCheck", "hover"}, borderColor = palette.cardStrong},
        {selectors = {"heroSheetCheckMark"}, bgcolor = palette.cardStrong},
        --the Skills & Languages component: its grant rows and skill chips.
        --Rows are a lighter step of the surface (solid mixes: see-through
        --fills blend lighter here). Chips: open ones raised (a faint fill and edge), a picked one cream with dark
        --text, one another row holds a dim cream, one that cannot be picked
        --flat (no fill or edge, text still 4.5:1), one the Hero has from
        --elsewhere in the label colour (the scheme's accent outside Default).
        {selectors = {"heroSklRow"}, bgcolor = Lift(0.06), borderColor = palette.border},
        {selectors = {"heroSklRow", "hover"}, bgcolor = Lift(0.12)},
        {selectors = {"heroSklRow", "heroSklRowSelected"}, bgcolor = Lift(0.12), borderColor = palette.cardStrong},
        {selectors = {"heroSklRowBar"}, bgcolor = palette.cardStrong},
        {selectors = {"heroSklStatusStrong"}, bold = true},
        {selectors = {"heroSklPill"}, bgcolor = palette.cardFg, color = palette.bg},
        {selectors = {"heroSklAdd"}, bgcolor = "clear", borderColor = Tint(palette.rawFg, 0.5), borderStyle = "dashed"},
        {selectors = {"heroSklAdd", "hover"}, bgcolor = ChipMix(palette.rawFg, 0.06), borderColor = palette.cardStrong},
        {selectors = {"heroSklAddIcon"}, bgcolor = palette.cardFg},
        {selectors = {"heroSklFilter"}, bgcolor = Lift(0.12), borderColor = palette.border},
        {selectors = {"heroSklColumn"}, bgcolor = "clear", borderColor = "#ffffff14"},
        {selectors = {"heroSklChip"}, bgcolor = "clear", borderColor = palette.border},
        {selectors = {"heroSklChip", "hover"}, borderColor = palette.cardFg},
        {selectors = {"heroSklChip", "heroSklPicked"}, bgcolor = palette.cardFg, borderColor = palette.cardFg},
        --the component's own chips (heroSklOption; the Features filter and
        --Titles chips share heroSklChip and keep its plain look). Each state
        --names its hover too, so hovering never lights a picked or flat chip.
        {selectors = {"heroSklChip", "heroSklOption"}, bgcolor = ChipMix(palette.cardFg, 0.075), borderColor = ChipMix(palette.cardFg, 0.42)},
        {selectors = {"heroSklChip", "heroSklOption", "hover"}, bgcolor = ChipMix(palette.cardFg, 0.14), borderColor = palette.cardStrong},
        {selectors = {"heroSklChip", "heroSklOption", "heroSklPicked"}, bgcolor = palette.cardFg, borderColor = palette.cardFg},
        {selectors = {"heroSklChip", "heroSklOption", "heroSklPicked", "hover"}, bgcolor = palette.cardStrong, borderColor = palette.cardStrong},
        {selectors = {"heroSklChip", "heroSklOption", "heroSklLocked"}, bgcolor = ChipMix(palette.cardFg, 0.28), borderColor = "#00000000"},
        {selectors = {"heroSklChip", "heroSklOption", "heroSklLocked", "hover"}, bgcolor = ChipMix(palette.cardFg, 0.28), borderColor = "#00000000"},
        --flat: no fill or edge (the solid plate is for the Builder's
        --characteristic tiles only).
        {selectors = {"heroSklChip", "heroSklOption", "heroSklUnav"}, bgcolor = "clear", borderColor = "#00000000"},
        {selectors = {"heroSklChip", "heroSklOption", "heroSklUnav", "hover"}, bgcolor = "clear", borderColor = "#00000000"},
        {selectors = {"heroSklChip", "heroSklOption", "heroSklKnown"}, bgcolor = ChipMix(palette.cardLabel, 0.14), borderColor = ChipMix(palette.cardLabel, 0.62)},
        {selectors = {"heroSklChip", "heroSklOption", "heroSklKnown", "hover"}, bgcolor = ChipMix(palette.cardLabel, 0.14), borderColor = ChipMix(palette.cardLabel, 0.62)},
        {selectors = {"heroSklChipText"}, color = palette.cardFg},
        {selectors = {"heroSklChipText", "heroSklPicked"}, color = palette.bg, bold = true},
        {selectors = {"heroSklChipText", "heroSklLocked"}, color = palette.cardStrong, bold = true},
        {selectors = {"heroSklChipText", "heroSklUnav"}, color = palette.cardSub},
        {selectors = {"heroSklChipText", "heroSklKnown"}, color = palette.cardLabel},
        {selectors = {"heroSklSizer"}, color = "#00000000"},
        {selectors = {"heroSklChipSpeakers"}, color = palette.cardSub},
        {selectors = {"heroSklChipSpeakers", "heroSklPicked"}, color = palette.bg},
        {selectors = {"heroSklChipMark"}, color = palette.cardLabel},
        {selectors = {"heroSklChipMark", "heroSklPicked"}, color = palette.bg},
        {selectors = {"heroSklDeadTag"}, bgcolor = "clear", borderColor = palette.border, color = palette.cardSub},
        --the lists: ability rows a lighter step of the surface (solid
        --mixes), a pinned card's row edged in the strong colour; the heading
        --tabs muted, the open one strong over a warm underline.
        {selectors = {"heroSheetListRow"}, bgcolor = Lift(0.07), borderColor = palette.border},
        {selectors = {"heroSheetListRow", "hover"}, bgcolor = Lift(0.12), borderColor = palette.cardSub},
        {selectors = {"heroSheetListRow", "heroSheetRowPinned"}, borderColor = palette.cardStrong},
        {selectors = {"heroSheetListTab"}, color = palette.cardSub},
        {selectors = {"heroSheetListTab", "selected"}, color = palette.cardStrong},
        {selectors = {"heroSheetListTabFrame"}, bgcolor = "clear", borderColor = "#00000000"},
        {selectors = {"heroSheetListTabFrame", "selected"}, borderColor = palette.cardLabel},
        {selectors = {"heroSheetCustomPill"}, bgcolor = ChipMix(palette.rawFg, 0.1), borderColor = Tint(palette.rawFg, 0.5)},
        --a row's "..." shows while the row is hovered, and always in Edit mode.
        {selectors = {"heroSheetKeb"}, collapsed = 1, bgcolor = "clear", borderColor = "#00000000"},
        {selectors = {"heroSheetKeb", "parent:hover"}, collapsed = 0},
        {selectors = {"heroSheetKeb", "heroSheetEditOn"}, collapsed = 0},
        {selectors = {"heroSheetKeb", "heroSheetKebOff"}, collapsed = 1, priority = 5},
        --the Inventory pane's "..." shows at all times, beside its buttons.
        {selectors = {"heroSheetKeb", "heroSheetKebAlways"}, collapsed = 0, borderColor = palette.border},
        --dragging an item: the chip on the pointer, the row it came from
        --dimmed, the zones at the foot of the list, and a target edged in the
        --gold "act now" colour while the chip is over it.
        {selectors = {"heroSheetDragChip"}, bgcolor = palette.plate, borderColor = palette.cardStrong},
        {selectors = {"heroSheetDragCover"}, collapsed = 1, bgcolor = "#000000a0"},
        {selectors = {"heroSheetDragCover", "parent:heroSheetDragSource"}, collapsed = 0},
        {selectors = {"heroSheetDropZone"}, bgcolor = HeroSheetTheme.ToHex(HeroSheetTheme.WithAlpha(palette.plate, 0.94)), borderColor = palette.border},
        {selectors = {"heroSheetDropZone", "heroSheetDropZoneDanger"}, borderColor = palette.cardDanger},
        {selectors = {"heroSheetDropZone", "heroSheetDropOver"}, bgcolor = HeroSheetTheme.ToHex(HeroSheetTheme.Mix(HeroSheetTheme.ParseHex(palette.plate) or BLACK, WHITE, 0.12)), borderColor = palette.info},
        --the scheme's own gold at full strength, thicker: the guarded gold reads too subtle.
        {selectors = {"heroSheetDropTarget", "heroSheetDropOver"}, borderColor = HeroSheetTheme.ToHex(HeroSheetTheme.WithAlpha(palette.rawInfo, 1)), border = 3},
        --the Give window's targets: the picked one edged in the strong colour.
        {selectors = {"heroSheetGiveTarget"}, bgcolor = "#ffffff0f", borderColor = palette.border},
        {selectors = {"heroSheetGiveTarget", "heroSheetGivePicked"}, borderColor = palette.cardStrong},
        --a leveled treasure's Level blocks: a reached one filled solid with the strong card colour, its words dark, as
        --a picked Builder card; one not reached yet stays dark with muted words.
        {selectors = {"heroSheetTier"}, bgcolor = "#00000033", borderColor = palette.border, border = 1},
        {selectors = {"heroSheetTier", "heroSheetTierReached"}, bgcolor = palette.cardStrong, borderColor = palette.cardStrong},
        {selectors = {"heroSheetCardText", "parent:heroSheetTierReached"}, color = palette.tierInk},
        {selectors = {"heroSheetCardLabel", "parent:heroSheetTierReached"}, color = palette.tierInk},
        {selectors = {"heroSheetCardText", "heroSheetTierDim"}, color = palette.cardSub},
        {selectors = {"heroSheetCardLabel", "heroSheetTierDim"}, color = palette.cardSub},
        {selectors = {"heroSheetKeb", "hover"}, bgcolor = Lift(0.14), borderColor = palette.border},
        {selectors = {"heroSheetPopRowText", "heroSheetMenuDanger"}, color = palette.cardDanger},
        --the Features list: cards on the rows' surface, the Core feature
        --edged warm, a custom feature dashed; pillar tags small bordered
        --pills; Show more warm, View ability light.
        {selectors = {"heroSheetFeatCard"}, bgcolor = Lift(0.07), borderColor = palette.border},
        {selectors = {"heroSheetFeatCard", "heroSheetFeatCore"}, borderColor = Tint(palette.cardLabel, 0.6)},
        {selectors = {"heroSheetFeatCard", "heroSheetFeatCustom"}, borderColor = Tint(palette.rawFg, 0.4), borderStyle = "dashed"},
        {selectors = {"heroSheetFeatTag"}, bgcolor = "clear", borderColor = palette.border},
        {selectors = {"heroSheetFeatLink"}, color = palette.cardLabel},
        {selectors = {"heroSheetFeatLink", "hover"}, color = palette.cardStrong},
        {selectors = {"heroSheetFeatLinkLight"}, color = palette.cardFg},
        {selectors = {"heroSheetFeatLinkLight", "hover"}, color = palette.cardStrong},
        --a choice still to make: the info colour on a faint fill; a hidden
        --feature (Show hidden) dashed.
        {selectors = {"heroSheetChoicePlate"}, bgcolor = Tint(palette.cardInfo, 0.16), borderColor = Tint(palette.cardInfo, 0.6)},
        {selectors = {"heroSheetFeatCard", "heroSheetFeatHidden"}, borderStyle = "dashed"},
        {selectors = {"heroSheetChoicePlate", "hoverable", "hover"}, borderColor = palette.cardInfo},
        {selectors = {"heroSheetIconButton", "selected"}, bgcolor = "#ffffff1f", borderColor = palette.cardFg},
        --the Titles window: a held title still to choose its benefit is
        --edged in the info colour (the one the card's line opened on, fully);
        --a benefit is a radio row, the picked one edged strong.
        {selectors = {"heroSheetFeatCard", "heroSheetTitleTodo"}, borderColor = Tint(palette.cardInfo, 0.55)},
        {selectors = {"heroSheetFeatCard", "heroSheetTitleFocus"}, borderColor = palette.cardInfo, border = 2},
        {selectors = {"heroSheetFeatCard", "heroSheetBenefit", "hover"}, borderColor = palette.cardSub},
        {selectors = {"heroSheetFeatCard", "heroSheetBenefit", "selected"}, borderColor = palette.cardStrong},
        {selectors = {"heroSheetRadio"}, bgcolor = "clear", borderColor = palette.cardSub},
        {selectors = {"heroSheetRadio", "selected"}, borderColor = palette.cardStrong},
        {selectors = {"heroSheetRadioDot"}, bgcolor = palette.cardStrong},
        --the card's "Add a title": a quiet dashed pill that lights on hover.
        {selectors = {"heroSheetTitleAdd"}, bgcolor = "clear", borderColor = "#ffffff47", borderStyle = "dashed"},
        {selectors = {"heroSheetTitleAdd", "hover"}, borderColor = "#ffffff99"},
        {selectors = {"heroSheetTitleAddText"}, color = palette.cardFg},
        {selectors = {"heroSheetTitleAddText", "parent:hover"}, color = "#ffffff"},
        {selectors = {"heroSheetTitleAddIcon"}, bgcolor = palette.cardFg},
        --the Appearance tab's look tiles: the shown look in the strong colour.
        {selectors = {"heroLookTile"}, bgcolor = "#ffffff0a", borderColor = palette.border},
        {selectors = {"heroLookTile", "hover"}, borderColor = palette.cardFg},
        {selectors = {"heroLookTile", "selected"}, borderColor = palette.cardStrong},
        --the Summons tab: a customised summon's gold ring in the list.
        {selectors = {"heroSummonCustom"}, bgcolor = "clear", borderColor = palette.info},
        --the Effects tab's dice: a die grows when the pointer is on
        --it, like the Dice panel's; the Dice window's sets sit in bare spots
        --that light on hover.
        {selectors = {"heroDicePop"}, scale = 1, transitionTime = 0.12},
        {selectors = {"heroDicePop", "heroDicePopped"}, scale = 1.18},
        {selectors = {"heroDiceSpot"}, bgcolor = "#ffffff00", borderColor = "#ffffff00"},
        {selectors = {"heroDiceSpot", "hover"}, bgcolor = "#ffffff12"},
        {selectors = {"heroDiceSpot", "selected"}, borderColor = palette.cardStrong},
        {selectors = {"heroLookFrom"}, bgcolor = palette.info, color = palette.bg},
        {selectors = {"heroAppearStepNumber"}, bgcolor = palette.info, color = palette.bg},
        --an unnamed Hero: the card's name strip asks for a name in the
        --Builder's to-do colour, dashed like the other empty slots.
        {selectors = {"heroAppearNameStrip"}, border = 1, borderColor = "#00000000"},
        {selectors = {"heroAppearNameStrip", "heroAppearNameEmpty"}, borderColor = palette.info, borderStyle = "dashed"},
        {selectors = {"heroAppearNamePrompt"}, color = palette.info, opacity = 0.85},
        {selectors = {"heroAppearDragTag"}, hidden = 1},
        {selectors = {"heroAppearDragTag", "parent:hover"}, hidden = 0},
        --a follower with no portrait: a quiet square where it would be.
        {selectors = {"heroSheetFollowerPortrait"}, bgcolor = Lift(0.14)},
        --Narrow's Stats pane: the band without a plate of its own.
        {selectors = {"heroSheetBandPane"}, bgcolor = "clear", borderColor = "#00000000"},
        --a note's card opens its window: its edge lights on hover.
        {selectors = {"heroSheetFeatCard", "heroSheetNoteCard", "hoverable", "hover"}, borderColor = palette.cardSub},
        --the Downtime tab: status pills (gold when the
        --Director must act), the progress bar and its milestone notch, the roll
        --box in the warm label colour, a milestone's gold box, a finished
        --project's box, characteristic and language chips, the Breakthrough tag.
        {selectors = {"heroSheetDtPill"}, bgcolor = "clear", borderColor = palette.border, color = palette.cardSub},
        {selectors = {"heroSheetDtPill", "heroSheetDtActive"}, borderColor = Tint(palette.rawSuccess, 0.55), color = palette.cardSuccess},
        {selectors = {"heroSheetDtPill", "heroSheetDtPaused"}, borderColor = Tint(palette.rawWarning, 0.55), color = palette.cardWarning},
        {selectors = {"heroSheetDtPill", "heroSheetDtMilestone"}, bgcolor = palette.rawInfo, borderColor = palette.rawInfo, color = palette.bg},
        {selectors = {"heroSheetDtPill", "heroSheetDtComplete"}, borderColor = palette.cardStrong, color = palette.cardStrong},
        {selectors = {"heroSheetDtTrack"}, bgcolor = "#ffffff1a"},
        {selectors = {"heroSheetDtFill"}, bgcolor = palette.cardFg},
        {selectors = {"heroSheetDtNotch"}, bgcolor = "#000000ff", borderColor = palette.cardStrong},
        {selectors = {"heroSheetDtRollBox"}, bgcolor = Tint(palette.cardLabel, 0.06), borderColor = Tint(palette.cardLabel, 0.45)},
        {selectors = {"heroSheetDtGoldBox"}, bgcolor = Tint(palette.rawInfo, 0.1), borderColor = Tint(palette.rawInfo, 0.6)},
        {selectors = {"heroSheetDtDoneBox"}, bgcolor = "clear", borderColor = palette.cardStrong},
        {selectors = {"heroSheetDtChip"}, bgcolor = "clear", borderColor = Tint(palette.rawFg, 0.35), color = palette.cardFg},
        {selectors = {"heroSheetDtChip", "heroSheetDtBest"}, borderColor = palette.cardStrong, color = palette.cardStrong},
        {selectors = {"heroSheetDtChip", "heroSheetDtUnknown"}, borderColor = Tint(palette.rawWarning, 0.55)},
        {selectors = {"heroSheetDtBreakthrough"}, bgcolor = palette.rawInfo, color = palette.bg},
        --a value that cannot be edited here keeps its edge, unseen.
        {selectors = {"heroSheetDtNoEdit"}, borderColor = "#00000000"},
        --Roll as: dark words on the gold of a roll that can be made.
        {selectors = {"heroSheetDtRollText"}, color = palette.cardStrong},
        {selectors = {"heroSheetDtRollText", "parent:heroSheetLevelReady"}, color = palette.bg},
    }
    return HeroSheetTheme.SoundRules(rules)
end

--Sounds: the controls that act. Selecting a row or opening a hover card is
--not here, so it stays silent.
local ACTING_CONTROLS = {
    "heroSheetButton", "heroSheetSmallButton", "heroSheetPlateButton", "heroSheetIconButton",
    "heroSheetXButton", "heroSheetLevelButton", "heroSheetNeedButton", "heroSheetNeedClose",
    "heroSheetTitleAdd", "heroSheetSegment", "heroSheetListTabFrame", "heroSheetPopRow",
    "heroSheetKeb", "heroSheetCtrlPill", "heroSheetCheck", "heroSheetThumb",
    "heroBuilderPill", "heroBuilderCard", "heroSklChip", "heroSklAdd", "heroLookTile",
}
--What marks a control that refuses a press: dimmed anywhere, and the states
--a Builder card or a skill chip cannot be picked in.
local REFUSED_EVERYWHERE = {"heroSheetDisabled", "heroSheetOff"}
local REFUSED_BY_CONTROL = {
    heroBuilderCard = {"unavailable"},
    heroSklChip = {"heroSklKnown", "heroSklLocked", "heroSklUnav"},
}

--- Add the sound rules to a style list and return it: a control that acts
--- clicks when pressed (a pick too), and one that refuses the press plays
--- the error, beside the reason it already shows.
--- @param rules table[]
--- @return table[]
function HeroSheetTheme.SoundRules(rules)
    for _, class in ipairs(ACTING_CONTROLS) do
        local click = {class, "press"}
        local refused = {}
        for _, state in ipairs(REFUSED_EVERYWHERE) do
            refused[#refused+1] = state
        end
        for _, state in ipairs(REFUSED_BY_CONTROL[class] or {}) do
            refused[#refused+1] = state
        end
        for _, state in ipairs(refused) do
            click[#click+1] = "~" .. state
            rules[#rules+1] = {selectors = {class, state, "press"}, soundEvent = "UI.Error_Generic"}
        end
        if class == "heroSheetButton" then
            --a Builder Finish plays the lock-in sound instead of clicking.
            click[#click+1] = "~heroBuilderLockIn"
            rules[#rules+1] = {selectors = {class, "heroBuilderLockIn", "press", "~heroSheetDisabled"}, soundEvent = "Notify.LockIn"}
        end
        rules[#rules+1] = {selectors = click, soundEvent = "Mouse.Click"}
    end
    return rules
end

--The root styles compiled (gui.Style) for the palette and see-through they
--were made from. The engine compiles a plain style table on every panel
--that takes it, which is slow for these ~600 rules on each window, pop-up
--and hover card; compiled ones are passed as they are.
--- @type {key: nil|string, styles: nil|table}
local g_rootStyles = {key = nil, styles = nil}

--- The styles a window or pop-up root takes: the theme with the sheet's
--- rules on top (one GetStyles per surface, as the theme guide asks),
--- compiled once and shared. Never add to the list it returns.
--- @return table
function HeroSheetTheme.RootStyles()
    local key = dmhub.ToJson(HeroSheetTheme.Palette()) .. "|" .. tostring(HeroSheetTheme.SeeThrough())
    if g_rootStyles.key ~= key or g_rootStyles.styles == nil then
        local compiled = {}
        for i, style in ipairs(ThemeEngine.MergeStyles(HeroSheetTheme.Rules())) do
            if type(style) == "table" then
                compiled[i] = gui.Style(style)
            else
                compiled[i] = style
            end
        end
        g_rootStyles = {key = key, styles = compiled}
    end
    return g_rootStyles.styles
end

--Live roots (windows, pop-ups) to re-style when the scheme changes. Held
--strongly (a weakly held panel handle is collected while the panel is
--still showing); each new root and each scheme change sweep out destroyed
--ones, so closed pop-ups do not pile up.
--- @type table<Panel, fun(panel: Panel)>
local g_roots = {}

--- True while a tracked panel still exists. A destroyed panel's userdata
--- errors on any read, even .valid.
--- @param panel Panel
--- @return boolean
local function RootAlive(panel)
    local ok, valid = pcall(function() return panel.valid end)
    return ok and valid == true
end

--- Register a root to re-style on a scheme or accessibility change; fn
--- re-applies its styles (it receives the panel).
--- @param panel Panel
--- @param fn fun(panel: Panel)
function HeroSheetTheme.Track(panel, fn)
    local dead = {}
    for root, _ in pairs(g_roots) do
        if not RootAlive(root) then
            dead[#dead+1] = root
        end
    end
    for _, root in ipairs(dead) do
        g_roots[root] = nil
    end
    g_roots[panel] = fn
end

local g_themeHandler = rawget(_G, "g_heroSheetThemeHandler")
if g_themeHandler ~= nil then
    pcall(function() g_themeHandler.Deregister() end)
end
g_heroSheetThemeHandler = ThemeEngine.OnThemeChanged(mod, function()
    --the theme under the sheet's rules changed: compile them again.
    g_rootStyles.key = nil
    local dead = {}
    for panel, fn in pairs(g_roots) do
        if RootAlive(panel) then
            fn(panel)
            --new styles alone do not repaint what is drawn: a class toggle does.
            panel:SetClassTree("heroSheetThemeTick", not panel:HasClass("heroSheetThemeTick"))
        else
            dead[#dead+1] = panel
        end
    end
    for _, panel in ipairs(dead) do
        g_roots[panel] = nil
    end
    --text that carries a colour in its markup (skill groups, sources, the
    --titles line) is redrawn: those blocks put the colour in their signature.
    --only colours changed, so the Hero is not read again.
    local refresh = rawget(_G, "HeroSheetRefresh")
    if refresh ~= nil then
        refresh.Recheck()
    end
end)

----------------------------------------------------------------------
--Hover cards: a card appears after a deliberate hover (0.4 s), click
--pins it (click elsewhere, Esc or its x closes it). An element whose click
--does something else keeps the hover card and does not pin.

--- Wire a hover card on an element's args: hover shows build() after the
--- wait; with pin, click pins it. Returns the args for chaining. build gets
--- the element too, so a pinned editor can rebuild itself after a change
--- (set element.popup to nil, then fire "click" on the element).
--- @param args table the element's gui args
--- @param build fun(pinned: boolean, close: fun(), element: Panel): nil|Panel nil shows no card
--- @param pin nil|boolean default true
--- @param placement nil|{halign: string, valign: string} where the pinned card sits against the element (the engine's popup placement)
--- @return table
function HeroSheetTheme.HoverCard(args, build, pin, placement)
    local hover, dehover, click = args.hover, args.dehover, args.click
    local heroChanged = args.heroSheetHero
    args.data = args.data or {}
    --another Hero in the kept sheet: a card showing the last one closes, and
    --one still waiting to show never does.
    args.heroSheetHero = function(element, newToken)
        element.data.cardGen = (element.data.cardGen or 0) + 1
        element.tooltip = nil
        element.popup = nil
        if heroChanged ~= nil then
            heroChanged(element, newToken)
        end
    end
    args.hover = function(element)
        element.data.cardGen = (element.data.cardGen or 0) + 1
        element.data.cardHover = true
        local gen = element.data.cardGen
        dmhub.Schedule(HeroSheetTheme.HOVER_DELAY, function()
            if mod.unloaded or not element.valid or element.data.cardGen ~= gen or not element.data.cardHover then
                return
            end
            --a pinned card is already showing: no second copy over it.
            if element.popup ~= nil then
                return
            end
            element.tooltip = build(false, function() end, element)
        end)
        if hover ~= nil then
            hover(element)
        end
    end
    args.dehover = function(element)
        element.data.cardHover = false
        element.data.cardGen = (element.data.cardGen or 0) + 1
        element.tooltip = nil
        if dehover ~= nil then
            dehover(element)
        end
    end
    if pin ~= false and click == nil then
        args.click = function(element)
            element.data.cardGen = (element.data.cardGen or 0) + 1
            element.tooltip = nil
            local function close()
                if element.valid then
                    element.popup = nil
                end
            end
            element.popupPositioning = "panel"
            element.popup = gui.Panel{
                width = "auto",
                height = "auto",
                halign = placement ~= nil and placement.halign or nil,
                valign = placement ~= nil and placement.valign or nil,
                --Esc closes the pinned card before anything else on the sheet.
                captureEscape = true,
                escapePriority = EscapePriority.DMHUB_POPUP,
                escape = function()
                    close()
                end,
                build(true, close, element),
            }
        end
    end
    return args
end

--- A hover or pinned card's frame: a solid card with the content. A pinned
--- card has a light edge, twice as thick, and an x button.
--- @param content Panel
--- @param pinned boolean
--- @param close fun()
--- @param flush nil|boolean the content brings its own padding (the codex's ability card, whose title band meets the edge)
--- @return Panel
function HeroSheetTheme.CardFrame(content, pinned, close, flush)
    local children = {content}
    if pinned then
        --on a flush card the x sits inside the card's coloured title band, on
        --a dark square, not over the card's rounded edge.
        children[#children+1] = gui.Panel{
            classes = {"heroSheetIconButton", "hoverable"},
            floating = true,
            halign = "right",
            valign = "top",
            width = 26,
            height = 26,
            tmargin = cond(flush, 10, 0),
            rmargin = cond(flush, 10, 0),
            bgcolor = cond(flush, "#00000059", nil),
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 6,
            click = function()
                close()
            end,
            gui.Panel{
                width = 12,
                height = 12,
                halign = "center",
                valign = "center",
                interactable = false,
                bgimage = "window-chrome/chrome-close.png",
                bgcolor = HeroSheetTheme.Palette().fg,
            },
        }
    end
    --the colours are set on the panel as well as by the rules: a new popup's
    --first frame is drawn before its rules apply, and would show see-through.
    local palette = HeroSheetTheme.Palette()
    return gui.Panel{
        classes = {"heroSheetCard", cond(pinned, "heroSheetCardPinned", nil)},
        styles = HeroSheetTheme.RootStyles(),
        bgimage = "panels/square.png",
        bgcolor = palette.plate,
        borderColor = cond(pinned, palette.cardStrong, palette.border),
        border = cond(pinned, 2, 1),
        cornerRadius = 10,
        --padding: 14 above, 16 a side, 12 below.
        hpad = cond(flush, 0, 16),
        tpad = cond(flush, 0, 14),
        bpad = cond(flush, 6, 12),
        borderBox = true,
        width = "auto",
        height = "auto",
        flow = "vertical",
        children = children,
    }
end

----------------------------------------------------------------------
--Cut-off text: a label cut off by its column shows its full
--text on a deliberate hover; one that fits shows nothing.

--- A single-line label that ends in an ellipsis when it does not fit and
--- then shows its full text as a tooltip.
--- @param args table gui.Label args (text, width, fontSize, classes...)
--- @return Panel
function HeroSheetTheme.EllipsisLabel(args)
    args.textWrap = false
    args.textOverflow = "ellipsis"
    local linger = args.linger
    args.linger = function(element)
        --preferred width is the whole text's width.
        local ok, size = pcall(function() return element:CalculatePreferredSize() end)
        if ok and size ~= nil and size.x > element.renderedWidth + 0.5 then
            gui.Tooltip(element.text)(element)
        elseif linger ~= nil then
            linger(element)
        end
    end
    return gui.Label(args)
end

----------------------------------------------------------------------
--The dotted underline under session numbers: the sign that a number can
--be clicked to type a new one.

--Dots are this far apart, in sheet units.
local DOT_PITCH = 3

--About how wide a text is in sheet units (digits and plain text run near
--half the font size per character).
--- @param text string
--- @param fontSize number
--- @return number
function HeroSheetTheme.TextWidth(text, fontSize)
    return #text * fontSize * 0.55
end

--- A row of dots for under a text about this wide; SetDots resizes it when
--- the text changes.
--- @param width number sheet units
--- @param args nil|table extra panel fields (floating, halign, valign, margins)
--- @return Panel
function HeroSheetTheme.DottedUnderline(width, args)
    local fields = {
        width = "auto",
        height = 1.5,
        flow = "horizontal",
        interactable = false,
    }
    for field, value in pairs(args or {}) do
        fields[field] = value
    end
    local row = gui.Panel(fields)
    HeroSheetTheme.SetDots(row, width)
    return row
end

--- Give a dotted underline enough dots for a text this wide.
--- @param row Panel from DottedUnderline
--- @param width number sheet units
function HeroSheetTheme.SetDots(row, width)
    local count = math.max(2, math.floor(width / DOT_PITCH))
    if #row.children == count then
        return
    end
    local dots = {}
    for i = 1, count do
        dots[i] = gui.Panel{
            classes = {"heroSheetDot"},
            bgimage = "panels/square.png",
            width = 1.5,
            height = 1.5,
            rmargin = DOT_PITCH - 1.5,
            interactable = false,
        }
    end
    row.children = dots
end

----------------------------------------------------------------------
--Session numbers: one editing language for every counter the sheet shows
--(hero tokens, Victories, the heroic resource, surges): click the number to
--type a new one; Enter or clicking away applies it, Esc cancels. There are
--no + and - buttons on hover.

--- @class HeroSheetClickNumberArgs
--- @field get fun(): number the value shown
--- @field set fun(value: number) saves a typed value (already a whole number, at least min)
--- @field min nil|number|fun(): number lowest value accepted (default 0; -math.huge for no floor); a function when it follows the Hero shown
--- @field canEdit nil|fun(): boolean false shows the number only (view only)
--- @field fontSize nil|number
--- @field classes nil|string[] the number's label classes (default heroSheetText)
--- @field tooltip nil|string|fun(): nil|string what the number is, shown on hover; a function when it follows the Hero shown
--- @field snug nil|boolean a field only as wide as the value, for a number inside a line of text

--- A number that turns into a field when clicked. Fire "refreshNumber" on
--- it (or its tree) to show the current value again.
--- @param args HeroSheetClickNumberArgs
--- @return Panel
function HeroSheetTheme.ClickNumber(args)
    local fontSize = args.fontSize or 18
    local function Min()
        local min = args.min
        if type(min) == "function" then
            return min()
        end
        return min or 0
    end
    local label
    local input
    local focused = false

    local function CanEdit()
        return args.canEdit == nil or args.canEdit()
    end

    --the dotted underline, under the number's text (not its 24-unit box).
    local dots = HeroSheetTheme.DottedUnderline(HeroSheetTheme.TextWidth("0", fontSize), {
        floating = true,
        halign = "center",
        valign = "bottom",
    })

    local function Show()
        local ok, value = pcall(args.get)
        label.text = ok and tostring(value) or "-"
        HeroSheetTheme.SetDots(dots, HeroSheetTheme.TextWidth(label.text, fontSize))
        dots:SetClass("collapsed", not CanEdit())
    end

    local function Close()
        focused = false
        input.captureEscape = false
        input:SetClass("collapsed", true)
        label:SetClass("heroSheetHush", false)
        Show()
    end

    --Enter or a click away applies what was typed and closes the field; an
    --unchanged value saves nothing. Called from change, defocus and submit,
    --whichever comes first (change does not fire when nothing was typed).
    --- @param text string
    local function Apply(text)
        if not focused then
            return
        end
        local typed = tonumber(text)
        Close()
        --let go of the keyboard first (a block holding it waits to redraw),
        --unless a click away already gave it to another field. After Enter
        --the field no longer has the keyboard but is still the focus on
        --record, and a field left that way cannot be focused again.
        if input.hasInputFocus or gui.GetFocus() == input then
            gui.SetFocus(nil)
        end
        if typed ~= nil then
            typed = math.floor(typed)
            local ok, current = pcall(args.get)
            if typed >= Min() and not (ok and current == typed) then
                args.set(typed)
            end
        end
        Show()
    end

    label = gui.Label{
        classes = args.classes or {"heroSheetText"},
        width = "auto",
        height = "auto",
        minWidth = 24,
        minHeight = 24,
        fontSize = fontSize,
        bold = true,
        textAlignment = "center",
        valign = "center",
        create = function(element)
            Show()
        end,
        linger = function(element)
            local tooltip = args.tooltip
            if type(tooltip) == "function" then
                tooltip = tooltip()
            end
            if tooltip ~= nil then
                gui.Tooltip(tooltip)(element)
            end
        end,
        click = function(element)
            if not CanEdit() then
                return
            end
            --a counter is a control that acts, so it clicks; its classes are
            --the caller's, so the sound rules cannot do it.
            audio.FireSoundEvent("Mouse.Click")
            input.text = element.text
            --as wide as the value with room for one more digit.
            if args.snug then
                input.selfStyle.width = math.floor(math.max(2, #element.text) * fontSize * 0.62) + 4
            else
                input.selfStyle.width = math.floor(math.max(2, #element.text + 1) * fontSize * 0.62) + 10
            end
            label:SetClass("heroSheetHush", true)
            dots:SetClass("collapsed", true)
            input:SetClass("collapsed", false)
            input.captureEscape = true
            --focus a frame later: the field is still collapsed until then.
            dmhub.Schedule(0.01, function()
                if mod.unloaded or not input.valid then
                    return
                end
                gui.SetFocus(input)
            end)
        end,
    }

    input = gui.Input{
        classes = {"heroSheetNumberInput", "collapsed"},
        floating = true,
        width = 36,
        height = fontSize + 6,
        fontSize = fontSize,
        halign = "center",
        valign = "center",
        characterLimit = 4,
        selectAllOnFocus = true,
        placeholderText = "",
        captureEscape = false,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            Close()
            gui.SetFocus(nil)
        end,
        focus = function(element)
            focused = true
        end,
        change = function(element)
            Apply(element.text)
        end,
        defocus = function(element)
            Apply(element.text)
        end,
        submit = function(element)
            Apply(element.text)
        end,
    }

    return gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        valign = "center",
        refreshNumber = function(element)
            if not focused then
                Show()
            end
        end,
        label,
        input,
        dots,
    }
end

----------------------------------------------------------------------
--Window buttons: a window that saves as you go has Done only; one
--that commits a change has Cancel and Save. Never a header Done beside them.

--- @class HeroSheetButtonsArgs
--- @field onDone nil|fun() a save-as-you-go window: one Done button
--- @field onCancel nil|fun() a commit window: Cancel...
--- @field onSave nil|fun() ...and Save
--- @field saveText nil|string Save's words when the window commits something else ("Delete")
--- @field note nil|string muted words before the buttons ("Saved as you type.")

--- A sheet window's footer button, sized to its words; a main one (Save,
--- Done) has the cream edge.
--- @param text string
--- @param fn fun()
--- @param primary boolean
--- @return Panel
function HeroSheetTheme.WindowButton(text, fn, primary)
    local frameClasses = {"heroSheetButton", "heroSheetSolid", "hoverable"}
    local labelClasses = {"heroSheetButtonLabel"}
    if primary then
        frameClasses[#frameClasses+1] = "heroSheetPrimary"
        labelClasses[#labelClasses+1] = "heroSheetPrimary"
    end
    return gui.Panel{
        classes = frameClasses,
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = HeroSheetWindow.TargetSize(36),
        minWidth = HeroSheetWindow.TargetSize(24),
        hpad = 14,
        borderBox = true,
        lmargin = 10,
        valign = "center",
        --a dimmed button says why on hover: set data.tip ("Type a name to start.").
        data = {},
        hover = function(element)
            if element.data.tip ~= nil then
                gui.Tooltip(element.data.tip)(element)
            end
        end,
        click = function()
            fn()
        end,
        gui.Label{
            classes = labelClasses,
            text = text,
            width = "auto",
            height = "auto",
            fontSize = 14,
            halign = "center",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
end

--- The footer row of a sheet window: its buttons, sized to their text, at
--- the right; Save (or Done) has the cream edge of a main button.
--- @param args HeroSheetButtonsArgs
--- @return Panel
function HeroSheetTheme.WindowButtons(args)
    local buttons = {}
    if args.note ~= nil then
        buttons[#buttons+1] = gui.Label{
            classes = {"heroSheetCardSub"},
            text = args.note,
            fontSize = 12,
            italics = true,
            width = "auto",
            height = "auto",
            rmargin = 4,
            valign = "center",
            textWrap = false,
        }
    end
    if args.onSave ~= nil then
        buttons[#buttons+1] = HeroSheetTheme.WindowButton("Cancel", args.onCancel or function() end, false)
        buttons[#buttons+1] = HeroSheetTheme.WindowButton(args.saveText or "Save", args.onSave, true)
    else
        buttons[#buttons+1] = HeroSheetTheme.WindowButton("Done", args.onDone or function() end, true)
    end
    return gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        valign = "center",
        children = buttons,
    }
end
