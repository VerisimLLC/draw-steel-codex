--- Styles for Character Builder

-- TODO: Clean up styles / ordering

--- Set this to true to draw layout helper borders around panels that have none
local DEBUG_PANEL_BG = false

CharacterBuilder.COLORS = {
    BLACK = "#000000",
    BLACK03 = "#191A18",
    CREAM = "#BC9B7B",
    CREAM03 = "#DFCFC0",
    GOLD = "#966D4B",
    GOLD03 = "#F1D3A5",
    GRAY02 = "#666663",
    PANEL_BG = "#080B09",

    -- For selections like skills etc.
    FILLED_ITEM_BG = "#E9B86F40",
    FILLED_ITEM_BORDER = "#E9B86F",

    DELETE_WARN_BG = "#660000",
    DELETE_WARN_BORDER = "#CC3333",
}

CharacterBuilder.SIZES = {
    -- Panels
    CHARACTER_PANEL_WIDTH = 447,
    CHARACTER_PANEL_HEADER_HEIGHT = 270,

    DESCRIPTION_PANEL_WIDTH = 450,

    AVATAR_DIAMETER = 185,

    -- Labels
    DESCRIPTION_LABEL_PAD = 4,

    -- Buttons
    ACTION_BUTTON_WIDTH = 225,
    ACTION_BUTTON_HEIGHT = 45,

    CATEGORY_BUTTON_WIDTH = 250,
    CATEGORY_BUTTON_HEIGHT = 48,
    CATEGORY_BUTTON_MARGIN = 16,

    SELECTOR_BUTTON_WIDTH = 200,
    SELECTOR_BUTTON_HEIGHT = 48,

    SELECT_BUTTON_WIDTH = 200,
    SELECT_BUTTON_HEIGHT = 36,

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
            fontFace = "Berling",
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
            selectors = {"panel-charpanel-detail"},
            width = "96%",
            height = "80%",
            halign = "center",
            valign = "top",
            flow = "vertical",
            borderColor = "yellow",
            border = 1,
        },
        {
            selectors = {CharacterBuilder.CONTROLLER_CLASS},
            bgcolor = "#ffffff",
            bgimage = true,
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.5, y = 0.5},
                point_b = {x = 0.5, y = 1.0},
                stops = {
                    {position = -0.01, color = "#1c1c1c"},
                    {position = 0.00, color = "#1c1c1c"},
                    {position = 0.12, color = "#191919"},
                    {position = 0.25, color = "#161616"},
                    {position = 0.37, color = "#131413"},
                    {position = 0.50, color = "#101110"},
                    {position = 0.62, color = "#0d0f0d"},
                    {position = 0.75, color = "#0b0d0b"},
                    {position = 0.87, color = "#090c0a"},
                    {position = 1.00, color = "#080b09"},
                },
            },
        },

        -- For the right side character pane
        {
            selectors = {"charpanel-detail-header"},
            width = "100%",
            height = "auto",
            valign = "top",
            halign = "left",
        },
        {
            selectors = {"feature-detail-panel"},
            width = "100%",
            height = "auto",
            valign = "top",
            halign = "left",
            flow = "horizontal",
        },
    }
end

function CharacterBuilder._labelStyles()
    return {
        {
            selectors = {"label"},
            height = "auto",
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
        {
            selectors = {"label-charname"},
            width = "98%",
            height = "auto",
            halign = "center",
            valign = "top",
            textAlignment = "center",
            fontSize = 24,
            tmargin = 12,
        },
        {
            selectors = {"label-description"},
            width = "50%",
            height = "auto",
            halign = "left",
            vpad = CharacterBuilder.SIZES.DESCRIPTION_LABEL_PAD,
            textAlignment = "left",
            fontSize = 18,
            bold = true,
        },
        {
            selectors = {"label-desc-item"},
            width = "50%",
            height = "auto",
            halign = "left",
            vpad = CharacterBuilder.SIZES.DESCRIPTION_LABEL_PAD,
            textAlignment = "left",
            fontSize = 18,
        },
        {
            selectors = {"label-panel-placeholder"},
            width = "auto",
            height = "auto",
            valign = "center",
            halign = "center",
            fontSize = 36,
        },

        -- Feature names & descriptions for selection panels
        {
            selectors = {"label-feature-name"},
            width = "100%",
            height = "auto",
            valign = "top",
            vpad = 14,
            bmargin = 10,
            textAlignment = "center",
            fontSize = 20,
            bgimage = true,
            borderColor = CharacterBuilder.COLORS.CREAM03,
            border = 1,
            cornerRadius = 5,
        },
        {
            selectors = {"label-feature-desc"},
            width = "80%",
            height = "auto",
            halign = "center",
            valign = "top",
            textAlignment = "center",
            fontSize = 18,
            italics = true,
        },

        -- Selector target for skill selection etc.
        {
            selectors = {"choice-selection"},
            width = "100%",
            height = "auto",
            tmargin = 10,
            vpad = 8,
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 5,
            borderWidth = 1,
        },
        {
            selectors = {"choice-selection", "empty"},
            borderColor = CharacterBuilder.COLORS.GOLD,
        },
        {
            selectors = {"choice-selection", "filled"},
            fontSize = 18,
            textAlignment = "left",
            bold = false,
            hpad = 20,
            bgcolor = CharacterBuilder.COLORS.FILLED_ITEM_BG,
            borderColor = CharacterBuilder.COLORS.FILLED_ITEM_BORDER,
        },
        {
            selectors = {"choice-selection", "filled", "hover"},
            bgcolor = CharacterBuilder.COLORS.DELETE_WARN_BG,
            borderColor = CharacterBuilder.COLORS.DELETE_WARN_BORDER,
        },

        -- Options for skill selection etc.
        {
            selectors = {"choice-option"},
            width = "100%",
            height = "auto",
            tmargin = 10,
            vpad = 18,
            hpad = 20,
            textAlignment = "left",
            bold = true,
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 5,
            borderWidth = 1,
            borderColor = CharacterBuilder.COLORS.GOLD,
        },
        {
            selectors = {"choice-option", "selected"},
            borderColor = CharacterBuilder.COLORS.GOLD03,
        },

        -- For the right-side character pane / builder tab
        {
            selectors = {"charpanel-detail-header-label"},
            halign = "left",
            valign = "bottom",
            width = "90%",
            textAlignment = "left",
            vpad = 4,
            fontSize = 24,
            bgimage = true,
            border = {y1 = 2, y2 = 0, x1 = 0, x2 = 0},
            borderColor = Styles.textColor,
        },
        {
            selectors = {"charpanel-check"},
            halign = "left",
            valign = "center",
            hmargin = 150,
            width = 24,
            height = 24,
            bgimage = "icons/icon_common/icon_common_29.png",
            bgcolor = "clear",
        },
        {
            selectors = {"charpanel-check", "complete"},
            bgcolor = Styles.textColor,
        },
        {
            selectors = {"feature-detail-id-label"},
            width = "20%",
            halign = "left",
            textAlignment = "left",
            fontSize = 18,
        },
        {
            selectors = {"feature-detail-status-label"},
            width = "15%",
            hmargin = 2,
            fontSize = 18,
        },
        {
            selectors = {"feature-detail-detail-label"},
            width = "60%",
            halign= "left",
            hmargin = 2,
            textAlignment = "left",
            fontSize = 18,
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
            selectors = {"button-select"},
            width = CharacterBuilder.SIZES.SELECT_BUTTON_WIDTH,
            height = CharacterBuilder.SIZES.SELECT_BUTTON_HEIGHT,
            fontSize = 36,
            bold = true,
            cornerRadius = 5,
            border = 1,
            borderWidth = 1,
            borderColor = CharacterBuilder.COLORS.GOLD03,
            color = CharacterBuilder.COLORS.GOLD03,
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
            cornerRadius = 4,
        },
        {
            selectors = {"primary"},
            height = 48,
            fontSize = 20,
        },
        {
            selectors = {"secondary"},
            height = 36,
        },
        {
            selectors = {"multiline"},
            height = 48*3,
        },
    }
end

function CharacterBuilder._dropdownStyles()
    return {
        {
            selectors = {"dropdown"},
            bgcolor = "#191A18",
            borderColor = "#666663",
            fontSize = 36,
            cornerRadius = 4,
            borderWidth = 2,
        },
        {
            selectors = {"dropdownLabel"},
            textAlignment = "left",
            halign = "left",
        },
    }
end

function CharacterBuilder._characterPanelTabStyles()
    return {
        {
            selectors = {"char-tab-btn"},
            bgimage = true,
            border = 0,
            pad = 4,
            borderColor = CharacterBuilder.COLORS.CREAM03,
        },
        {
            selectors = {"char-tab-border"},
            width = "100%",
            height = "100%",
            border = 0,
            borderColor = CharacterBuilder.COLORS.CREAM03,
            bgimage = "panels/square.png",
            bgcolor = "clear",
        },
        {
            selectors = {"char-tab-border", "parent:selected"},
            border = {y1 = 0, y2 = 2, x1 = 2, x2 = 2},
        },
        {
            selectors = {"char-tab-icon"},
            width = 24,
            height = 24,
            bgcolor = CharacterBuilder.COLORS.GOLD,
        },
        {
            selectors = {"char-tab-label"},
        },
        {
            selectors = {"char-tab-icon", "selected"},
            bgcolor = CharacterBuilder.COLORS.CREAM03,
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
    mergeStyles(CharacterBuilder._dropdownStyles())
    mergeStyles(CharacterBuilder._characterPanelTabStyles())

    return styles
end