--[[
    Styles for Character Builder
]]
CBStyles = RegisterGameType("CBStyles")

--- Set this to true to draw layout helper borders around panels that have none
local DEBUG_PANEL_BG = false

CBStyles.COLORS = {
    BLACK = "#000000",
    BLACK03 = "#191A18",
    CREAM = "#BC9B7B",
    CREAM03 = "#DFCFC0",
    GOLD = "#966D4B",
    GOLD03 = "#F1D3A5",
    GRAY02 = "#666663",
    PANEL_BG = "#080B09",

    -- For selections like skills etc.
    FILLED_ITEM_BG = "#E9B86F0F",
    FILLED_ITEM_BORDER = "#E9B86F",

    DELETE_WARN_BG = "#660000",
    DELETE_WARN_BORDER = "#CC3333",
}

CBStyles.SIZES = {
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
CBStyles.SIZES.BUTTON_PANEL_WIDTH = CBStyles.SIZES.ACTION_BUTTON_WIDTH + 60
CBStyles.SIZES.CENTER_PANEL_WIDTH = "100%-" .. (30 + CBStyles.SIZES.BUTTON_PANEL_WIDTH + CBStyles.SIZES.CHARACTER_PANEL_WIDTH)

--- Prepend root selectors to each style's selectors array
--- @param rootSelectors string|table The selectors to prepend
--- @param styles table The list of styles to modify
--- @return table styles The modified styles array
local function _applyRootSelectors(rootSelectors, styles)
    local rootArray = type(rootSelectors) == "table" and rootSelectors or {rootSelectors}

    for _, style in ipairs(styles) do
        if style.selectors then
            local newSelectors = {}
            table.move(rootArray, 1, #rootArray, 1, newSelectors)
            table.move(style.selectors, 1, #style.selectors, #rootArray + 1, newSelectors)
            style.selectors = newSelectors
        else
            style.selectors = rootArray
        end
    end

    return styles
end

--- Generate base styles for the character builder
--- @return table[] Array of style definitions
local function _baseStyles()
    return {
        {
            selectors = {"builder-base"},
            fontSize = 14,
            fontFace = "Berling",
            color = Styles.textColor,
            bold = false,
        },
    }
end

--- Generate panel styles with panel-base root selector
--- @return table[] Array of style definitions
local function _panelStyles()

    local starburstGradient = gui.Gradient{
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
    }

    return _applyRootSelectors("panel-base", {
        {
            selectors = {},
            height = "auto",
            width = "auto",
            valign = "top",
            halign = "center",
            pad = 0,
            margin = 0,
            bgimage = DEBUG_PANEL_BG and "panels/square.png",
            border = DEBUG_PANEL_BG and 1 or 0
        },
        {
            selectors = {"container"},
            width = "100%",
            height = "auto",
            halign = "left",
            flow = "vertical",
        },
        {
            selectors = {"border"},
            borderColor = CBStyles.COLORS.CREAM,
            border = 2,
            cornerRadius = 10,
        },

        -- Detail Panels
        {
            selectors = {"detail-panel"},
            width = "100%",
            height = "100%",
            flow = "horizontal",
            borderColor = "yellow",
        },
        {
            selectors = {"detail-nav-panel"},
            height = "100%-12",
            width = CBStyles.SIZES.BUTTON_PANEL_WIDTH + 20,
            tmargin = 12,
            flow = "vertical",
            borderColor = "teal",
        },
        {
            selectors = {"inner-detail-panel"},
            width = 440,
            height = "100%",
            valign = "center",
            halign = "center",
            borderColor = "teal",
        },
        {
            selectors = {"inner-detail-panel", "wide"},
            width = 660,
        },
        {
            selectors = {"detail-overview-panel"},
            width = "100%",
            height = "100%",
            valign = "center",
            halign = "center",
            bgcolor = "white",
        },
        {
            selectors = {"detail-overview-labels"},
            width = "100%-4",
            height = "auto",
            halign = "center",
            valign = "bottom",
            vmargin = 32,
            vpad = 8,
            flow = "vertical",
            bgimage = true,
        },

        -- Feature selectors
        {
            selectors = {"feature-target"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 10,
            vpad = 8,
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 5,
            borderWidth = 1,
            borderColor = CBStyles.COLORS.GOLD,
        },
        {
            selectors = {"feature-target", "filled"},
            bgcolor = CBStyles.COLORS.FILLED_ITEM_BG,
            borderColor = CBStyles.COLORS.FILLED_ITEM_BORDER,
        },
        {
            selectors = {"feature-target", "filled", "selected"},
            brightness = 1.8,
        },
        {
            selectors = {"feature-choice-container"},
            width = "100%-14",
            halign = "left",
            flow = "vertical",
        },
        {
            selectors = {"feature-choice"},
            width = "100%",
            height = "auto",
            halign = "left",
            flow = "vertical",
            tmargin = 10,
            vpad = 8,
            bgimage = true,
            bgcolor = "clear",
            cornerRadius = 5,
            borderWidth = 1,
            borderColor = CBStyles.COLORS.GOLD,
        },
        {
            selectors = {"feature-choice", "selected"},
            borderColor = CBStyles.COLORS.GOLD03,
        },
        {
            selectors = {"feature-choice", "filtered"},
            collapsed = true,
        },

        -- Attribute editor
        {
            selectors = {"attr-container"},
            width = "100%",
            height = "auto",
        },
        {
            selectors = {"attr-item"},
            width = "18%",
            height = "auto",
        },
        {
            selectors = {"attr-lock"},
            width = 24,
            height = 24,
            halign = "right",
            valign = "top",
            hmargin = 18,
            vmargin = 18,
            bgimage = "game-icons/padlock.png",
            bgcolor = "clear",
        },
        {
            selectors = {"attr-lock", "parent:locked"},
            bgcolor = CBStyles.COLORS.GRAY02,
        },

        -- Right-side character panel
        {
            selectors = {"charpanel", "tab-content"},
            width = "100%-20",
            height = "100% available",
            hpad = 8,
            halign = "center",
            valign = "top",
            flow = "vertical",
        },
        {
            selectors = {"builder-content-entry"},
            width = "100%-20",
            halign = "left",
            hmargin = 12,
        },
        {
            selectors = {"charpanel", "builder-header"},
            width = "100%",
            height = "auto",
            valign = "top",
            halign = "left",
            tmargin = 8,
        },
        {
            selectors = {"charpanel", "builder-check"},
            halign = "right",
            valign = "center",
            hmargin = 40,
            width = 24,
            height = 24,
            bgimage = "icons/icon_common/icon_common_29.png",
            bgcolor = "clear",
        },
        {
            selectors = {"charpanel", "builder-check", "complete"},
            bgcolor = Styles.textColor,
        },
        {
            selectors = {"charpanel", "builder-feature-content"},
            width = "100%",
            height = "auto",
            valign = "top",
            halign = "left",
            flow = "horizontal",
            tmargin = 4,
        },

        -- Contains all the tab content
        {
            selectors = {CharacterBuilder.CONTROLLER_CLASS},
            bgcolor = "#ffffff",
            bgimage = true,
            gradient = starburstGradient,
        },
    })
end

--- Generate label styles with label root selector
--- @return table[] Array of style definitions
local function _labelStyles()
    return _applyRootSelectors("label", {
        {
            selectors = {},
            height = "auto",
            textAlignment = "center",
            fontSize = 14,
            color = Styles.textColor,
            bold = false,
        },
        {
            selectors = {"info"},
            hpad = 12,
            fontSize = 18,
            textAlignment = "left",
            bgimage = true,
            bgcolor = "#10110FE5",
        },
        {
            selectors = {"header"},
            fontSize = 40,
            bold = true,
        },
        {
            selectors = {"charname"},
            width = "98%",
            height = "auto",
            halign = "center",
            valign = "top",
            textAlignment = "center",
            fontSize = 24,
            tmargin = 12,
        },

        -- Feature names & descriptions for selection panels
        {
            selectors = {"feature-header", "name"},
            width = "100%",
            height = "auto",
            valign = "top",
            vpad = 14,
            bmargin = 10,
            textAlignment = "center",
            fontSize = 20,
            bgimage = true,
            borderColor = CBStyles.COLORS.CREAM03,
            border = 1,
            cornerRadius = 5,
        },
        {
            selectors = {"feature-header", "desc"},
            width = "94%",
            height = "auto",
            halign = "center",
            valign = "top",
            textAlignment = "center",
            fontSize = 16,
            italics = true,
        },

        -- Selector target for skill selection etc.
        {
            selectors = {"feature-target"},
            width = "98%",
            height = "auto",
            halign = "center",
        },
        {
            selectors = {"feature-target", "desc"},
            fontSize = 14,
            bold = false,
            italics = true,
        },
        {
            selectors = {"feature-target", "parent:filled"},
            halign = "left",
            hpad = 20,
            textAlignment = "left",
        },
        {
            selectors = {"feature-target", "parent:filled", "~desc"},
            fontSize = 22,
            bold = true,
        },
        {
            selectors = {"feature-target", "ability-card"},
            bgcolor = "clear",
            border = 0,
        },

        -- Options for skill selection etc.
        {
            selectors = {"feature-choice"},
            width = "100%",
            height = "auto",
            halign = "left",
            hmargin = 8,
            textAlignment = "left",
            fontSize = 22,
            bold = true,
        },
        {
            selectors = {"feature-choice", "desc"},
            width = "100%-16",
            fontSize = 14,
            bold = false,
            italics = true,
        },

        -- Attribute editor
        {
            selectors = {"attr-name"},
            width = "98%",
            height = "auto",
            halign = "center",
            bold = false,
        },
        {
            selectors = {"attr-value"},
            width = 80,
            height = 80,
            halign = "center",
            fontSize = 32,
            textAlignment = "center",
            bgimage = true,
            bgcolor = "clear",
            borderWidth = 2,
            cornerRadius = 10,
            borderColor = CBStyles.COLORS.GOLD,
        },
        {
            selectors = {"attr-value", "parent:locked"},
            color = CBStyles.COLORS.GRAY02,
            borderColor = CBStyles.COLORS.GRAY02,
        },
        {
            selectors = {"attr-value", "drag-target"},
            brightness = 1.5,
        },
        {
            selectors = {"attr-value", "drag-target-hover"},
            brightness = 2.0,
            borderColor = CBStyles.COLORS.CREAM03,
        },

        -- For the right-side character panel / builder tab
        {
            selectors = {"charpanel", "desc-item-label"},
            width = "50%",
            height = "auto",
            halign = "left",
            vpad = CBStyles.SIZES.DESCRIPTION_LABEL_PAD,
            textAlignment = "left",
            fontSize = 18,
            bold = true,
        },
        {
            selectors = {"charpanel", "desc-item-detail"},
            width = "50%",
            height = "auto",
            halign = "left",
            vpad = CBStyles.SIZES.DESCRIPTION_LABEL_PAD,
            textAlignment = "left",
            fontSize = 18,
        },
        {
            selectors = {"charpanel", "builder-header"},
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
            selectors = {"charpanel", "builder-category"},
            width = "25%",
            halign = "left",
            valign = "top",
            textAlignment = "topleft",
            fontSize = 18,
        },
        {
            selectors = {"charpanel", "builder-status"},
            width = "10%",
            valign = "top",
            textAlignment = "topleft",
            hmargin = 2,
            fontSize = 18,
        },
        {
            selectors = {"charpanel", "builder-detail"},
            width = "60%",
            halign = "left",
            valign = "top",
            hmargin = 2,
            textAlignment = "topleft",
            fontSize = 18,
        },
    })
end

--- Generate button styles with button root selector
--- @return table[] Array of style definitions
local function _buttonStyles()
    return _applyRootSelectors("button", {
        {
            selectors = {},
            border = 1,
            borderWidth = 1,
        },
        {
            selectors = {"category"},
            width = CBStyles.SIZES.ACTION_BUTTON_WIDTH,
            height = CBStyles.SIZES.ACTION_BUTTON_HEIGHT,
            halign = "center",
            valign = "top",
            bmargin = 20,
            fontSize = 24,
            cornerRadius = 5,
            textAlignment = "left",
            bold = false,
        },
        {
            selectors = {"select"},
            width = CBStyles.SIZES.SELECT_BUTTON_WIDTH,
            height = CBStyles.SIZES.SELECT_BUTTON_HEIGHT,
            fontSize = 36,
            bold = true,
            cornerRadius = 5,
            border = 1,
            borderWidth = 1,
            borderColor = CBStyles.COLORS.GOLD03,
            color = CBStyles.COLORS.GOLD03,
        },
        {
            selectors = {"disabled"},
            borderColor = CBStyles.COLORS.GRAY02,
            color = CBStyles.COLORS.GRAY02,
        },
        -- {
        --     selectors = {"available"},
        --     borderColor = CBStyles.COLORS.CREAM,
        --     color = CBStyles.COLORS.GOLD,
        -- },
        -- {
        --     selectors = {"unavailable"},
        --     borderColor = CBStyles.COLORS.GRAY02,
        --     color = CBStyles.COLORS.GRAY02,
        -- }
    })
end

--- Generate input styles with input root selector
--- @return table[] Array of style definitions
local function _inputStyles()
    return _applyRootSelectors("input", {
        {
            selectors = {},
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
    })
end

--- Generate dropdown styles with dropdown root selector
--- @return table[] Array of style definitions
local function _dropdownStyles()
    return _applyRootSelectors("dropdown", {
        {
            selectors = {},
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
        {
            selectors = {"primary"},
            height = 48,
            fontSize = 20,
        },
    })
end

--- Generate character panel tab styles
--- @return table[] Array of style definitions
local function _characterPanelTabStyles()
    return _applyRootSelectors("charpanel", {
        {
            selectors = {"tab-button"},
            bgimage = true,
            border = 0,
            pad = 4,
            borderColor = CBStyles.COLORS.CREAM03,
        },
        {
            selectors = {"tab-border"},
            width = "100%",
            height = "100%",
            border = 0,
            borderColor = CBStyles.COLORS.CREAM03,
            bgimage = "panels/square.png",
            bgcolor = "clear",
        },
        {
            selectors = {"tab-border", "parent:selected"},
            border = {y1 = 0, y2 = 2, x1 = 2, x2 = 2},
        },
        {
            selectors = {"tab-icon"},
            width = 24,
            height = 24,
            bgcolor = CBStyles.COLORS.GOLD,
        },
        {
            selectors = {"tab-label"},
        },
        {
            selectors = {"tab-icon", "selected"},
            bgcolor = CBStyles.COLORS.CREAM03,
        },
    })
end

--- Return the styling for the character builder
--- @return table[] Array of style definitions
function CBStyles.GetStyles()
    local styles = {}

    local function mergeStyles(sourceStyles)
        for _, style in ipairs(sourceStyles) do
            styles[#styles + 1] = style
        end
    end

    mergeStyles(_baseStyles())
    mergeStyles(_panelStyles())
    mergeStyles(_labelStyles())
    mergeStyles(_buttonStyles())
    mergeStyles(_inputStyles())
    mergeStyles(_dropdownStyles())
    mergeStyles(_characterPanelTabStyles())

    return styles
end