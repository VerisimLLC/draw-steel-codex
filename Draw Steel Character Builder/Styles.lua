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
    GRAY_TRANSPARENT = "#10110FF0",

    -- For selections like skills etc.
    FILLED_ITEM_BG = "#E9B86F0F",
    FILLED_ITEM_BORDER = "#E9B86F",

    DESTRUCTIVE_BG = "#2A1414",
    DESTRUCTIVE_BORDER = "#B94A30",
    DESTRUCTIVE_TEXT = "#ffffffcc", --"#D97166",
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

    PROGRESS_PIP_SIZE = 6,

    -- The little buttons top right on feature selector pane 3
    FEATURE_SELECT_WIDTH = 24,
    FEATURE_SELECT_HEIGHT = 24,

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

        --- Dialog
        {
            selectors = {"dialog"},
            halign = "center",
            valign = "center",
            bgcolor = "#111111ff",
            borderWidth = 2,
            borderColor = Styles.textColor,
            bgimage = "panels/square.png",
            flow = "vertical",
            hpad = 10,
            vpad = 10,
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
            selectors = {"detail-nav-panel", "wide"},
            width = 480,
        },
        {
            selectors = {"inner-detail-panel"},
            width = 580,
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
            vmargin = 8,
            flow = "vertical",
            bgimage = true,
            bgcolor = CBStyles.COLORS.GRAY_TRANSPARENT,
        },
        {
            selectors = {"detail-overview-panel", "has-kit"},
            bgcolor = "#666666",
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
        -- Drop target glow for individual target slots (when dragging options over)
        {
            selectors = {"feature-target", "drag-target"},
            brightness = 1.3,
        },
        {
            selectors = {"feature-target", "drag-target-hover"},
            brightness = 1.6,
            borderColor = CBStyles.COLORS.CREAM03,
        },
        -- Drop target glow for individual choice panels (when dragging targets over)
        {
            selectors = {"feature-choice", "drag-target"},
            brightness = 1.3,
        },
        {
            selectors = {"feature-choice", "drag-target-hover"},
            brightness = 1.6,
            borderColor = CBStyles.COLORS.CREAM03,
        },
        {
            selectors = {"feature-selector"},
            width = CBStyles.SIZES.FEATURE_SELECT_WIDTH,
            height = CBStyles.SIZES.FEATURE_SELECT_HEIGHT,
            halign = "right",
            valign = "top",
            hmargin = 4,
            vmargin = -4,
            bgcolor = "white",
        },
        {
            selectors = {"feature-selector", "remove"},
            bgimage = "icons/icon_tool/icon_tool_43.png",
            bgcolor = CBStyles.COLORS.GOLD03,
        },
        {
            selectors = {"feature-selector", "remove", "hover"},
            bgimage = "icons/icon_tool/icon_tool_44.png",
            bgcolor = "#fc0000",
        },
        {
            selectors = {"feature-selector", "select"},
            bgimage = "ui-icons/Plus.png", --"ui-icons/Back.png",
            bgcolor = "white",
        },
        {
            selectors = {"feature-selector", "select", "hover"},
            brightness = 1.5,
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

        -- Level Dividers in Class Panel
        {
            selectors = {"class-divider", "builder-header"},
            width = "100%",
            height = "auto",
            valign = "top",
            halign = "left",
            tmargin = 4,
        },
        {
            selectors = {"class-divider", "builder-check"},
            halign = "right",
            valign = "center",
            hmargin = 40,
            width = 24,
            height = 24,
            bgimage = "icons/icon_common/icon_common_29.png",
            bgcolor = "clear",
        },
        {
            selectors = {"class-divider", "builder-check", "complete"},
            bgcolor = CBStyles.COLORS.GOLD03,
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

        -- Progress Bar
        {
            selectors = {"progress-bar"},
            valign = "top",
            halign = "center",
            flow = "horizontal",
            width = "auto",
            height = CBStyles.SIZES.PROGRESS_PIP_SIZE,
        },
        {
            selectors = {"progress-pip"},
            valign = "top",
            halign = "center",
            hmargin = 2,
            width = CBStyles.SIZES.PROGRESS_PIP_SIZE,
            height = CBStyles.SIZES.PROGRESS_PIP_SIZE,
            bgimage = true,
            bgcolor = CBStyles.COLORS.GRAY02,
            border = 0,
            borderColor = CBStyles.COLORS.GOLD,
        },
        {
            selectors = {"progress-pip", "solo"},
            bgcolor = CBStyles.COLORS.BLACK,
            border = 1,
        },
        {
            selectors = {"progress-pip", "filled"},
            bgcolor = CBStyles.COLORS.GOLD03,
        },
        {
            selectors = {"progress-pip", "filled", "solo"},
            bgcolor = CBStyles.COLORS.CREAM03
        },

        -- Gradient-based progress pip styles (fill from bottom to top)
        -- For diamond shape (45° rotated), gradient goes from bottom corner to top corner
        {
            selectors = {"progress-pip", "progress-gradient-0"},
            bgcolor = "white",
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.0, y = 0.0},
                point_b = {x = 1.0, y = 1.0},
                stops = {
                    {position = 0.0, color = CBStyles.COLORS.BLACK},
                    {position = 1.0, color = CBStyles.COLORS.BLACK},
                },
            },
        },
        {
            selectors = {"progress-pip", "progress-gradient-10"},
            bgcolor = "white",
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.0, y = 0.0},
                point_b = {x = 1.0, y = 1.0},
                stops = {
                    {position = 0.0, color = CBStyles.COLORS.GOLD},
                    {position = 0.10, color = CBStyles.COLORS.GOLD},
                    {position = 0.10, color = CBStyles.COLORS.BLACK},
                    {position = 1.0, color = CBStyles.COLORS.BLACK},
                },
            },
        },
        {
            selectors = {"progress-pip", "progress-gradient-20"},
            bgcolor = "white",
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.0, y = 0.0},
                point_b = {x = 1.0, y = 1.0},
                stops = {
                    {position = 0.0, color = CBStyles.COLORS.GOLD},
                    {position = 0.20, color = CBStyles.COLORS.GOLD},
                    {position = 0.20, color = CBStyles.COLORS.BLACK},
                    {position = 1.0, color = CBStyles.COLORS.BLACK},
                },
            },
        },
        {
            selectors = {"progress-pip", "progress-gradient-30"},
            bgcolor = "white",
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.0, y = 0.0},
                point_b = {x = 1.0, y = 1.0},
                stops = {
                    {position = 0.0, color = CBStyles.COLORS.GOLD},
                    {position = 0.30, color = CBStyles.COLORS.GOLD},
                    {position = 0.30, color = CBStyles.COLORS.BLACK},
                    {position = 1.0, color = CBStyles.COLORS.BLACK},
                },
            },
        },
        {
            selectors = {"progress-pip", "progress-gradient-40"},
            bgcolor = "white",
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.0, y = 0.0},
                point_b = {x = 1.0, y = 1.0},
                stops = {
                    {position = 0.0, color = CBStyles.COLORS.GOLD},
                    {position = 0.40, color = CBStyles.COLORS.GOLD},
                    {position = 0.40, color = CBStyles.COLORS.BLACK},
                    {position = 1.0, color = CBStyles.COLORS.BLACK},
                },
            },
        },
        {
            selectors = {"progress-pip", "progress-gradient-50"},
            bgcolor = "white",
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.0, y = 0.0},
                point_b = {x = 1.0, y = 1.0},
                stops = {
                    {position = 0.0, color = CBStyles.COLORS.GOLD},
                    {position = 0.50, color = CBStyles.COLORS.GOLD},
                    {position = 0.50, color = CBStyles.COLORS.BLACK},
                    {position = 1.0, color = CBStyles.COLORS.BLACK},
                },
            },
        },
        {
            selectors = {"progress-pip", "progress-gradient-60"},
            bgcolor = "white",
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.0, y = 0.0},
                point_b = {x = 1.0, y = 1.0},
                stops = {
                    {position = 0.0, color = CBStyles.COLORS.GOLD},
                    {position = 0.60, color = CBStyles.COLORS.GOLD},
                    {position = 0.60, color = CBStyles.COLORS.BLACK},
                    {position = 1.0, color = CBStyles.COLORS.BLACK},
                },
            },
        },
        {
            selectors = {"progress-pip", "progress-gradient-70"},
            bgcolor = "white",
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.0, y = 0.0},
                point_b = {x = 1.0, y = 1.0},
                stops = {
                    {position = 0.0, color = CBStyles.COLORS.GOLD},
                    {position = 0.70, color = CBStyles.COLORS.GOLD},
                    {position = 0.70, color = CBStyles.COLORS.BLACK},
                    {position = 1.0, color = CBStyles.COLORS.BLACK},
                },
            },
        },
        {
            selectors = {"progress-pip", "progress-gradient-80"},
            bgcolor = "white",
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.0, y = 0.0},
                point_b = {x = 1.0, y = 1.0},
                stops = {
                    {position = 0.0, color = CBStyles.COLORS.GOLD},
                    {position = 0.80, color = CBStyles.COLORS.GOLD},
                    {position = 0.80, color = CBStyles.COLORS.BLACK},
                    {position = 1.0, color = CBStyles.COLORS.BLACK},
                },
            },
        },
        {
            selectors = {"progress-pip", "progress-gradient-90"},
            bgcolor = "white",
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.0, y = 0.0},
                point_b = {x = 1.0, y = 1.0},
                stops = {
                    {position = 0.0, color = CBStyles.COLORS.GOLD},
                    {position = 0.90, color = CBStyles.COLORS.GOLD},
                    {position = 0.90, color = CBStyles.COLORS.BLACK},
                    {position = 1.0, color = CBStyles.COLORS.BLACK},
                },
            },
        },
        {
            selectors = {"progress-pip", "progress-gradient-100"},
            bgcolor = "white",
            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.0, y = 0.0},
                point_b = {x = 1.0, y = 1.0},
                stops = {
                    {position = 0.0, color = CBStyles.COLORS.CREAM03},
                    {position = 1.0, color = CBStyles.COLORS.CREAM03},
                },
            },
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

        -- Dialog
        {
            selectors = {"dialog-header"},
            width = "100%",
            height = 30,
            halign = "center",
            valign = "top",
            fontSize = 24,
            textAlignment = "center",
            bold = true,
        },
        {
            selectors = {"dialog-message"},
            width = "100%",
            height = 80,
            halign = "center",
            valign = "center",
            textAlignment = "center",
            fontSize = 18,
            textWrap = true,
        },

        -- Overview panel
        {
            selectors = {"overview"},
            width = "100%",
            height = "auto",
            hpad = 12,
            textAlignment = "left",
        },
        {
            selectors = {"info", "overview", "detail-header"},
            fontSize = 22,
            bold = true,
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

        -- Kit bonus selectors
        {
            selectors = {"bonus-selector"},
            color = CBStyles.COLORS.GRAY02,
            bgimage = true,
            borderColor = CBStyles.COLORS.GRAY02,
            border = 1,
            cornerRadius = 3,
        },
        {
            selectors = {"bonus-selector", "hover", "~selected"},
            brightness = 1.5,
        },
        {
            selectors = {"bonus-selector", "selected"},
            color = CBStyles.COLORS.GOLD03,
            borderColor = CBStyles.COLORS.CREAM03,
        },

        -- Class panel level dividers
        {
            selectors = {"class-divider", "builder-header"},
            halign = "left",
            valign = "bottom",
            width = "90%",
            textAlignment = "left",
            vpad = 4,
            fontSize = 20,
            color = CBStyles.COLORS.GOLD03,
            bgimage = true,
            border = {y1 = 2, y2 = 0, x1 = 0, x2 = 0},
            borderColor = CBStyles.COLORS.GOLD03,
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
            width = "30%",
            halign = "left",
            valign = "top",
            textAlignment = "topleft",
            fontSize = 18,
        },
        {
            selectors = {"charpanel", "builder-status"},
            width = "13%",
            valign = "top",
            textAlignment = "topleft",
            hmargin = 2,
            fontSize = 18,
        },
        {
            selectors = {"charpanel", "builder-detail"},
            width = "54%",
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
            selectors = {"dialog"},
            width = 120,
            height = 36,
            cornerRadius = 5,
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
        {  -- TODO: Rework into "selector", below when we don't need this button
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
        {
            selectors = {"selector"},
            valign = "top",
            halign = "center",
            bmargin = CBStyles.SIZES.CATEGORY_BUTTON_MARGIN,
            fontSize = 24,
            bold = false,
            cornerRadius = 5,
            border = 1,
            borderWidth = 1,
            borderColor = CBStyles.COLORS.GOLD03,
            color = CBStyles.COLORS.GOLD03,
        },
        {
            selectors = {"selector", "destructive"},
            borderColor = CBStyles.COLORS.DESTRUCTIVE_BORDER,
            bgcolor = CBStyles.COLORS.DESTRUCTIVE_BG,
            color = CBStyles.COLORS.DESTRUCTIVE_TEXT,
        },
        {
            selectors = {"destructive", "hover"},
            bgcolor = "#330000",
            color = "#9F0000",
        }
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
        -- {
        --     selectors = {"secondary"},
        --     height = 36,
        -- },
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
        -- {
        --     selectors = {"dropdownLabel"},
        --     textAlignment = "left",
        --     halign = "left",
        -- },
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

function CBStyles.SelectorButtonOverrides()
    local styles = {
        {
            selectors = {"parent:destructive"},
            borderColor = CBStyles.COLORS.DESTRUCTIVE_BORDER,
            bgcolor = CBStyles.COLORS.DESTRUCTIVE_BG,
        },
        {
            selectors = {"parent:destructive"},
            color = CBStyles.COLORS.DESTRUCTIVE_TEXT,
        },
    }
    return styles
end
