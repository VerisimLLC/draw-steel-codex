--- Styles for Character Builder

-- TODO: Clean up styles / ordering

--- Set this to true to draw layout helper borders around panels that have none
local DEBUG_PANEL_BG = false

CharacterBuilder.COLORS = {
    BLACK = "#000000",
    BLACK03 = "#191A18",
    CREAM = "#BC9B7B",
    GOLD = "#966D4B",
    GRAY02 = "#666663",
    PANEL_BG = "#080B09",
}

CharacterBuilder.SIZES = {
    CHARACTER_PANEL_WIDTH = 447,

    ACTION_BUTTON_WIDTH = 225,
    ACTION_BUTTON_HEIGHT = 45,

    SELECTOR_BUTTON_WIDTH = 200,
    SELECTOR_BUTTON_HEIGHT = 48,

    CATEGORY_BUTTON_WIDTH = 250,
    CATEGORY_BUTTON_HEIGHT = 48,
    CATEGORY_BUTTON_MARGIN = 16,

    AVATAR_DIAMETER = 185,

    BUTTON_SPACING = 12,
}
CharacterBuilder.SIZES.BUTTON_PANEL_WIDTH = CharacterBuilder.SIZES.ACTION_BUTTON_WIDTH + 60
CharacterBuilder.SIZES.CENTER_PANEL_WIDTH = "100%-" .. (30 + CharacterBuilder.SIZES.BUTTON_PANEL_WIDTH + CharacterBuilder.SIZES.CHARACTER_PANEL_WIDTH)

--[[
    Styles
]]

function CharacterBuilder._baseStyles()
    return {
        {
            selectors = {"builder-base"},
            fontSize = 14,
            fontFace = "Newzald",
            color = Styles.textColor,
            bold = false,
        },
        {
            selectors = {"font-black"},
            color = "#000000",
        },
    }
end

function CharacterBuilder._panelStyles()
    return {
        {
            selectors = {"panel-base"},
            height = "auto",
            width = "auto",
            pad = 2,
            margin = 2,
            bgimage = DEBUG_PANEL_BG and "panels/square.png",
            borderWidth = 1,
            border = DEBUG_PANEL_BG and 1 or 0
        },
        {
            selectors = {"panel-border"},
            -- bgimage = true,
            -- bgcolor = "#ffffff",
            borderColor = CharacterBuilder.COLORS.CREAM,
            border = 2,
            cornerRadius = 10,
        },
        {
            selectors = {"builderPanel"},
            bgcolor = CharacterBuilder.COLORS.PANEL_BG,
        },
        {
            selectors = {CharacterBuilder.CONTROLLER_CLASS},
            bgcolor = "#ffffff",
            bgimage = nil,
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.5, y = 0.5},
                point_b = {x = 0.5, y = 1.0},
                stops = {
                    {position = 0.00, color = "#ffffff"},
                    {position = 0.08, color = "#e0e0e0"},
                    {position = 0.15, color = "#c0c0c0"},
                    {position = 0.22, color = "#a0a0a0"},
                    {position = 0.30, color = "#808080"},
                    {position = 0.45, color = "#606060"},
                    {position = 0.60, color = "#404040"},
                    {position = 0.75, color = "#202020"},
                    {position = 0.88, color = "#101010"},
                    {position = 1.00, color = "#000000"},
                },
            },
        },
    }
end

function CharacterBuilder._labelStyles()
    return {
        {
            selectors = {"label"},
            textAlignment = "center",
            fontSize = 14,
            color = Styles.textColor,
            bold = false,
        },
        {
            selectors = {"label-info"},
            hpad = 12,
            fontSize = 18,
            textAlignment = "left",
            bgimage = true,
            bgcolor = "#10110FE5",
        },
        {
            selectors = {"label-header"},
            fontSize = 40,
            bold = true,
        },
    }
end

function CharacterBuilder._buttonStyles()
    return {
        {
            selectors = {"button"},
            border = 1,
            borderWidth = 1,
        },
        {
            selectors = {"category"},
            width = CharacterBuilder.SIZES.ACTION_BUTTON_WIDTH,
            height = CharacterBuilder.SIZES.ACTION_BUTTON_HEIGHT,
            halign = "center",
            valign = "top",
            bmargin = 20,
            fontSize = 24,
            cornerRadius = 5,
            textAlignment = "left",
            bold = false,
        },
        {
            selectors = {"available"},
            borderColor = CharacterBuilder.COLORS.CREAM,
            color = CharacterBuilder.COLORS.GOLD,
        },
        {
            selectors = {"unavailable"},
            borderColor = CharacterBuilder.COLORS.GRAY02,
            color = CharacterBuilder.COLORS.GRAY02,
        }
    }
end

function CharacterBuilder._inputStyles()
    return {
        {
            selectors = {"text-entry"},
            bgcolor = "#191A18",
            borderColor = "#666663",
        },
        {
            selectors = {"primary"},
            height = 48,
        },
        {
            selectors = {"secondary"},
            height = 36,
        },
    }
end

function CharacterBuilder._getStyles()
    local styles = {}

    local function mergeStyles(sourceStyles)
        for _, style in ipairs(sourceStyles) do
            styles[#styles + 1] = style
        end
    end

    mergeStyles(CharacterBuilder._baseStyles())
    mergeStyles(CharacterBuilder._panelStyles())
    mergeStyles(CharacterBuilder._labelStyles())
    mergeStyles(CharacterBuilder._buttonStyles())
    mergeStyles(CharacterBuilder._inputStyles())

    return styles
end