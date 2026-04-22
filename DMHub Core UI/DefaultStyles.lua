local mod = dmhub.GetModLoading()

--- DefaultStyles — registers ThemeEngine's default color scheme and default theme.
--- These act as the ultimate fallback for sparse/inheriting third-party registrations
--- and define the canonical color names and font slots a scheme/theme is expected to
--- cover. Intentionally minimal for now; grow as the engine absorbs more of the UI.

-- =============================================================================
-- Default color scheme — canonical color name set
-- =============================================================================

ThemeEngine.RegisterColorScheme{
    id          = "default",
    name        = "Default",
    description = "The Draw Steel default color palette.",
    colors = {
        -- surfaces
        background    = "#080B09",
        backgroundAlt = "#191A18",

        -- borders
        border        = "#666663",

        -- text
        text          = "#DFCFC0",
        textMuted     = "#666663",
        textInverse   = "#040807",

        -- accent family
        accent        = "#966D4B",
        accentStrong  = "#F1D3A5",
        accentHover   = "#E9B86F",

        -- semantic statuses
    },
    gradients = {
        panelRadial = {
            type = "radial",
            point_a = {x = 0.5, y = 0.5},
            point_b = {x = 0.5, y = 1.0},
            stops = {
                {position = -0.01, color = "#1c1c1c"},
                {position = 0.00,  color = "#1c1c1c"},
                {position = 0.12,  color = "#191919"},
                {position = 0.25,  color = "#161616"},
                {position = 0.37,  color = "#131413"},
                {position = 0.50,  color = "#101110"},
                {position = 0.62,  color = "#0d0f0d"},
                {position = 0.75,  color = "#0b0d0b"},
                {position = 0.87,  color = "#090c0a"},
                {position = 1.00,  color = "#080b09"},
            },
        },
    },
}

-- =============================================================================
-- Default theme — canonical font slots + base widget rules
-- =============================================================================

ThemeEngine.RegisterTheme{
    id          = "default",
    name        = "Default",
    description = "The Draw Steel default theme.",
    colorScheme = "default",

    fonts = {
        heading = "Berling",
        label   = "Berling",
        input   = "Inter",
        number  = "Newzald",
    },

    styles = {
        -- Base widget rules. Variants and utilities get appended later as the
        -- engine grows to cover more of the UI.

        --[[ Panels ]]
        {
            selectors = {"panel"},
            bgcolor = "@background",
        },
        {
            selectors = {"panel", "radial-gradient"},
            bgimage = true,
            gradient = "@panelRadial",
        },
        {
            selectors = {"panel", "border"},
            bgimage = true,
            border = 1,
            borderColor = "@border",
        },

        --[[ Labels ]]
        {
            selectors = {"label"},
            fontFace = "@label",
            fontSize = 14,
            color = "@text"
        },
        {
            selectors = {"label", "number"},
            fontFace = "@number",
        },

        --[[ Buttons ]]
        {
            selectors = {"button"},
            fontFace = "@label",
            fontSize = 14,
            color = "@text",
            bgcolor = "@accent",
            borderColor = "@border"
        },

        --[[ Inputs ]]
        {
            selectors = {"input"},
            fontFace = "@input", 
            fontSize = 14, 
            color = "@text",
            bgcolor = "@backgroundAlt",
            borderColor = "@border"
        },

        --[[ Dropdowns ]]
        {
            selectors = {"dropdown"},
            fontFace = "@input",
            fontSize = 14,
            color = "@text",
            bgcolor = "@backgroundAlt",
            borderColor = "@border"
        },
    },
}
