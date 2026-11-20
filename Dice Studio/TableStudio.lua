local mod = dmhub.GetModLoading()

--The Table Studio panel (TABLE_STUDIO_PLAN.md): authors tabletop backgrounds as data -- one of the
--seven table shaders, its textures, its settings and a layout -- previewed live on the real table
--while the panel is open. The engine side is TableStudio.cs: the tablestudio global, set only for
--admin accounts (nil for everyone else, and in engine builds without it), so for anyone else this
--file registers nothing. Phase 1a: tables live in local files; nothing here reaches players.

local studio = tablestudio
if studio == nil then
    return
end

local T = UIText.T

--The open panel's root (nil when closed), so the MCP bridge can reach it while testing, as
--the Dice Studio's RefreshDiceStudioInterface does.
--- @type Panel|nil
g_tableStudioRoot = nil

--Each type's hand-written controls. kinds:
--  float  a number setting (prop, min, max)
--  vec    one component of a vector setting (prop, index 1..4, min, max): shaders pack several
--         knobs into one vector
--  color  a colour setting (prop)
--  ramp   one end of a four-stop colour ramp kept in linear light (stops, which = "cool"/"hot")
--  axis   Gold Marble's vein colour: which way the gold mask reads colour (prop)
--Every entry has the text key of its label.
local g_types = {
    playmat = {
        textures = { _MainTex = "tablestudio.tex.leather" },
        logo = {
            {kind = "float", prop = "_GrainOnLogo", min = 0, max = 1, key = "tablestudio.playmat.grainonlogo"},
        },
        look = {
            {kind = "float", prop = "_Vignette", min = 0, max = 1, key = "tablestudio.vignette"},
        },
    },
    marble = {
        textures = { _MainTex = "tablestudio.tex.stone" },
        logo = {
            {kind = "color", prop = "_CutTint", key = "tablestudio.marble.cuttint"},
            {kind = "float", prop = "_CutFrost", min = 0, max = 1, key = "tablestudio.marble.cutfrost"},
            {kind = "float", prop = "_CutLift", min = 0, max = 0.3, key = "tablestudio.marble.cutlift"},
            {kind = "float", prop = "_CutBrightness", min = 0.5, max = 1.5, key = "tablestudio.marble.cutbrightness"},
            {kind = "float", prop = "_CutAO", min = 0, max = 1, key = "tablestudio.marble.cutdepth"},
            {kind = "float", prop = "_CutShadow", min = 0, max = 1, key = "tablestudio.marble.cutshadow"},
        },
        look = {
            {kind = "float", prop = "_Sheen", min = 0, max = 0.3, key = "tablestudio.marble.sheen"},
            {kind = "float", prop = "_Gloss", min = 0, max = 0.1, key = "tablestudio.marble.gloss"},
            {kind = "float", prop = "_ReflectStrength", min = 0, max = 1, key = "tablestudio.reflection"},
            {kind = "float", prop = "_ReflectDarken", min = 0, max = 1, key = "tablestudio.marble.reflectdarken"},
            {kind = "float", prop = "_Vignette", min = 0, max = 1, key = "tablestudio.vignette"},
        },
    },
    goldmarble = {
        textures = { _MainTex = "tablestudio.tex.stone" },
        logo = {
            {kind = "color", prop = "_GoldLeaf", key = "tablestudio.gold.leaf"},
            {kind = "float", prop = "_LeafAO", min = 0, max = 1, key = "tablestudio.gold.leafdepth"},
        },
        look = {
            {kind = "axis", prop = "_GoldAxis", key = "tablestudio.gold.veincolor"},
            {kind = "vec", prop = "_GoldMask", index = 1, min = 0, max = 0.5, key = "tablestudio.gold.veinfrom"},
            {kind = "vec", prop = "_GoldMask", index = 2, min = 0, max = 1, key = "tablestudio.gold.veinto"},
            {kind = "float", prop = "_Sheen", min = 0, max = 0.3, key = "tablestudio.marble.sheen"},
            {kind = "color", prop = "_GlintColor", key = "tablestudio.gold.glintcolor"},
            {kind = "float", prop = "_GlintPeriod", min = 4, max = 60, key = "tablestudio.gold.glintevery"},
            {kind = "float", prop = "_GlintTravel", min = 0.5, max = 10, key = "tablestudio.gold.glinttravel"},
            {kind = "float", prop = "_GlintWidth", min = 0.01, max = 0.5, key = "tablestudio.gold.glintwidth"},
            {kind = "float", prop = "_GlintGold", min = 0, max = 3, key = "tablestudio.gold.glintgold"},
            {kind = "float", prop = "_GlintStone", min = 0, max = 0.3, key = "tablestudio.gold.glintstone"},
            {kind = "vec", prop = "_Sparkles", index = 1, min = 10, max = 120, key = "tablestudio.gold.sparkledensity"},
            {kind = "vec", prop = "_Sparkles", index = 2, min = 0, max = 1, key = "tablestudio.gold.sparkleamount"},
            {kind = "vec", prop = "_Sparkles", index = 3, min = 0.5, max = 3, key = "tablestudio.gold.sparklesize"},
            {kind = "vec", prop = "_Sparkles", index = 4, min = 0, max = 4, key = "tablestudio.gold.sparklebrightness"},
            {kind = "float", prop = "_ReflectStrength", min = 0, max = 1, key = "tablestudio.reflection"},
            {kind = "float", prop = "_ReflectGold", min = 0, max = 2, key = "tablestudio.gold.reflectgold"},
            {kind = "float", prop = "_ReflectDarken", min = 0, max = 1, key = "tablestudio.marble.reflectdarken"},
            {kind = "float", prop = "_Vignette", min = 0, max = 1, key = "tablestudio.vignette"},
        },
    },
    starfield = {
        textures = { _MainTex = "tablestudio.tex.nebula" },
        logo = {
            {kind = "color", prop = "_LogoFill", key = "tablestudio.stars.logofill"},
            {kind = "float", prop = "_HaloStrength", min = 0, max = 2, key = "tablestudio.halo"},
        },
        look = {
            {kind = "float", prop = "_NebulaBrightness", min = 0, max = 2, key = "tablestudio.stars.nebulabrightness"},
            {kind = "float", prop = "_NebulaDrift", min = 0, max = 0.002, key = "tablestudio.stars.nebuladrift"},
            {kind = "vec", prop = "_DeepStars", index = 2, min = 0, max = 1, key = "tablestudio.stars.deepamount"},
            {kind = "vec", prop = "_DeepStars", index = 3, min = 0.3, max = 3, key = "tablestudio.stars.deepsize"},
            {kind = "vec", prop = "_DeepStars", index = 4, min = 0, max = 3, key = "tablestudio.stars.deepbrightness"},
            {kind = "color", prop = "_DeepColor", key = "tablestudio.stars.deepcolor"},
            {kind = "vec", prop = "_MidStars", index = 2, min = 0, max = 1, key = "tablestudio.stars.midamount"},
            {kind = "vec", prop = "_MidStars", index = 3, min = 0.3, max = 3, key = "tablestudio.stars.midsize"},
            {kind = "vec", prop = "_MidStars", index = 4, min = 0, max = 3, key = "tablestudio.stars.midbrightness"},
            {kind = "color", prop = "_MidColor", key = "tablestudio.stars.midcolor"},
            {kind = "vec", prop = "_NearStars", index = 2, min = 0, max = 1, key = "tablestudio.stars.nearamount"},
            {kind = "vec", prop = "_NearStars", index = 3, min = 0.3, max = 3, key = "tablestudio.stars.nearsize"},
            {kind = "vec", prop = "_NearStars", index = 4, min = 0, max = 3, key = "tablestudio.stars.nearbrightness"},
            {kind = "color", prop = "_NearColor", key = "tablestudio.stars.nearcolor"},
            {kind = "float", prop = "_TwinkleSpeed", min = 0, max = 8, key = "tablestudio.stars.twinklespeed"},
            {kind = "float", prop = "_TwinkleAmount", min = 0, max = 1, key = "tablestudio.stars.twinkleamount"},
            {kind = "float", prop = "_StarGlow", min = 0, max = 1, key = "tablestudio.stars.starglow"},
            {kind = "float", prop = "_Vignette", min = 0, max = 1, key = "tablestudio.vignette"},
        },
    },
    spectral = {
        textures = { _MainTex = "tablestudio.tex.fog" },
        logo = {
            {kind = "color", prop = "_LetterColor", key = "tablestudio.spectral.letter"},
            {kind = "color", prop = "_RimColor", key = "tablestudio.spectral.rim"},
            {kind = "float", prop = "_LetterOpacity", min = 0, max = 1, key = "tablestudio.spectral.letteropacity"},
            {kind = "color", prop = "_HaloColor", key = "tablestudio.spectral.halocolor"},
            {kind = "float", prop = "_HaloStrength", min = 0, max = 2, key = "tablestudio.halo"},
        },
        look = {
            {kind = "color", prop = "_Deep", key = "tablestudio.spectral.deep"},
            {kind = "color", prop = "_FogColor", key = "tablestudio.spectral.fogcolor"},
            {kind = "color", prop = "_WispColor", key = "tablestudio.spectral.wisps"},
            {kind = "vec", prop = "_FogScale", index = 1, min = 0.1, max = 2, key = "tablestudio.spectral.fogscale"},
            {kind = "vec", prop = "_Souls", index = 2, min = 0, max = 1, key = "tablestudio.spectral.souls"},
            {kind = "vec", prop = "_Souls", index = 3, min = 0.3, max = 4, key = "tablestudio.spectral.soulsize"},
            {kind = "vec", prop = "_Souls", index = 4, min = 0, max = 2, key = "tablestudio.spectral.soulbrightness"},
            {kind = "color", prop = "_SoulColor", key = "tablestudio.spectral.soulcolor"},
            {kind = "float", prop = "_SoulRise", min = 0, max = 0.05, key = "tablestudio.spectral.soulrise"},
            {kind = "color", prop = "_PulseColor", key = "tablestudio.spectral.pulsecolor"},
            {kind = "float", prop = "_PulsePeriod", min = 4, max = 60, key = "tablestudio.spectral.pulseevery"},
            {kind = "float", prop = "_PulseWidth", min = 0.005, max = 0.2, key = "tablestudio.spectral.pulsewidth"},
            {kind = "float", prop = "_PulseStrength", min = 0, max = 1, key = "tablestudio.spectral.pulsestrength"},
            {kind = "float", prop = "_Vignette", min = 0, max = 1, key = "tablestudio.vignette"},
        },
    },
    steel = {
        textures = { _MainTex = "tablestudio.tex.steel" },
        logo = {
            {kind = "float", prop = "_CutContrast", min = 0, max = 3, key = "tablestudio.steel.cutcontrast"},
            {kind = "float", prop = "_CutDark", min = 0, max = 1, key = "tablestudio.steel.cutdepth"},
            {kind = "color", prop = "_HaloColor", key = "tablestudio.steel.halocolor"},
            {kind = "float", prop = "_HaloStrength", min = 0, max = 2, key = "tablestudio.halo"},
        },
        look = {
            {kind = "ramp", stops = {"_Forge0", "_Forge1", "_Forge2", "_Forge3"}, which = "cool", key = "tablestudio.steel.forgecool"},
            {kind = "ramp", stops = {"_Forge0", "_Forge1", "_Forge2", "_Forge3"}, which = "hot", key = "tablestudio.steel.forgehot"},
            {kind = "float", prop = "_HeatPeriod", min = 4, max = 60, key = "tablestudio.steel.forgeevery"},
            {kind = "float", prop = "_HeatBrightness", min = 0, max = 3, key = "tablestudio.steel.heatbrightness"},
            {kind = "float", prop = "_SheenBroad", min = 0, max = 0.3, key = "tablestudio.steel.sheenbroad"},
            {kind = "float", prop = "_SheenCore", min = 0, max = 0.5, key = "tablestudio.steel.sheencore"},
            {kind = "float", prop = "_SheenWidth", min = 0.05, max = 2, key = "tablestudio.steel.sheenwidth"},
            {kind = "float", prop = "_SheenDrift", min = 0, max = 0.5, key = "tablestudio.steel.sheendrift"},
            {kind = "float", prop = "_SheenFollow", min = 0, max = 1, key = "tablestudio.steel.sheenfollow"},
            {kind = "float", prop = "_ReflectStrength", min = 0, max = 1, key = "tablestudio.reflection"},
            {kind = "float", prop = "_ReflectStretch", min = 0, max = 0.05, key = "tablestudio.steel.reflectstretch"},
            {kind = "float", prop = "_Vignette", min = 0, max = 1, key = "tablestudio.vignette"},
        },
    },
    obsidian = {
        textures = { _MainTex = "tablestudio.tex.stone", _HeatTex = "tablestudio.tex.heat" },
        logo = {
            {kind = "float", prop = "_LogoBrightness", min = 0, max = 2, key = "tablestudio.logobrightness"},
            {kind = "float", prop = "_HaloStrength", min = 0, max = 2, key = "tablestudio.halo"},
        },
        look = {
            {kind = "float", prop = "_CrackBrightness", min = 0, max = 3, key = "tablestudio.obsidian.cracks"},
            {kind = "ramp", stops = {"_Lava0", "_Lava1", "_Lava2", "_Lava3"}, which = "cool", key = "tablestudio.obsidian.lavacool"},
            {kind = "ramp", stops = {"_Lava0", "_Lava1", "_Lava2", "_Lava3"}, which = "hot", key = "tablestudio.obsidian.lavahot"},
            {kind = "float", prop = "_GlowAmount", min = 0, max = 0.5, key = "tablestudio.obsidian.glow"},
            {kind = "color", prop = "_GlowColor", key = "tablestudio.obsidian.glowcolor"},
            {kind = "float", prop = "_FlickerMin", min = 0, max = 1, key = "tablestudio.obsidian.flicker"},
            {kind = "vec", prop = "_Shimmer", index = 3, min = 0, max = 1, key = "tablestudio.obsidian.shimmer"},
            {kind = "vec", prop = "_Embers", index = 2, min = 0, max = 1, key = "tablestudio.obsidian.embers"},
            {kind = "float", prop = "_EmberRise", min = 0, max = 0.1, key = "tablestudio.obsidian.emberrise"},
            {kind = "float", prop = "_ReflectStrength", min = 0, max = 1, key = "tablestudio.reflection"},
            {kind = "float", prop = "_Vignette", min = 0, max = 1, key = "tablestudio.vignette"},
        },
    },
}

local g_typeKeys = {
    playmat = "tablestudio.type.playmat",
    marble = "tablestudio.type.marble",
    goldmarble = "tablestudio.type.goldmarble",
    starfield = "tablestudio.type.starfield",
    spectral = "tablestudio.type.spectral",
    steel = "tablestudio.type.steel",
    obsidian = "tablestudio.type.obsidian",
}

--The layout's sliders. Tile size and offset only mean something for types that tile.
local g_layoutFields = {
    {kind = "layout", name = "tileSize", min = 0.5, max = 4, key = "tablestudio.tilesize"},
    {kind = "layout", name = "offsetX", min = -0.5, max = 0.5, key = "tablestudio.offsetx"},
    {kind = "layout", name = "offsetY", min = -0.5, max = 0.5, key = "tablestudio.offsety"},
}

----------------------------------------------------------------------
--Reading and writing a control's value.

local function FieldGet(f)
    if f.kind == "vec" then
        return studio:GetVectorComponent(f.prop, f.index)
    elseif f.kind == "layout" then
        return studio:GetLayout()[f.name] or 0
    end
    return studio:GetFloat(f.prop)
end

local function FieldDefault(f)
    if f.kind == "vec" then
        return studio:GetDefaultVectorComponent(f.prop, f.index)
    elseif f.kind == "layout" then
        return studio:GetDefaultLayout()[f.name] or 0
    end
    return studio:GetDefaultFloat(f.prop)
end

local function FieldSet(f, value)
    if f.kind == "vec" then
        studio:SetVectorComponent(f.prop, f.index, value)
    elseif f.kind == "layout" then
        studio:SetLayout{ [f.name] = value }
    else
        studio:SetFloat(f.prop, value)
    end
end

--Two to four decimals for small ranges, whole numbers for big ones.
local function FormatValue(f, value)
    local range = f.max - f.min
    if range < 0.05 then
        return string.format("%.4f", value)
    elseif range < 0.5 then
        return string.format("%.3f", value)
    elseif range < 2.5 then
        return string.format("%.2f", value)
    elseif range < 20 then
        return string.format("%.1f", value)
    end
    return string.format("%.0f", value)
end

--A ramp's two ends. The cool end sets stops 1 and 2 (the dark start follows the cool colour at
--an eighth of its strength, as the shipped ramps do), the hot end stop 4; stop 3 sits between
--them. Untouched ramps keep their exact shipped stops.
local function RampProp(f)
    return f.which == "cool" and f.stops[2] or f.stops[4]
end

local function SetRampMiddle(f)
    for i = 1, 3 do
        local a = studio:GetVectorComponent(f.stops[2], i)
        local b = studio:GetVectorComponent(f.stops[4], i)
        studio:SetVectorComponent(f.stops[3], i, a + (b - a) * 0.35)
    end
end

local function SetRamp(f, color)
    studio:SetLinearColor(RampProp(f), color)
    if f.which == "cool" then
        for i = 1, 3 do
            studio:SetVectorComponent(f.stops[1], i, studio:GetVectorComponent(f.stops[2], i) * 0.125)
        end
    end
    SetRampMiddle(f)
end

local function ResetVector(prop)
    for i = 1, 4 do
        studio:SetVectorComponent(prop, i, studio:GetDefaultVectorComponent(prop, i))
    end
end

local function VectorIsDefault(prop)
    for i = 1, 4 do
        if math.abs(studio:GetVectorComponent(prop, i) - studio:GetDefaultVectorComponent(prop, i)) > 0.00001 then
            return false
        end
    end
    return true
end

local function ResetRamp(f)
    if f.which == "cool" then
        ResetVector(f.stops[1])
        ResetVector(f.stops[2])
    else
        ResetVector(f.stops[4])
    end
    local other = f.which == "cool" and f.stops[4] or f.stops[2]
    if VectorIsDefault(other) then
        ResetVector(f.stops[3])
    else
        SetRampMiddle(f)
    end
end

--Gold Marble's vein colour: the gold mask reads dot(colour, axis), red minus blue by default.
--A picked colour points the axis toward that colour, at the default axis's strength.
local function AxisColor(f)
    local function c(i)
        return math.max(0, math.min(1, 0.55 + 0.3 * studio:GetVectorComponent(f.prop, i)))
    end
    return core.Color{ r = c(1), g = c(2), b = c(3) }
end

local function SetAxis(f, color)
    local r, g, b = color.r ^ 2.2, color.g ^ 2.2, color.b ^ 2.2
    local mean = (r + g + b) / 3
    local x, y, z = r - mean, g - mean, b - mean
    local len = math.sqrt(x * x + y * y + z * z)
    if len < 0.001 then
        return
    end
    local k = math.sqrt(2) / len
    studio:SetVectorComponent(f.prop, 1, x * k)
    studio:SetVectorComponent(f.prop, 2, y * k)
    studio:SetVectorComponent(f.prop, 3, z * k)
end

----------------------------------------------------------------------
--Styles: the panel style guide's grammar (STYLE_GUIDE.md), as in the approved mockup.

local SLIDER_WIDTH = 150

local function BuildStyles()
    return {
        {
            selectors = {"tsRow"},
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = "100%",
            height = 34,
            hpad = 12,
            borderBox = true,
            halign = "left",
            valign = "top",
        },
        {
            selectors = {"tsRow", "hover"},
            bgcolor = "@bgAlt",
            transitionTime = 0.1,
        },
        {
            selectors = {"tsRow", "tall"},
            height = 56,
        },
        {
            selectors = {"tsName"},
            fontSize = 14,
            color = "@fg",
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
        },
        {
            selectors = {"tsName", "fixed"},
            width = 120,
        },
        {
            selectors = {"tsSub"},
            fontSize = 11,
            color = "@fgMuted",
            width = "auto",
            height = "auto",
            halign = "left",
        },
        {
            selectors = {"tsSub", "warn"},
            color = "@danger",
        },
        {
            selectors = {"tsValue"},
            fontSize = 11,
            color = "@fgMuted",
            width = 44,
            height = "auto",
            halign = "right",
            valign = "center",
            textAlignment = "right",
        },
        {
            selectors = {"tsTrack"},
            bgimage = "panels/square.png",
            bgcolor = "@bg",
            borderWidth = 1,
            borderColor = "@border",
            cornerRadius = 2,
            width = SLIDER_WIDTH,
            height = 12,
            halign = "left",
            valign = "center",
            lmargin = 4,
            flow = "none",
        },
        {
            selectors = {"tsFill"},
            bgimage = "panels/square.png",
            bgcolor = "@fgMuted",
            opacity = 0.55,
            height = "100%",
            halign = "left",
            cornerRadius = 2,
        },
        {
            selectors = {"tsFill", "parent:parent:hover"},
            opacity = 0.8,
        },
        {
            selectors = {"tsTick"},
            bgimage = "panels/square.png",
            bgcolor = "@fg",
            opacity = 0.55,
            width = 1,
            height = 18,
            halign = "left",
            valign = "center",
        },
        {
            selectors = {"tsHeader"},
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = "100%",
            height = 30,
            tmargin = 6,
            hpad = 12,
            borderBox = true,
            halign = "left",
            valign = "top",
        },
        {
            selectors = {"tsHeaderLabel"},
            fontSize = 13,
            bold = true,
            color = "@fg",
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            lmargin = 6,
        },
        {
            selectors = {"tsHeaderLabel", "parent:hover"},
            color = "@fgStrong",
            transitionTime = 0.1,
        },
        {
            selectors = {"tsCaret"},
            bgcolor = "@fg",
            width = 10,
            height = 10,
            valign = "center",
        },
        {
            selectors = {"tsModalTitle"},
            fontSize = 18,
            bold = true,
            color = "@fgStrong",
            width = "100%",
            height = "auto",
            bmargin = 4,
        },
        {
            selectors = {"tsBannerText"},
            fontSize = 12,
            color = "@fg",
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
        },
        {
            selectors = {"tsSwatch"},
            borderWidth = 1,
            borderColor = "@borderSolid",
            width = 40,
            height = 16,
            halign = "right",
            valign = "center",
        },
        {
            selectors = {"tsSegmentBox"},
            bgimage = "panels/square.png",
            bgcolor = "clear",
            borderWidth = 1,
            borderColor = "@borderSolid",
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            valign = "center",
        },
        {
            selectors = {"tsRule"},
            bgimage = "panels/square.png",
            bgcolor = "@border",
            opacity = 0.35,
            width = "100%",
            height = 1,
        },
        {
            selectors = {"tsSeam"},
            bgimage = "panels/square.png",
            bgcolor = "@border",
            opacity = 0.2,
            width = "100%-24",
            height = 1,
            halign = "center",
        },
        {
            selectors = {"tsButton"},
            bgimage = "panels/square.png",
            bgcolor = "@bg",
            borderWidth = 1,
            borderColor = "@borderSolid",
            cornerRadius = 3,
            width = "auto",
            height = 26,
            hpad = 10,
            borderBox = true,
            halign = "left",
            valign = "center",
            rmargin = 6,
            flow = "horizontal",
        },
        {
            selectors = {"tsButton", "hover"},
            bgcolor = "@bgRaised",
            transitionTime = 0.15,
        },
        {
            selectors = {"tsButton", "tsOff"},
            priority = 5,
            opacity = 0.4,
        },
        {
            selectors = {"tsButtonLabel"},
            fontSize = 12,
            color = "@fg",
            width = "auto",
            height = "auto",
            valign = "center",
        },
        {
            selectors = {"tsButtonIcon"},
            bgcolor = "@fg",
            width = 13,
            height = 13,
            valign = "center",
            rmargin = 5,
        },
        --a button that does nothing here (Play Now on a type with no timed effect): its label and
        --glyph go muted (opacity on the button itself doesn't reach them).
        {
            selectors = {"tsButtonLabel", "parent:tsOff"},
            color = "@fgMuted",
            priority = 5,
        },
        {
            selectors = {"tsButtonIcon", "parent:tsOff"},
            bgcolor = "@fgMuted",
            priority = 5,
        },
        {
            selectors = {"tsChip"},
            bgimage = "panels/square.png",
            bgcolor = "clear",
            borderWidth = 1,
            borderColor = "@border",
            cornerRadius = 9,
            width = "auto",
            height = 18,
            hpad = 7,
            borderBox = true,
            valign = "center",
            lmargin = 6,
        },
        {
            selectors = {"tsChipLabel"},
            fontSize = 11,
            color = "@fgMuted",
            width = "auto",
            height = "auto",
            valign = "center",
        },
        {
            selectors = {"tsIcon"},
            bgcolor = "@fgMuted",
            width = 16,
            height = 16,
            valign = "center",
            lmargin = 8,
            opacity = 0.5,
        },
        {
            selectors = {"tsIcon", "parent:hover"},
            opacity = 1,
        },
        {
            selectors = {"tsIcon", "parent:parent:hover"},
            opacity = 1,
        },
        {
            selectors = {"tsIcon", "hover"},
            bgcolor = "@fg",
        },
        {
            selectors = {"tsIcon", "tsOff"},
            priority = 5,
            opacity = 0.15,
        },
        {
            selectors = {"tsThumb"},
            bgcolor = "white",
            borderWidth = 1,
            borderColor = "@borderSolid",
            width = 40,
            height = 40,
            halign = "left",
            valign = "center",
            rmargin = 10,
        },
        {
            selectors = {"tsUnsaved"},
            fontSize = 11,
            color = "@info",
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 8,
        },
        {
            selectors = {"tsBanner"},
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "@bgAlt",
            border = {x1 = 3, x2 = 0, y1 = 0, y2 = 0},
            borderColor = "@info",
            width = "100%",
            height = "auto",
            vpad = 8,
            hpad = 12,
            borderBox = true,
        },
        {
            selectors = {"tsSegment"},
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = "auto",
            height = 22,
            hpad = 10,
            borderBox = true,
            valign = "center",
        },
        {
            selectors = {"tsSegment", "on"},
            bgcolor = "@bgAlt",
            border = {x1 = 0, x2 = 0, y1 = 2, y2 = 0},
            borderColor = "@accent",
        },
        {
            selectors = {"tsSegmentLabel"},
            fontSize = 12,
            color = "@fgMuted",
            width = "auto",
            height = "auto",
            valign = "center",
        },
        {
            selectors = {"tsSegmentLabel", "parent:on"},
            color = "@fgStrong",
        },
        {
            selectors = {"tsPickerRow"},
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = "100%",
            height = 52,
            hpad = 12,
            borderBox = true,
        },
        {
            selectors = {"tsPickerRow", "hover"},
            bgcolor = "@bgRaised",
        },
        {
            selectors = {"tsPickerThumb"},
            bgcolor = "white",
            borderWidth = 1,
            borderColor = "@borderSolid",
            width = 60,
            height = 36,
            valign = "center",
            rmargin = 10,
        },
    }
end

----------------------------------------------------------------------
--Building blocks.

local function Label(classes, text, args)
    args = args or {}
    args.classes = classes
    args.text = text
    return gui.Label(args)
end

--A quiet button: an optional glyph and a label.
local function Button(args)
    local children = {}
    if args.icon ~= nil then
        children[#children + 1] = gui.Panel{ classes = {"tsButtonIcon"}, bgimage = args.icon }
    end
    children[#children + 1] = gui.Label{ classes = {"tsButtonLabel"}, text = args.text, refreshLabel = args.refreshLabel }

    local panelArgs = {
        classes = {"tsButton"},
        bgimage = "panels/square.png",
        children = children,
        press = args.press,
        click = args.click,
        think = args.think,
        thinkTime = args.thinkTime,
        linger = args.linger,
    }
    if args.tooltip ~= nil then
        panelArgs.linger = gui.Tooltip(args.tooltip)
    end
    return gui.Panel(panelArgs)
end

--A collapsible section: caret, label, underline, body.
local function Section(textKey, children)
    local body = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        children = children,
    }
    local caret = gui.ExpandoArrow{
        classes = {"tsCaret", "expanded"},
        bgimage = "phosphor/caret-down-fill.png",
    }
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Panel{
            classes = {"tsHeader"},
            caret,
            Label({"tsHeaderLabel"}, T(textKey)),
            click = function(element)
                local open = body:HasClass("collapsed")
                body:SetClass("collapsed", not open)
                caret:SetClass("expanded", open)
            end,
        },
        gui.Panel{ classes = {"tsRule"} },
        body,
    }
end

--Right-click on a row: Reset to Default.
local function ResetMenu(reset)
    return function(element)
        element.popup = gui.ContextMenu{
            width = 160,
            entries = {
                {
                    text = T("tablestudio.resettodefault"),
                    click = function()
                        element.popup = nil
                        reset()
                        element:FireEventTree("refreshValues")
                    end,
                },
            },
        }
    end
end

--A muted slider row, with a tick at the starting table's value.
local function SliderRow(f)
    local function Fraction(value)
        return math.max(0, math.min(1, (value - f.min) / (f.max - f.min)))
    end

    local fill = gui.Panel{ classes = {"tsFill"}, width = "0%" }
    local tick = gui.Panel{ classes = {"tsTick"}, floating = true, x = 0 }
    local valueLabel = Label({"tsValue"}, "")

    local function Show()
        local value = FieldGet(f)
        fill.selfStyle.width = string.format("%d%%", math.floor(Fraction(value) * 100 + 0.5))
        tick.selfStyle.x = math.floor(Fraction(FieldDefault(f)) * (SLIDER_WIDTH - 1))
        valueLabel.text = FormatValue(f, value)
    end

    local function SetFrom(element)
        local x = math.max(0, math.min(1, element.mousePoint.x))
        FieldSet(f, f.min + x * (f.max - f.min))
        Show()
    end

    local track = gui.Panel{
        classes = {"tsTrack"},
        swallowPress = true,
        draggable = true,
        dragMove = false,
        fill,
        tick,
        press = SetFrom,
        dragging = SetFrom,
        drag = function(element) end,
    }

    return gui.Panel{
        classes = {"tsRow"},
        Label({"tsName", "fixed"}, T(f.key)),
        track,
        valueLabel,
        create = function(element) Show() end,
        refreshValues = function(element) Show() end,
        rightClick = ResetMenu(function()
            FieldSet(f, FieldDefault(f))
        end),
    }
end

--A colour row: a plain colour, a ramp end, or Gold Marble's vein colour.
local function ColorRow(f)
    local function Get()
        if f.kind == "ramp" then
            return studio:GetLinearColor(RampProp(f))
        elseif f.kind == "axis" then
            return AxisColor(f)
        end
        return studio:GetColor(f.prop)
    end

    local function Set(color)
        if f.kind == "ramp" then
            SetRamp(f, color)
        elseif f.kind == "axis" then
            SetAxis(f, color)
        else
            studio:SetColor(f.prop, color)
        end
    end

    local function Reset()
        if f.kind == "ramp" then
            ResetRamp(f)
        elseif f.kind == "axis" then
            ResetVector(f.prop)
        else
            studio:SetColor(f.prop, studio:GetDefaultColor(f.prop))
        end
    end

    return gui.Panel{
        classes = {"tsRow"},
        Label({"tsName"}, T(f.key)),
        gui.ColorPicker{
            classes = {"tsSwatch"},
            value = Get(),
            change = function(element)
                Set(element.value)
            end,
            refreshValues = function(element)
                element.value = Get()
            end,
        },
        rightClick = ResetMenu(Reset),
    }
end

local function FieldRow(f)
    if f.kind == "color" or f.kind == "ramp" or f.kind == "axis" then
        return ColorRow(f)
    end
    return SliderRow(f)
end

--A texture slot's row: what the table shows in it now, its kind, size and source, and Replace /
--Save to disk / Use built in.
local function TextureRow(slot, textKey)
    local prop = slot.prop
    local sub = Label({"tsSub"}, "")

    local function Refresh()
        local info = nil
        for _, s in ipairs(studio:GetTextures()) do
            if s.prop == prop then
                info = s
            end
        end
        if info == nil then
            return
        end

        local size = tostring(info.width)
        local data = info.kind == "data"
        local warning = data and info.state == "loaded" and studio:GetTextureWarning(prop) == "picture"
        sub:SetClass("warn", warning)
        if warning then
            sub.text = T("tablestudio.tex.notdatamap")
        elseif info.state == "loading" then
            sub.text = T("tablestudio.tex.loading")
        elseif info.state == "loaded" then
            sub.text = data and T("tablestudio.tex.datamapuploaded", { size = size }) or T("tablestudio.tex.uploaded", { size = size })
        else
            sub.text = data and T("tablestudio.tex.datamap", { size = size }) or T("tablestudio.tex.builtin", { size = size })
        end
    end

    local replace = gui.IconEditor{
        classes = {"tsIcon"},
        library = "Textures",
        allowNone = true,
        noneImage = "phosphor/upload-simple-bold.png",
        hideIcon = true,
        searchHidden = true,
        categoriesHidden = true,
        width = 16,
        height = 16,
        linger = gui.Tooltip(T("tablestudio.replace")),
        change = function(element)
            local assetid = element.value
            if assetid == nil or assetid == "" then
                return
            end
            studio:SetTexture(prop, assetid)
            element.value = nil
            Refresh()
        end,
    }

    return gui.Panel{
        classes = {"tsRow", "tall"},
        gui.Panel{ classes = {"tsThumb"}, bgimage = "#TableStudioTex:" .. prop },
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            halign = "left",
            valign = "center",
            Label({"tsName"}, T(textKey)),
            sub,
        },
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            valign = "center",
            replace,
            gui.Panel{
                classes = {"tsIcon"},
                bgimage = "phosphor/download-simple.png",
                linger = gui.Tooltip(T("tablestudio.savetodisk")),
                press = function(element)
                    local path = studio:ExportTexture(prop)
                    if path ~= nil then
                        dmhub.RevealInFileBrowser(path)
                    end
                end,
            },
            gui.Panel{
                classes = {"tsIcon"},
                bgimage = "phosphor/arrow-counter-clockwise.png",
                linger = gui.Tooltip(T("tablestudio.usebuiltin")),
                press = function(element)
                    studio:SetTexture(prop, "")
                    Refresh()
                end,
            },
        },
        create = function(element) Refresh() end,
        refreshValues = function(element) Refresh() end,
        thinkTime = 0.5,
        think = function(element) Refresh() end,
    }
end

--A two-way switch, e.g. Preview As Draw Steel / DMHub.
local function Segmented(options, getValue, setValue)
    local children = {}
    for _, option in ipairs(options) do
        children[#children + 1] = gui.Panel{
            classes = {"tsSegment"},
            Label({"tsSegmentLabel"}, option.text),
            press = function(element)
                setValue(option.id)
                element.parent:FireEventTree("refreshSegment")
            end,
            refreshSegment = function(element)
                element:SetClass("on", getValue() == option.id)
            end,
            create = function(element)
                element:SetClass("on", getValue() == option.id)
            end,
        }
    end
    return gui.Panel{
        classes = {"tsSegmentBox"},
        children = children,
    }
end

----------------------------------------------------------------------
--Dialogs.

local function Modal(title, buttons, extra)
    local children = {
        Label({"tsModalTitle"}, title),
    }
    if extra ~= nil then
        children[#children + 1] = extra
    end
    local row = {}
    for _, b in ipairs(buttons) do
        row[#row + 1] = Button{ text = b.text, click = function(element)
            gui.CloseModal()
            if b.action ~= nil then
                b.action()
            end
        end }
    end
    children[#children + 1] = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "right",
        tmargin = 16,
        children = row,
    }
    gui.ShowModal(gui.Panel{
        classes = {"framedPanel"},
        styles = ThemeEngine.MergeStyles(BuildStyles()),
        width = 480,
        height = "auto",
        flow = "vertical",
        pad = 20,
        borderBox = true,
        children = children,
    })
end

--Asks for a name, then saves the table under it. onSaved runs after a save.
local function SaveAsDialog(onSaved)
    local input = gui.Input{
        width = "100%",
        height = 28,
        fontSize = 14,
        --a copy of an existing tabletop starts with that tabletop's name.
        text = studio.name ~= "" and studio.name or T("tablestudio.preset." .. studio.preset),
    }
    Modal(T("tablestudio.saveas"), {
        {
            text = T("tablestudio.save"),
            action = function()
                if studio:SaveAs(input.text) and onSaved ~= nil then
                    onSaved()
                end
            end,
        },
        { text = T("tablestudio.cancel") },
    }, input)
end

local function SaveThen(onSaved)
    if studio.name == "" then
        SaveAsDialog(onSaved)
    elseif studio:Save() and onSaved ~= nil then
        onSaved()
    end
end

--Runs action now if nothing is unsaved; otherwise asks Save / Discard / Cancel first.
local function GuardUnsaved(action)
    if not studio.hasTable or not studio.hasUnsavedChanges then
        action()
        return
    end
    local name = studio.name ~= "" and studio.name or T("tablestudio.newtable")
    Modal(T("tablestudio.savechanges", { name = name }), {
        { text = T("tablestudio.save"), action = function() SaveThen(action) end },
        { text = T("tablestudio.discard"), action = function() studio:Revert() action() end },
        { text = T("tablestudio.cancel") },
    })
end

----------------------------------------------------------------------
--Going live (phase 1b): who gets each table, versions, Upload and Set Live.

--An engine from before going live (phase 1a) has none of it; the panel then offers what 1a did.
local g_canGoLive = pcall(function() return studio.liveVersion end)

--The built-in tabletops as the players' menu has them (Tabletop.lua): {id, text, dice}, in order.
local function BuiltinSurfaces()
    local tabletop = rawget(_G, "Tabletop")
    return (tabletop ~= nil and tabletop.surfaces) or {}
end

--A built-in's entry there and its place (1 to 9), or nil, 0.
local function BuiltinInfo(id)
    for i, entry in ipairs(BuiltinSurfaces()) do
        if entry.id == id then
            return entry, i
        end
    end
    return nil, 0
end

--The tables put live (dmhub.GetLiveTables).
local function LiveTables()
    local ok, list = pcall(function() return dmhub.GetLiveTables() end)
    return (ok and type(list) == "table") and list or {}
end

--Every dice set's name as players see it, by asset id: the display name where the engine gives
--it (or this account owns the set), else the internal name. Sets with no name are left out.
local function DiceNames()
    local names = {}
    for _, entry in ipairs(dice.GetAllDice()) do
        local name = entry.displayName or entry.text
        if name ~= nil and name ~= "" then
            names[entry.id] = name
        end
    end
    for _, entry in ipairs(dice.GetAvailableDice()) do
        if entry.value ~= "Default" and entry.text ~= nil and entry.text ~= "" then
            names[entry.value] = entry.text
        end
    end
    return names
end

--A dice set's name, from its asset id.
local function DiceName(assetid)
    return DiceNames()[assetid] or assetid
end

--The tag showing who gets a table: "Free", or "<set> dice" (a set named "Soulkiller Dice" gives
--"Soulkiller dice", not "Soulkiller Dice dice").
local function AccessTag(access, diceid)
    if access == "dice" and diceid ~= nil and diceid ~= "" then
        local name = string.gsub(DiceName(diceid), "%s+[Dd][Ii][Cc][Ee]$", "")
        return T("tablestudio.tag.dice", { dice = name })
    end
    return T("tablestudio.tag.free")
end

--Who gets a built-in tabletop without the studio: its dice link in the players' menu.
local function BuiltinDefaultAccess(id)
    local entry = BuiltinInfo(id)
    if entry ~= nil and entry.dice ~= nil then
        return "dice", entry.dice
    end
    return "everyone", ""
end

--Who gets a built-in tabletop now: its live version's rule, else its dice link.
local function BuiltinAccess(id)
    for _, live in ipairs(LiveTables()) do
        if live.builtin == id then
            return live.access, live.dice
        end
    end
    return BuiltinDefaultAccess(id)
end

--Opens a built-in tabletop for editing, named and placed as the players' menu has it.
local function OpenBuiltin(id)
    local entry, index = BuiltinInfo(id)
    local diceid = (entry ~= nil and entry.dice) or ""
    return studio:EditBuiltin(id, T("tablestudio.preset." .. id), diceid, index > 0 and index or 10)
end

--The dice set whose non-owners would lose the table if this version went live, or nil.
local function AccessLoss()
    if studio.access ~= "dice" or studio.dice == "" then
        return nil
    end

    local oldAccess, oldDice
    local live = studio:GetLiveAccess()
    if live ~= nil then
        oldAccess, oldDice = live.access, live.dice
    elseif studio.builtin ~= "" then
        oldAccess, oldDice = BuiltinDefaultAccess(studio.builtin)
    else
        --a new table: nobody has it yet.
        return nil
    end

    if oldAccess == "dice" and oldDice == studio.dice then
        return nil
    end
    return DiceName(studio.dice)
end

----------------------------------------------------------------------
--The panel.

local function CreateTableStudioPanel()
    local root
    local sections

    --The type, textures, layout, logo and look sections for the table being edited.
    local function BuildSections()
        if not studio.hasTable then
            sections.children = {}
            return
        end

        local typeid = studio.type
        local def = g_types[typeid]
        local typeInfo = nil
        for _, t in ipairs(studio:GetTypes()) do
            if t.id == typeid then
                typeInfo = t
            end
        end
        if def == nil or typeInfo == nil then
            sections.children = {}
            return
        end

        local chips = {}
        if typeInfo.reflects then
            chips[#chips + 1] = gui.Panel{ classes = {"tsChip"}, Label({"tsChipLabel"}, T("tablestudio.feat.reflects")) }
        end
        if typeInfo.parallax then
            chips[#chips + 1] = gui.Panel{ classes = {"tsChip"}, Label({"tsChipLabel"}, T("tablestudio.feat.parallax")) }
        end

        local textureRows = {}
        for _, slot in ipairs(studio:GetTextures()) do
            local key = def.textures[slot.prop]
            --Felt is a Playmat too, but its texture is cloth, not leather.
            if typeid == "playmat" and studio.preset == "felt" and slot.prop == "_MainTex" then
                key = "tablestudio.tex.cloth"
            end
            --logo slots wait for the own-logo step (phase 1c).
            if key ~= nil and slot.kind ~= "logo" then
                if #textureRows > 0 then
                    textureRows[#textureRows + 1] = gui.Panel{ classes = {"tsSeam"} }
                end
                textureRows[#textureRows + 1] = TextureRow(slot, key)
            end
        end

        local layoutRows = {}
        if typeInfo.tiled then
            for _, f in ipairs(g_layoutFields) do
                layoutRows[#layoutRows + 1] = SliderRow(f)
            end
        end

        local logoRows = {
            gui.Panel{
                classes = {"tsRow"},
                Label({"tsName"}, T("tablestudio.showlogo")),
                gui.Check{
                    halign = "right",
                    valign = "center",
                    text = "",
                    value = studio:GetLayout().showLogo,
                    change = function(element)
                        studio:SetLayout{ showLogo = element.value }
                    end,
                    refreshValues = function(element)
                        element.value = studio:GetLayout().showLogo
                    end,
                },
            },
            gui.Panel{ classes = {"tsSeam"} },
            gui.Panel{
                classes = {"tsRow"},
                Label({"tsName"}, T("tablestudio.previewas")),
                Segmented(
                    {
                        { id = "drawsteel", text = T("tablestudio.logo.drawsteel") },
                        { id = "dmhub", text = T("tablestudio.logo.dmhub") },
                    },
                    function()
                        local which = studio.logoPreview
                        if which == "" then
                            which = dmhub.whiteLabel == "mcdm" and "drawsteel" or "dmhub"
                        end
                        return which
                    end,
                    function(id) studio.logoPreview = id end
                ),
            },
            gui.Panel{ classes = {"tsSeam"} },
        }
        for _, f in ipairs(def.logo) do
            logoRows[#logoRows + 1] = FieldRow(f)
        end

        local lookRows = {}
        for _, f in ipairs(def.look) do
            lookRows[#lookRows + 1] = FieldRow(f)
        end

        local children = {
            Section("tablestudio.sec.type", {
                gui.Panel{
                    classes = {"tsRow"},
                    Label({"tsName"}, T(g_typeKeys[typeid] or "tablestudio.sec.type")),
                    gui.Panel{ width = "auto", height = "auto", flow = "horizontal", halign = "right", valign = "center", children = chips },
                },
            }),
            Section("tablestudio.sec.textures", textureRows),
        }
        if #layoutRows > 0 then
            children[#children + 1] = Section("tablestudio.sec.layout", layoutRows)
        end
        children[#children + 1] = Section("tablestudio.sec.logo", logoRows)
        children[#children + 1] = Section("tablestudio.sec.look", lookRows)

        if g_canGoLive then
            --Leather is everyone's fallback table, so it can't be locked to a dice set.
            local isLeather = studio.builtin == "leather"

            if not isLeather then
                local named = {}
                for id, name in pairs(DiceNames()) do
                    named[#named + 1] = { id = id, text = name }
                end
                table.sort(named, function(a, b) return a.text < b.text end)
                local diceOptions = { { id = "", text = T("tablestudio.dice.none") } }
                for _, option in ipairs(named) do
                    diceOptions[#diceOptions + 1] = option
                end
                children[#children + 1] = Section("tablestudio.sec.dice", {
                    gui.Panel{
                        classes = {"tsRow"},
                        Label({"tsName"}, T("tablestudio.diceset")),
                        gui.Dropdown{
                            width = 180,
                            height = 26,
                            fontSize = 14,
                            halign = "right",
                            valign = "center",
                            options = diceOptions,
                            idChosen = studio.dice,
                            change = function(element)
                                local id = tostring(element.idChosen or "")
                                --with no dice set, only Everyone makes sense.
                                studio:SetAccess(id == "" and "everyone" or studio.access, id)
                                root:FireEventTree("refreshSegment")
                            end,
                        },
                    },
                })
            end

            local accessRows = {}
            if isLeather then
                accessRows[#accessRows + 1] = gui.Panel{
                    classes = {"tsRow"},
                    Label({"tsName"}, T("tablestudio.access.everyone")),
                }
            else
                accessRows[#accessRows + 1] = gui.Panel{
                    classes = {"tsRow"},
                    Segmented(
                        {
                            { id = "everyone", text = T("tablestudio.access.everyone") },
                            { id = "dice", text = T("tablestudio.access.dice") },
                        },
                        function() return studio.access end,
                        function(id)
                            --Dice Owners needs a dice set first.
                            if id ~= "dice" or studio.dice ~= "" then
                                studio:SetAccess(id, studio.dice)
                            end
                        end
                    ),
                }
            end
            accessRows[#accessRows + 1] = gui.Panel{ classes = {"tsSeam"} }
            accessRows[#accessRows + 1] = gui.Panel{
                classes = {"tsRow"},
                Label({"tsName"}, T("tablestudio.viewasplayer")),
                gui.Check{
                    halign = "right",
                    valign = "center",
                    text = "",
                    value = studio.viewAsPlayer,
                    change = function(element)
                        studio.viewAsPlayer = element.value
                    end,
                },
            }
            children[#children + 1] = Section("tablestudio.sec.access", accessRows)

            children[#children + 1] = Section("tablestudio.sec.menu", {
                gui.Panel{
                    classes = {"tsRow"},
                    Label({"tsName"}, T("tablestudio.menuname")),
                    gui.Input{
                        width = 180,
                        height = 24,
                        fontSize = 13,
                        halign = "right",
                        valign = "center",
                        text = studio.menuName ~= "" and studio.menuName or studio.name,
                        change = function(element)
                            studio:SetMenu(element.text, studio.position)
                        end,
                    },
                },
                gui.Panel{ classes = {"tsSeam"} },
                gui.Panel{
                    classes = {"tsRow"},
                    Label({"tsName"}, T("tablestudio.position")),
                    gui.Input{
                        width = 50,
                        height = 24,
                        fontSize = 13,
                        halign = "right",
                        valign = "center",
                        text = tostring(studio.position),
                        change = function(element)
                            local n = tonumber(element.text)
                            if n ~= nil then
                                studio:SetMenu(studio.menuName, math.floor(n))
                            end
                            element.text = tostring(studio.position)
                        end,
                    },
                },
            })
        end

        sections.children = children
    end

    --The table dropdown: the built-in tabletops first ("builtin:<id>": picking one edits it),
    --then the tables saved here (by name; a folder name can't hold ':'), then live tables made on
    --another machine ("cloud:<id>"), each tagged with who gets it. A new table not saved yet
    --shows as ":new".
    local function CurrentEntry()
        if not studio.hasTable then
            return ""
        elseif g_canGoLive and studio.builtin ~= "" then
            return "builtin:" .. studio.builtin
        elseif studio.name == "" then
            return g_canGoLive and ":new" or ("builtin:" .. studio.preset)
        end
        return studio.name
    end

    local tableDropdown = gui.Dropdown{
        width = 260,
        height = 28,
        fontSize = 14,
        options = {},
        idChosen = "",
        refreshFile = function(element)
            local options = {}
            if not studio.hasTable then
                --blank while nothing is open.
                options[#options + 1] = { id = "", text = "" }
            end
            if CurrentEntry() == ":new" then
                options[#options + 1] = { id = ":new", text = T("tablestudio.newtable") }
            end
            for _, preset in ipairs(studio:GetPresets()) do
                local text = T("tablestudio.preset." .. preset.id)
                if g_canGoLive then
                    text = T("tablestudio.listentry", { name = text, tag = AccessTag(BuiltinAccess(preset.id)) })
                end
                options[#options + 1] = { id = "builtin:" .. preset.id, text = text }
            end
            if g_canGoLive then
                for _, t in ipairs(studio:GetTableList()) do
                    options[#options + 1] = { id = t.name, text = T("tablestudio.listentry", { name = t.name, tag = AccessTag(t.access, t.dice) }) }
                end
                for _, t in ipairs(studio:GetCloudTables()) do
                    options[#options + 1] = { id = "cloud:" .. t.id, text = T("tablestudio.listentry", { name = t.name, tag = AccessTag(t.access, t.dice) }) }
                end
            else
                for _, name in ipairs(studio:GetLocalTables()) do
                    options[#options + 1] = { id = name, text = name }
                end
            end
            element.options = options
            element.idChosen = CurrentEntry()
        end,
        change = function(element)
            local id = tostring(element.idChosen or "")
            local current = CurrentEntry()
            --the dropdown keeps showing the open table until the switch happens (and stays put
            --if the unsaved prompt is cancelled).
            element.idChosen = current
            if id == "" or id == current then
                return
            end
            GuardUnsaved(function()
                local builtinId = string.match(id, "^builtin:(.+)$")
                local cloudId = string.match(id, "^cloud:(.+)$")
                if builtinId ~= nil then
                    if g_canGoLive then
                        OpenBuiltin(builtinId)
                    else
                        studio:NewTable(builtinId)
                    end
                elseif cloudId ~= nil then
                    studio:OpenCloudTable(cloudId)
                else
                    studio:Load(id)
                end
                root:FireEvent("tableChanged")
            end)
        end,
    }

    --(shown and hidden by its row's think: a label's own think doesn't fire.)
    local unsavedLabel = Label({"tsUnsaved", "hidden"}, T("tablestudio.unsaved"))

    --The New picker: the built-in tables as starting points.
    local function OpenPicker(anchor)
        local rows = {
            Label({"tsHeaderLabel"}, T("tablestudio.startfrom"), { lmargin = 12, tmargin = 6, bmargin = 6 }),
        }
        for _, preset in ipairs(studio:GetPresets()) do
            local id = preset.id
            rows[#rows + 1] = gui.Panel{
                classes = {"tsPickerRow"},
                gui.Panel{ classes = {"tsPickerThumb"}, bgimage = "#TableStudioPreset:" .. id },
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                    halign = "left",
                    valign = "center",
                    Label({"tsName"}, T("tablestudio.preset." .. id)),
                    Label({"tsSub"}, T(g_typeKeys[preset.type] or "tablestudio.sec.type")),
                },
                g_canGoLive and gui.Panel{
                    classes = {"tsChip"},
                    halign = "right",
                    Label({"tsChipLabel"}, AccessTag(BuiltinAccess(id))),
                } or nil,
                press = function(element)
                    anchor.popup = nil
                    if studio:NewTable(id) then
                        root:FireEvent("tableChanged")
                    end
                end,
            }
        end
        anchor.popup = gui.Panel{
            classes = {"framedPanel"},
            styles = ThemeEngine.MergeStyles(BuildStyles()),
            width = 300,
            height = "auto",
            flow = "vertical",
            vpad = 6,
            borderBox = true,
            halign = "left",
            valign = "bottom",
            children = rows,
        }
    end

    local newButton
    newButton = Button{
        text = T("tablestudio.new"),
        click = function(element)
            GuardUnsaved(function() OpenPicker(newButton) end)
        end,
    }

    local fileBlock = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        hpad = 12,
        vpad = 10,
        borderBox = true,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bmargin = 8,
            tableDropdown,
            unsavedLabel,
            thinkTime = 0.25,
            think = function(element)
                unsavedLabel:SetClass("hidden", not (studio.hasTable and studio.hasUnsavedChanges))
            end,
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            newButton,
            Button{
                text = T("tablestudio.save"),
                click = function(element)
                    if studio.hasTable then
                        SaveThen(function() root:FireEvent("tableChanged") end)
                    end
                end,
            },
            Button{
                text = T("tablestudio.saveas"),
                click = function(element)
                    if studio.hasTable then
                        SaveAsDialog(function() root:FireEvent("tableChanged") end)
                    end
                end,
            },
            g_canGoLive and Button{
                text = T("tablestudio.upload"),
                click = function(element)
                    if not studio.hasTable then
                        return
                    end
                    --a table never saved needs a name first.
                    if studio.name == "" then
                        SaveAsDialog(function()
                            studio:Upload()
                            root:FireEvent("tableChanged")
                        end)
                    else
                        studio:Upload()
                        root:FireEventTree("refreshVersion")
                    end
                end,
            } or nil,
        },
    }

    --Set Live, after a confirmation that names who would lose the table.
    local function ConfirmSetLive()
        local function Confirm()
            local extra = nil
            local loss = AccessLoss()
            if loss ~= nil then
                extra = Label({"tsSub"}, T("tablestudio.setlive.accessloss", { dice = loss }), { width = "100%", tmargin = 8 })
            end
            Modal(T("tablestudio.setlive.confirm", { n = studio.version }), {
                {
                    text = T("tablestudio.setlive"),
                    action = function()
                        studio:SetLive()
                        root:FireEvent("tableChanged")
                    end,
                },
                { text = T("tablestudio.cancel") },
            }, extra)
        end

        if studio.name == "" then
            SaveAsDialog(Confirm)
        else
            Confirm()
        end
    end

    --The versions (phase 1b): the version open with its status, the live one, Set Live, the
    --live version's read-only note, a failed upload, and the version's notes. Refreshed when
    --anything about them changes (an edit starting a version, an upload finishing).
    local versionBlock = nil
    if g_canGoLive then
        local versionDropdown = gui.Dropdown{
            width = 230,
            height = 26,
            fontSize = 14,
            options = {},
            idChosen = "",
            refreshVersion = function(element)
                local options = {}
                for _, v in ipairs(studio:GetVersions()) do
                    options[#options + 1] = {
                        id = tostring(v.version),
                        text = T("tablestudio.versionentry", {
                            version = T("tablestudio.version", { n = v.version }),
                            status = T("tablestudio.status." .. v.status),
                        }),
                    }
                end
                element.options = options
                element.idChosen = tostring(studio.version)
            end,
            change = function(element)
                local id = tostring(element.idChosen or "")
                local current = tostring(studio.version)
                element.idChosen = current
                local n = tonumber(id)
                if n == nil or id == current then
                    return
                end
                GuardUnsaved(function()
                    if studio:LoadVersion(n) then
                        root:FireEvent("tableChanged")
                    end
                end)
            end,
        }

        local lastSignature = ""
        versionBlock = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            hpad = 12,
            bmargin = 10,
            borderBox = true,
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                versionDropdown,
                Label({"tsSub"}, "", {
                    lmargin = 8,
                    valign = "center",
                    refreshVersion = function(element)
                        local live = studio.liveVersion
                        element.text = (live > 0 and not studio.isLiveVersion) and T("tablestudio.liveversion", { n = live }) or ""
                    end,
                }),
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    halign = "right",
                    Button{
                        text = T("tablestudio.setlive"),
                        click = function(element)
                            ConfirmSetLive()
                        end,
                    },
                    refreshVersion = function(element)
                        element:SetClass("collapsed", studio.isLiveVersion)
                    end,
                },
            },
            Label({"tsSub"}, "", {
                tmargin = 4,
                refreshVersion = function(element)
                    element:SetClass("collapsed", not studio.isLiveVersion)
                    element.text = T("tablestudio.livereadonly", { n = studio.nextVersion })
                end,
            }),
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                tmargin = 4,
                Label({"tsSub", "warn"}, T("tablestudio.uploadfailed"), { valign = "center" }),
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    halign = "right",
                    Button{
                        text = T("tablestudio.retry"),
                        click = function(element)
                            studio:RetrySend()
                            root:FireEventTree("refreshVersion")
                        end,
                    },
                },
                refreshVersion = function(element)
                    element:SetClass("collapsed", studio.sendState ~= "failed")
                end,
            },
            gui.Input{
                width = "100%",
                height = 24,
                fontSize = 13,
                tmargin = 6,
                placeholderText = T("tablestudio.notes"),
                text = "",
                change = function(element)
                    studio.notes = element.text
                end,
                refreshVersion = function(element)
                    if element.text ~= studio.notes then
                        element.text = studio.notes
                    end
                end,
            },

            --(the version open changes on a live version's first edit, and uploads finish later.)
            thinkTime = 0.5,
            think = function(element)
                local signature = string.format("%d|%d|%s|%d", studio.version, studio.liveVersion, studio.sendState, studio.changeSeq)
                if signature ~= lastSignature then
                    lastSignature = signature
                    element:FireEventTree("refreshVersion")
                end
            end,
            refreshFile = function(element)
                element:SetClass("collapsed", not studio.hasTable)
                lastSignature = ""
            end,
        }
    end

    --Peek / Compare (held), Pause, Play Now.
    local toolbar = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        hpad = 12,
        bmargin = 6,
        borderBox = true,
        Button{
            icon = "phosphor/eye.png",
            text = T("tablestudio.peek"),
            tooltip = T("tablestudio.peek.tip"),
            press = function(element) studio:HoldPeek() end,
        },
        Button{
            icon = "phosphor/arrow-counter-clockwise.png",
            text = T("tablestudio.compare"),
            tooltip = T("tablestudio.compare.tip"),
            press = function(element) studio:HoldCompare() end,
        },
        Button{
            icon = "phosphor/pause.png",
            text = T("tablestudio.pause"),
            click = function(element)
                studio.paused = not studio.paused
                element:FireEventTree("refreshLabel")
            end,
            refreshLabel = function(element)
                element.text = studio.paused and T("tablestudio.resume") or T("tablestudio.pause")
            end,
        },
        Button{
            icon = "phosphor/play.png",
            text = T("tablestudio.playnow"),
            click = function(element)
                studio:PlayNow()
            end,
            linger = function(element)
                local tip = element:HasClass("tsOff") and T("tablestudio.playnow.none") or T("tablestudio.playnow.tip")
                gui.Tooltip(tip)(element)
            end,
            thinkTime = 0.5,
            think = function(element)
                local timed = false
                for _, t in ipairs(studio:GetTypes()) do
                    if t.id == studio.type then
                        timed = t.timed
                    end
                end
                element:SetClass("tsOff", not timed)
            end,
        },
    }

    --The draft found at open: Restore puts it back as the table being edited.
    local banner
    banner = gui.Panel{
        classes = {"tsBanner", "collapsed"},
        Label({"tsBannerText"}, "", {
            refreshDraft = function(element)
                local draft = studio:GetDraft()
                if draft ~= nil then
                    element.text = T("tablestudio.draftfound", { time = os.date("%H:%M", math.floor(draft.savedAt)) })
                end
            end,
        }),
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            valign = "center",
            Button{
                text = T("tablestudio.restore"),
                click = function(element)
                    if studio:RestoreDraft() then
                        root:FireEvent("tableChanged")
                    end
                    banner:SetClass("collapsed", true)
                end,
            },
            Button{
                text = T("tablestudio.discard"),
                click = function(element)
                    studio:DiscardDraft()
                    banner:SetClass("collapsed", true)
                end,
            },
        },
    }

    sections = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        bmargin = 14,
    }

    --(a list, so a missing version block leaves no hole.)
    local rootChildren = { banner, fileBlock }
    if versionBlock ~= nil then
        rootChildren[#rootChildren + 1] = versionBlock
    end
    rootChildren[#rootChildren + 1] = toolbar
    rootChildren[#rootChildren + 1] = sections

    root = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        styles = ThemeEngine.MergeStyles(BuildStyles()),
        children = rootChildren,

        create = function(element)
            g_tableStudioRoot = element
            studio.previewing = true
            local draft = studio:GetDraft()
            local show = draft ~= nil and not (studio.hasTable and studio.hasUnsavedChanges)
            banner:SetClass("collapsed", not show)
            if show then
                banner:FireEventTree("refreshDraft")
            end
            element:FireEvent("tableChanged")
        end,

        destroy = function(element)
            studio.previewing = false
            if g_tableStudioRoot == element then
                g_tableStudioRoot = nil
            end
        end,

        --another tab in the dock, or the dock slid away: the panel stays alive but unseen, so
        --the user's own table comes back until it is shown again.
        hidepanel = function(element)
            studio.previewing = false
        end,

        showpanel = function(element)
            studio.previewing = true
        end,

        tableChanged = function(element)
            BuildSections()
            element:FireEventTree("refreshFile")
            element:FireEventTree("refreshVersion")
        end,

        --the unsaved changes go to the draft every few seconds.
        thinkTime = 5,
        think = function(element)
            if studio.hasTable and studio.hasUnsavedChanges then
                studio:SaveDraft()
            end
        end,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if root ~= nil and root.valid then
            root.styles = ThemeEngine.MergeStyles(BuildStyles())
        end
    end)

    return root
end

DockablePanel.Register{
    name = "Table Studio",
    icon = "phosphor/image.png",
    vscroll = true,
    minHeight = 100,
    content = function()
        return CreateTableStudioPanel()
    end,
}
