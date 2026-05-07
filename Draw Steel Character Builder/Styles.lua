--[[
    Styles for Character Builder
]]
CBStyles = RegisterGameType("CBStyles")

--- Set this to true to draw layout helper borders around panels that have none
local DEBUG_PANEL_BG = false

-- Recolored from gold to cream tones. The GOLD* keys are kept (to avoid
-- touching every call site) but now point at the shared Cream palette from
-- Styles.lua:
--   Cream01 = #F3EDE7 (lightest)
--   Cream02 = #DFCFC0 (mid)
--   Cream03 = #BC9B7B (darkest / tan)
CBStyles.COLORS = {
    BLACK = "#000000",
    BLACK02 = "#10110F",
    BLACK03 = "#191A18",
    BLACK04 = "#040807",
    CREAM = "srgb:#BC9B7B",
    CREAM03 = "srgb:#DFCFC0",
    GOLD = "srgb:#DFCFC0",     -- was #966D4B (dark gold)  -> Cream02 (mid cream)
    GOLD03 = "srgb:#F3EDE7",   -- was #F1D3A5 (light gold) -> Cream01 (lightest)
    GOLD04 = "srgb:#BC9B7B",   -- was #E9B86F (mid gold)   -> Cream03 (darker, used on hover bg)
    GRAY02 = "#666663",
    PANEL_BG = "#080B09",
    GRAY_TRANSPARENT = "#10110FF3",

    -- For selections like skills etc.
    FILLED_ITEM_BG = "srgb:#DFCFC01A",
    FILLED_ITEM_BORDER = "srgb:#DFCFC0",

    DESTRUCTIVE_BG = "#2A1414",
    DESTRUCTIVE_BORDER = "#B94A30",
    DESTRUCTIVE_TEXT = "#ffffffcc", --"#D97166",
}

CBStyles.SIZES = {
    -- Panels
    CHARACTER_PANEL_WIDTH = 447,
    CHARACTER_PANEL_HEADER_HEIGHT = 310,

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
            color = "@fgStrong",
            bold = false,
        },
    }
end

--- Generate panel styles with panel-base root selector
--- @return table[] Array of style definitions
local function _panelStyles()
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
            borderColor = "@border",
            border = 2,
            cornerRadius = 10,
        },

        --- Dialog
        {
            selectors = {"dialog"},
            halign = "center",
            valign = "center",
            bgcolor = "@bg",
            borderWidth = 2,
            borderColor = "@fgStrong",
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
            bgcolor = "@fgMuted",
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
            borderColor = "@accent",
        },
        {
            selectors = {"feature-target", "filled"},
            bgcolor = "@bgAlt",
            borderColor = "@borderInverse",
        },
        {
            selectors = {"feature-target", "filled", "selected"},
            borderColor = "@border",
            brightness = 1.4,
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
            bgcolor = "@bg", --"clear",
            cornerRadius = 5,
            borderWidth = 1,
            borderColor = "@accent",
        },
        {
            selectors = {"feature-choice", "selected"},
            borderColor = "@fgStrong",
        },
        {
            selectors = {"feature-choice", "hover"},
            bgcolor = "@accentHover",
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
            borderColor = "@fgStrong",
        },
        -- Drop target glow for individual choice panels (when dragging targets over)
        {
            selectors = {"feature-choice", "drag-target"},
            brightness = 1.3,
        },
        {
            selectors = {"feature-choice", "drag-target-hover"},
            brightness = 1.6,
            borderColor = "@fgStrong",
        },
        {
            selectors = {"feature-selector"},
            width = CBStyles.SIZES.FEATURE_SELECT_WIDTH,
            height = CBStyles.SIZES.FEATURE_SELECT_HEIGHT,
            halign = "right",
            valign = "top",
            hmargin = 4,
            vmargin = 0,
            bgcolor = "white",
        },
        {
            selectors = {"feature-selector", "remove"},
            bgimage = "icons/icon_tool/icon_tool_43.png",
            bgcolor = "@fgStrong",
        },
        {
            selectors = {"feature-selector", "remove", "hover"},
            bgimage = "icons/icon_tool/icon_tool_44.png",
            bgcolor = "@danger",
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
            bgcolor = "@fgMuted",
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
            bgcolor = "@fgStrong",
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
            bgcolor = "@fgStrong",
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
            bgcolor = "@disabled",
            border = 0,
            borderColor = "@accent",
        },
        {
            selectors = {"progress-pip", "solo"},
            -- bgcolor = "@disabled",
            border = 1,
        },
        {
            selectors = {"progress-pip", "secondary"},
            -- bgcolor = "@disabled",
            border = 0,
        },
        {
            selectors = {"progress-pip", "filled"},
            bgcolor = "@accent",
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
                    {position = 0.0, color = "@bg"},
                    {position = 1.0, color = "@bg"},
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
                    {position = 0.0, color = "@accent"},
                    {position = 0.10, color = "@accent"},
                    {position = 0.10, color = "@bg"},
                    {position = 1.0, color = "@bg"},
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
                    {position = 0.0, color = "@accent"},
                    {position = 0.20, color = "@accent"},
                    {position = 0.20, color = "@bg"},
                    {position = 1.0, color = "@bg"},
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
                    {position = 0.0, color = "@accent"},
                    {position = 0.30, color = "@accent"},
                    {position = 0.30, color = "@bg"},
                    {position = 1.0, color = "@bg"},
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
                    {position = 0.0, color = "@accent"},
                    {position = 0.40, color = "@accent"},
                    {position = 0.40, color = "@bg"},
                    {position = 1.0, color = "@bg"},
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
                    {position = 0.0, color = "@accent"},
                    {position = 0.50, color = "@accent"},
                    {position = 0.50, color = "@bg"},
                    {position = 1.0, color = "@bg"},
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
                    {position = 0.0, color = "@accent"},
                    {position = 0.60, color = "@accent"},
                    {position = 0.60, color = "@bg"},
                    {position = 1.0, color = "@bg"},
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
                    {position = 0.0, color = "@accent"},
                    {position = 0.70, color = "@accent"},
                    {position = 0.70, color = "@bg"},
                    {position = 1.0, color = "@bg"},
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
                    {position = 0.0, color = "@accent"},
                    {position = 0.80, color = "@accent"},
                    {position = 0.80, color = "@bg"},
                    {position = 1.0, color = "@bg"},
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
                    {position = 0.0, color = "@accent"},
                    {position = 0.90, color = "@accent"},
                    {position = 0.90, color = "@bg"},
                    {position = 1.0, color = "@bg"},
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
                    {position = 0.0, color = "@fgStrong"},
                    {position = 1.0, color = "@fgStrong"},
                },
            },
        },

        -- Contains all the tab content
        {
            selectors = {CharacterBuilder.CONTROLLER_CLASS},
            bgcolor = "white",
            bgimage = true,
            gradient = "@surfaceRadial",
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
            color = "@fgStrong",
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
            tmargin = 6,
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
            borderColor = "@fgStrong",
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
            hpad = 8,
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
        -- {
        --     selectors = {"feature-choice", "hover"},
        --     color = "@bg",
        -- },
        {
            selectors = {"feature-choice", "parent:hovering"},
            color = "@bg",
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
            borderColor = "@accent",
        },
        {
            selectors = {"attr-value", "parent:locked"},
            color = "@fgMuted",
            borderColor = "@fgMuted",
        },
        {
            selectors = {"attr-value", "drag-target"},
            brightness = 1.5,
        },
        {
            selectors = {"attr-value", "drag-target-hover"},
            brightness = 2.0,
            borderColor = "@fgStrong",
        },

        -- Kit bonus selectors
        {
            selectors = {"bonus-selector"},
            color = "@fgMuted",
            bgimage = true,
            borderColor = "@fgMuted",
            border = 1,
            cornerRadius = 3,
        },
        {
            selectors = {"bonus-selector", "hover", "~selected"},
            brightness = 1.5,
        },
        {
            selectors = {"bonus-selector", "selected"},
            color = "@fgStrong",
            borderColor = "@fgStrong",
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
            color = "@fgStrong",
            bgimage = true,
            border = {y1 = 2, y2 = 0, x1 = 0, x2 = 0},
            borderColor = "@fgStrong",
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
            borderColor = "@fgStrong",
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
            borderColor = "@fgStrong",
            color = "@fgStrong",
        },
        {
            selectors = {"disabled"},
            borderColor = "@fgMuted",
            color = "@fgMuted",
        },
        {
            selectors = {"selector"},
            valign = "top",
            halign = "center",
            width = CBStyles.SIZES.CATEGORY_BUTTON_WIDTH,
            height = CBStyles.SIZES.CATEGORY_BUTTON_HEIGHT,
            bmargin = CBStyles.SIZES.CATEGORY_BUTTON_MARGIN,
            fontSize = 24,
            borderWidth = 1,
            cornerRadius = 2,
            borderColor = "@accent",
            color = "@accent",
        },
        {
            selectors = {"selector", "hover"},
            bgcolor = "@accentHover",
            color = "@bg",
        },
        -- {
        --     selectors = {"selector", "destructive"},
        --     borderColor = CBStyles.COLORS.DESTRUCTIVE_BORDER,
        --     bgcolor = CBStyles.COLORS.DESTRUCTIVE_BG,
        --     color = CBStyles.COLORS.DESTRUCTIVE_TEXT,
        -- },
        {
            selectors = {"destructive", "hover"},
            bgcolor = "@danger",
            borderColor = "@danger",
            color = "white",
        }
    })
end

--- Generate input styles with input root selector
--- @return table[] Array of style definitions
local function _inputStyles()
    return _applyRootSelectors("input", {
        {
            selectors = {},
            bgcolor = "@bg",
            borderColor = "@border",
            cornerRadius = 4,
        },
        {
            selectors = {"primary"},
            height = 48,
            fontSize = 20,
        },
        {
            selectors = {"charname"},
            width = "80%",
            height = "auto",
            halign = "center",
            valign = "top",
            bgcolor = "clear",
            textAlignment = "center",
            fontSize = 24,
            tmargin = 6,
            vpad = 2,
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

--- The CB label base rule sets textAlignment/fontSize for every label in the
--- cascade, which leaks into dropdownLabel (closed control) and dropdownOption
--- (open list rows). These overrides defeat that leak so dropdowns render with
--- the default theme's intended look.
--- @return table[] Array of style definitions
local function _dropdownLabelOverrides()
    return {
        {
            selectors = {"label", "dropdownLabel"},
            textAlignment = "left",
            fontSize = 18,
        },
        {
            selectors = {"label", "dropdownOption"},
            textAlignment = "left",
            fontSize = 18,
        },
    }
end

--- Generate character panel tab styles
--- @return table[] Array of style definitions
local function _characterPanelTabStyles()
    return _applyRootSelectors("charpanel", {
        {
            selectors = {"tab-button"},
            bgimage = true,
            bgcolor = "clear",
            border = 0,
            pad = 4,
        },
        {
            selectors = {"tab-icon"},
            width = 24,
            height = 24,
            bgcolor = "@accent",
        },
        {
            selectors = {"tab-label"},
        },
        {
            selectors = {"tab-icon", "selected"},
            bgcolor = "@fgStrong",
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
    mergeStyles(_dropdownLabelOverrides())
    mergeStyles(_characterPanelTabStyles())

    return styles
end

function CBStyles.SelectorButtonOverrides()
    local styles = {
        {
            selectors = {"parent:destructive"},
            borderColor = "@danger",
            bgcolor = "@danger",
        },
        {
            selectors = {"parent:destructive"},
            color = "@fgInverse",
        },
    }
    return styles
end
