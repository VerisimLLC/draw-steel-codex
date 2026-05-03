local mod = dmhub.GetModLoading()

--- DefaultStyles -- registers ThemeEngine's default color scheme and default theme.
---

-- =============================================================================
-- Default color scheme -- usage-named colors and gradients
-- =============================================================================

ThemeEngine.RegisterColorScheme{
    id          = "default",
    name        = "Default",
    description = "The Draw Steel default color palette.",
    colors = {
        -- Surfaces
        bg            = "#080B09",
        bgAlt         = "#191A18",
        bgInverse     = "#9C9C9C",

        -- Foreground / text
        fg            = "#CECECE",
        fgStrong      = "#EFEFEF",
        fgMuted       = "#9F9F9B",
        fgPending     = "#999999",
        fgInverse     = "#040404",

        -- Borders
        border        = "#DFDFDF",
        borderInverse = "#666666",

        -- Accent + interactive
        accent        = "#999999",
        accentHover   = "#DDDDDD",

        -- Status
        success       = "#6BA84F", -- Also healthy, good, etc.
        info          = "#E9C868",
        warning       = "#E08A2E", -- Also winded, etc.
        danger        = "#C73131", -- Also dying, bad, etc.

        -- Disabled
        disabled      = "#343434",

        --[[
            Implementation status for abilities. Users will expect these to be
            consistent across color schemes so the best approach is to avoid
            redefining these unless they would be difficult to see in your
            color scheme.
        ]]--
        implStatus0   = "#F82FCD",
        implStatus1   = "#FF0000",
        implStatus2   = "#CD7F32",
        implStatus3   = "#C0C0C0",
        implStatus4   = "#FFD700",
    },
    gradients = {
        -- Surfaces
        surfaceRadial = {
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

        surfaceLinear = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 1},
            stops = {
                {position = 0, color = "#1A1B19"},
                {position = 1, color = "#050605"},
            },
        },

        -- Bars
        -- Important: This is used in the title bar
        barTrack = {
            point_a = {x = -0.02, y = 0},
            point_b = {x = 1.02,  y = 0},
            stops = {
                {position = 0, color = "#060605"},
                {position = 1, color = "@bgAlt"},
            },
        },

        -- Alpha-fade masks (utility)
        maskHorizontal = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 0},
            stops = {
                {position = 0,   color = "#FFFFFF00"},
                {position = 0.2, color = "#FFFFFFFF"},
                {position = 0.8, color = "#FFFFFFFF"},
                {position = 1,   color = "#FFFFFF00"},
            },
        },

        maskVertical = {
            point_a = {x = 0, y = 0},
            point_b = {x = 0, y = 1},
            stops = {
                {position = 0,   color = "#FFFFFF00"},
                {position = 0.2, color = "#FFFFFFFF"},
                {position = 0.8, color = "#FFFFFFFF"},
                {position = 1,   color = "#FFFFFF00"},
            },
        },
    },
}

-- =============================================================================
-- Warm Gold color scheme -- warm dark surfaces, cream foreground, gold accents.
-- The engine falls back to the default scheme for any color name this scheme
-- doesn't define.
-- =============================================================================

ThemeEngine.RegisterColorScheme{
    id          = "warm-gold",
    name        = "Warm Gold",
    description = "Warm dark surfaces with bright cream text and gold accents.",
    colors = {
        -- Surfaces
        bg            = "#1B1310",
        bgAlt         = "#2A1E15",
        bgInverse     = "#E9B86F",

        -- Foreground / text
        fg            = "#F5E9D3",
        fgStrong      = "#FFF5DD",
        fgMuted       = "#A89377",
        fgPending     = "#8B7960",
        fgInverse     = "#1B1310",

        -- Borders
        border        = "#C49562",
        borderInverse = "#5A4128",

        -- Accent + interactive
        accent        = "#B8884C",
        accentHover   = "#F1D3A5",

        -- Status (kept semantic so they read consistently across schemes)
        success       = "#6BA84F",
        info          = "#E9C868",
        warning       = "#E08A2E",
        danger        = "#C73131",

        -- Disabled
        disabled      = "#3A2D22",
    },
    gradients = {
        -- Surfaces -- warm-tinted to match the scheme's brown surface palette.
        -- Tuned to be noticeable but not loud; mirrors the default scheme's
        -- approach (top-left lighter, bottom-right darker; radial vignette
        -- bright at center, darker at edge) but stays inside the warm family.
        surfaceLinear = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 1},
            stops = {
                {position = 0, color = "#1D110A"},
                {position = 1, color = "#100A06"},
            },
        },

        surfaceRadial = {
            type = "radial",
            point_a = {x = 0.5, y = 0.5},
            point_b = {x = 0.5, y = 1.0},
            stops = {
                {position = -0.01, color = "#2D211A"},
                {position = 0.00,  color = "#2D211A"},
                {position = 0.25,  color = "#251A12"},
                {position = 0.50,  color = "#1D140E"},
                {position = 0.75,  color = "#160F0A"},
                {position = 1.00,  color = "#100A06"},
            },
        },
    },
}

-- =============================================================================
-- Default theme -- canonical font slots + base widget rules
-- =============================================================================

ThemeEngine.RegisterTheme{
    id          = "default",
    name        = "Default",
    description = "The Draw Steel default theme.",
    colorScheme = "default",

    fonts = {
        heading = "Berling",
        label   = "Berling",
        input   = "LiberationSans",
        number  = "Newzald",
    },

    styles = {

        -- =====================================================================
        -- 1. BASICS -- generic widget vocabulary
        -- =====================================================================
        --
        -- Convention: bgcolor = "white" is image-tint-neutral. Setting it
        -- on a bgimage-bearing rule opts that surface out of the cascade's
        -- @bg tint so the asset paints in its natural colors. Used by
        -- {panel, image}, portraitImage, tooltipIcon, dialogPanel,
        -- framedPanel, tokenImagePortrait, and similar.

        --[[ Panel ]]
        {
            selectors = {"panel"},
            bgcolor = "@bg",
            scrollHandleColor = "@fgMuted",
        },
        {
            selectors = {"panel", "bordered"},
            bgimage = true,
            border = 1,
            borderColor = "@border",
        },
        -- Image-displaying panels. bgcolor "white" is image-tint-neutral
        -- (see top of section 1). Borders are intentionally NOT set here --
        -- callers manage borderWidth / borderColor per their needs.
        {
            selectors = {"panel", "image"},
            bgcolor = "white",
        },
        -- Portrait image editor (compendium sidebars on Race / Class /
        -- Career / etc.). 196x294 with a 2px @border frame; bgcolor
        -- "white" is image-tint-neutral (see top of section 1).
        {
            selectors = {"portraitImage"},
            bgcolor = "white",
            borderColor = "@border",
            borderWidth = 2,
            width = 196,
            height = "150% width",
        },
        -- Live dice preview surface marker class. The render-texture
        -- hookup itself (`bgimage = "#DicePreview"`) and the
        -- image-tint-neutral `bgcolor = "white"` MUST live inline on
        -- the call site -- the engine's "#" render-target rendering
        -- doesn't honor cascade-derived properties, and any visual
        -- chrome we'd add here (border, cornerRadius, bgcolor tint)
        -- gets fully covered by the render texture anyway. The class
        -- is kept as a marker so future theme-able properties (e.g.,
        -- a scheme-driven scene bgcolor set via a runtime hook) have
        -- a place to land.
        {
            selectors = {"panel", "dicePreview"},
        },
        -- The icon child gui.Button auto-creates when called with `icon = ...`.
        -- Tints the bgimage to @fg so the glyph reads against the surrounding
        -- button surface and follows the active scheme.
        {
            selectors = {"panel", "buttonIcon"},
            bgcolor = "@fg",
            height = "100%",
            width = "100%",
        },
        {
            selectors = {"panel", "buttonIcon", "hover"},
            brightness = 2,
        },

        --[[ Label ]]
        {
            selectors = {"label"},
            width = "auto",
            height = "auto",
            fontFace = "@label",
            fontSize = 14,
            color = "@fgStrong",
            bold = false,
        },
        {
            selectors = {"label", "sizeXs"},
            fontSize = 12,
        },
        {
            selectors = {"label", "sizeS"},
            fontSize = 14,
        },
        {
            selectors = {"label", "sizeM"},
            fontSize = 16,
        },
        {
            selectors = {"label", "sizeL"},
            fontSize = 18,
        },
        {
            selectors = {"label", "sizeXl"},
            fontSize = 24,
        },
        {
            selectors = {"label", "sizeXxl"},
            fontSize = 28,
        },
        {
            selectors = {"bold"},
            bold = true,
        },
        {
            selectors = {"noBold"},
            bold = false,
        },
        {
            selectors = {"label", "number"},
            fontFace = "@number",
        },
        {
            selectors = {"label", "pending"},
            color = "@fgPending",
        },
        {
            selectors = {"label", "link"},
            color = "@accent",
        },
        {
            selectors = {"label", "link", "hover"},
            color = "@accentHover",
        },
        {
            selectors = {"label", "link", "press"},
            brightness = 0.8,
        },

        --[[ Button (sizes + states + variants) ]]
        {
            selectors = {"label", "button"},
            height = 31,
            width = 129,
            bgimage = true,
            fontFace = "@label",
            fontSize = 16,
            textAlignment = "center",
            color = "@fg",
            bgcolor = "@bg",
            borderColor = "@border",
            border = 1,
            borderWidth = 1,
            fontWeight = "light",
            bold = false,
        },
        {
            selectors = {"button", "sizeXs"},
            width = 31,
            height = 20,
            fontSize = 12,
        },
        {
            selectors = {"button", "sizeS"},
            width = 57,
            height = 26,
            fontSize = 14,
        },
        {
            selectors = {"button", "sizeM"},
            width = 129,
            height = 31,
            fontSize = 16,
        },
        {
            selectors = {"button", "sizeL"},
            width = 175,
            height = 35,
            fontSize = 18,
        },
        {
            selectors = {"button", "sizeXl"},
            width = 175,
            height = 35,
            fontSize = 18,
        },
        {
            selectors = {"button", "sizeXxl"},
            width = 175,
            height = 35,
            fontSize = 18,
        },
        {
            selectors = {"button", "hasIcon"},
            width = "100% height",
            border = 0,
            borderWidth = 0,
            bgcolor = "clear",
        },
        {
            selectors = {"button", "disabled"},
            bgcolor = "@disabled",
        },
        {
            selectors = {"label", "button", "~disabled", "hasIcon", "hover"},
            bgcolor = "@bg"
        },
        {
            selectors = {"label", "button", "~disabled", "~hasIcon", "hover"},
            bgcolor = "@bgInverse",
            color = "@fgInverse",
            borderColor = "@borderInverse",
            fontWeight = "light",
        },
        {
            selectors = {"label", "button", "press"},
            transitionTime = 0.1,
            brightness = 0.7,
            soundEvent = "Mouse.Click",
        },
        {
            selectors = {"label", "button", "selected"},
            color = "@fgInverse",
            bgcolor = "@bgInverse",
            textAlignment = "center",
            fontWeight = "bold",
        },
        {
            selectors = {"label", "button", "focus"},
            borderColor = "@fg",
        },

        --[[ Input ]]
        {
            selectors = {"input"},
            bgimage = true,
            fontFace = "@input",
            fontSize = 14,
            color = "@fg",
            bgcolor = "@bg",
            borderColor = "@border",
            border = 2,
        },
        {
            selectors = {"input", "focus"},
            borderColor = "@fg",
        },
        {
            selectors = {"inputFaded"},
            borderColor = "@bg",
            borderWidth = 3,
            borderFade = true,
            bgcolor = "@bg",
        },
        -- Default search input has no border. Surfaces that want a bordered
        -- search input add it via their own MergeStyles extras.
        {
            selectors = {"searchInput"},
            bgimage = true,
            hpad = 6,
            fontSize = 16,
            bold = true,
            borderFade = false,
            color = "@fg",
            bgcolor = "@bg",
            borderWidth = 0,
        },
        -- Magnifying-glass icon child auto-created by gui.SearchInput.
        -- Tinted to @fg so the glyph follows the active scheme. The
        -- `floating = true` and `x = -20` positioning stay inline at
        -- the call site -- floating is a structural property (controls
        -- layout participation) that the engine doesn't honor through
        -- the style cascade.
        {
            selectors = {"searchInputIcon"},
            bgcolor = "@fg",
            vmargin = 0,
            halign = "left",
            valign = "center",
            height = "90%",
            width = "100% height",
        },
        -- Color picker main button (gui.ColorPicker mainPanel).
        -- The button shows the currently-selected color via
        -- selfStyle.bgcolor (set at runtime by the widget); the theme
        -- owns the border frame.
        {
            selectors = {"colorPicker"},
            bgimage = true,
            borderColor = "@border",
            borderWidth = 2,
        },
        {
            selectors = {"colorPicker", "hover"},
            borderColor = "@accentHover",
        },
        {
            selectors = {"colorPicker", "press"},
            borderColor = "@fg",
        },

        --[[ Dropdown -- closed control + open popup machinery ]]
        --
        -- The dropdown's internal sub-element classes (dropdownLabel,
        -- dropdownTriangle, dropdownBorder, dropdownMenuSub, dropdownOption,
        -- submenuArrow) are emitted by the DMHub engine itself, so theme
        -- rules must match those names verbatim.
        --
        -- Open state composition: a dropdownBorder container holds a
        -- dropdownMenuSub (or inline option list) full of dropdownOption
        -- rows. submenuArrow is the indicator on options that open a sub-popup.
        {
            selectors = {"dropdown"},
            fontFace = "@input",
            fontSize = 14,
            color = "@fg",
            bgcolor = "@bgAlt",
            borderColor = "@border",
            border = 2,
        },
        {
            selectors = {"dropdown", "expandedTop"},
            border = {x1 = 2, x2 = 2, y1 = 2, y2 = 0},
        },
        {
            selectors = {"dropdown", "expandedBottom"},
            border = {x1 = 2, x2 = 2, y1 = 0, y2 = 2},
        },
        {
            selectors = {"dropdown", "hover", "~search"},
            bgcolor = "@fg",
        },
        {
            selectors = {"label", "dropdownLabel"},
            fontFace = "@input",
            fontSize = 18,
            minFontSize = 10,
            color = "@fg",
            halign = "left",
            valign = "center",
            width = "100%-40",
            height = "100%",
            hmargin = 6,
        },
        {
            selectors = {"label", "dropdownLabel", "parent:hover"},
            color = "@fgInverse",
        },
        {
            selectors = {"dropdownTriangle"},
            height = "30%",
            width = "160% height",
            bgcolor = "@fg",
            halign = "right",
            valign = "center",
            hmargin = 6,
        },
        {
            selectors = {"dropdownTriangle", "parent:hover"},
            bgcolor = "@fgInverse",
        },
        {
            selectors = {"dropdownBorder"},
            bgcolor = "@bg",
            border = {x1 = 2, x2 = 2, y1 = 2, y2 = 0},
            borderColor = "@border",
        },
        {
            selectors = {"dropdownBorder", "vcenter"},
            border = {x1 = 2, x2 = 2, y1 = 2, y2 = 2},
            vpad = 4,
        },
        {
            selectors = {"dropdownBorder", "top"},
            border = {x1 = 2, x2 = 2, y1 = 0, y2 = 2},
        },
        {
            selectors = {"dropdownBorder", "detached"},
            border = {x1 = 2, x2 = 2, y1 = 2, y2 = 2},
        },
        {
            selectors = {"dropdownMenuSub"},
            bgimage = true,
            bgcolor = "@bg",
            border = {x1 = 2, x2 = 2, y1 = 2, y2 = 2},
            borderColor = "@border",
            flow = "vertical",
            width = "auto",
            height = "auto",
            valign = "top",
            hidden = 1,
        },
        {
            selectors = {"dropdownMenuSub", "parent:hover"},
            hidden = 0,
        },
        {
            selectors = {"dropdownOption"},
            bgimage = true,
            width = "100%-2",
            height = "auto",
            halign = "center",
            hpad = 6,
            fontSize = 18,
            color = "@fg",
        },
        {
            selectors = {"dropdownOption", "hover"},
            color = "@bg",
            bgcolor = "@fg",
        },
        {
            selectors = {"dropdownOption", "searchfocus"},
            color = "@bg",
            bgcolor = "@fg",
        },
        {
            selectors = {"dropdownOption", "disabled"},
            color = "@fgMuted",
        },
        {
            selectors = {"submenuArrow"},
            bgcolor = "@fg",
        },
        {
            selectors = {"submenuArrow", "parent:hover"},
            bgcolor = "@bg",
        },

        --[[ Multiselect chip ]]
        --
        -- gui.Multiselect renders selected items as removable chips next to
        -- a Dropdown. Each chip is a {panel, multiselectChip} container
        -- holding a {label, multiselectChipText} text label and a
        -- {panel, multiselectChipRemove} delete button (with an X label
        -- inside) that's hidden until the parent chip is hovered.
        {
            selectors = {"panel", "multiselectChip"},
            flow = "horizontal",
            width = "auto",
            height = "auto",
            pad = 4,
            margin = 4,
            bgimage = true,
            bgcolor = "@bg",
            border = 1,
            borderColor = "@border",
            cornerRadius = 2,
        },
        {
            selectors = {"panel", "multiselectChip", "hover"},
            brightness = 1.2,
        },
        {
            selectors = {"label", "multiselectChipText"},
            width = "auto",
            height = "auto",
            valign = "center",
            margin = 0,
            pad = 0,
            fontFace = "@input",
            fontSize = 14,
        },
        -- No fill on the remove button -- it sits on top of the chip's `@bg`
        -- via the cascade. The red `@danger` border + X glyph carry the
        -- "danger zone" signal without an alpha wash.
        {
            selectors = {"panel", "multiselectChipRemove"},
            width = 14,
            height = 14,
            halign = "right",
            valign = "center",
            lmargin = 4,
            bgimage = true,
            border = 1,
            borderColor = "@danger",
            cornerRadius = 2,
            bold = true,
            hidden = 1,
        },
        {
            selectors = {"panel", "multiselectChipRemove", "parent:hover"},
            hidden = 0,
        },
        {
            selectors = {"panel", "multiselectChipRemove", "hover"},
            brightness = 1.5,
        },
        -- The "X" label inside the remove button. Color is @fg (not @danger)
        -- so the letter contrasts against its own red-bordered red-wash
        -- container; the parent's border + faint bg already carry the
        -- "danger zone" signal so the X just needs to be readable.
        {
            selectors = {"label", "multiselectChipRemove"},
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "center",
            margin = 0,
            pad = 0,
            textAlignment = "center",
            color = "@fg",
            fontFace = "@input",
            fontSize = 8,
        },
        {
            selectors = {"label", "multiselectChipRemove", "parent:hover"},
            brightness = 1.5,
        },

        --[[ Slider ]]
        --
        -- gui.Slider (Gui.lua wrapper) -- emits sliderHandleBorder /
        -- sliderHandleInner on its internal handle parts.
        --
        -- gui.EnumeratedSliderControl (core widget) -- composed of an
        -- enumSlider container with a row of enumSliderOption labels.
        -- The widget's .lua only applies classes; all styling lives here
        -- so themes/schemes own it.
        {
            selectors = {"sliderHandleBorder"},
            borderWidth = 2,
            borderColor = "@border",
            bgcolor = "@bg",
            bgimage = true,
            width = "60%",
            height = "60%",
            halign = "center",
            valign = "center",
        },
        {
            selectors = {"sliderHandleInner"},
            bgimage = true,
            bgcolor = "@fg",
            width = "30%",
            height = "30%",
            halign = "center",
            valign = "center",
        },
        {
            selectors = {"sliderNotch"},
            bgimage = true,
            bgcolor = "@borderInverse",
            width = "100%",
            halign = "center",
            borderWidth = 0,
        },
        {
            selectors = {"sliderFill"},
            bgimage = true,
            bgcolor = "@fg",
            height = 2,
            halign = "left",
            borderWidth = 0,
        },
        {
            selectors = {"enumSlider"},
            width = "100%",
            height = 24,
            flow = "horizontal",
        },
        {
            selectors = {"enumSliderOption"},
            bgimage = true,
            bgcolor = "@bg",
            color = "@fg",
            borderColor = "@border",
            borderWidth = 2,
            fontSize = 12,
            bold = true,
            halign = "center",
            valign = "center",
            textAlignment = "center",
            height = "100%",
        },
        {
            selectors = {"enumSliderOption", "selected"},
            bgcolor = "@fg",
            color = "@bg",
            transitionTime = 0.2,
        },
        {
            selectors = {"enumSliderOption", "hover"},
            bgcolor = "@fg",
            color = "@bg",
            brightness = 1.5,
            transitionTime = 0.2,
        },

        --[[ Checkbox ]]
        -- Transparent fill on the checkbox container -- the checkmark and
        -- check-background panels below paint the visual; the container
        -- itself just lays out the row.
        {
            selectors = {"checkbox"},
            bgimage = true,
            flow = "horizontal",
            bgcolor = "clear",
            height = 30,
            width = "auto",
            minWidth = 200,
            hpad = 4,
        },
        {
            selectors = {"checkbox", "hover", "~disabled"},
            borderWidth = 1,
            borderColor = "@fg",
        },
        {
            selectors = {"checkBackground"},
            bgimage = true,
            bgcolor = "@bg",
            halign = "left",
            valign = "center",
            height = "70%",
            width = "100% height",
            rmargin = 6,
            borderColor = "@border",
            borderWidth = 2,
        },
        {
            selectors = {"checkBackground", "disabled"},
            saturation = 0,
        },
        {
            selectors = {"checkMark"},
            bgimage = true,
            bgcolor = "@fg",
            halign = "center",
            valign = "center",
            width = "50%",
            height = "50%",
        },
        {
            selectors = {"checkMark", "disabled"},
            saturation = 0,
        },
        {
            selectors = {"checkboxLabel"},
            halign = "left",
            valign = "center",
            textAlignment = "left",
            borderWidth = 0,
            width = "auto",
            height = "auto",
            fontSize = 18,
        },
        {
            selectors = {"checkboxLabel", "rightAlign"},
            rmargin = 8,
        },
        {
            selectors = {"checkboxLabel", "disabled"},
            color = "@fgMuted",
        },

        --[[ Tab ]]
        {
            selectors = {"tab"},
            bgimage = true,
            borderWidth = 1,
            borderColor = "@border",
            width = 130,
            height = 40,
            fontSize = 18,
            bgcolor = "@bg",
            color = "@fgMuted",
            hpad = 6,
        },
        {
            selectors = {"tab", "hover"},
            brightness = 1.2,
        },
        {
            selectors = {"tab", "selected"},
            bold = true,
            color = "@fgStrong",
            borderColor = "@fg",
            borderWidth = 2,
        },
        {
            selectors = {"tabBar"},
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "center",
        },

        --[[ Tooltip ]]
        --
        -- tooltipLabel / tooltipIcon / hasTooltip are engine-emitted on
        -- gui.Tooltip elements; theme rules match those names verbatim.
        {
            selectors = {"label", "tooltipLabel"},
            color = "@fg",
            fontSize = 16,
            width = "auto",
            height = "auto",
            halign = "left",
        },
        {
            selectors = {"label", "tooltipLabel", "title"},
            bold = true,
            width = "100%",
            fontSize = 24,
        },
        -- bgcolor "white" is image-tint-neutral (see top of section 1).
        {
            selectors = {"icon", "tooltipIcon"},
            halign = "right",
            valign = "top",
            width = 32,
            height = 32,
            bgcolor = "white",
        },
        {
            selectors = {"hasTooltip"},
            color = "@accent",
        },
        {
            selectors = {"hasTooltip", "hover"},
            color = "@accentHover",
        },

        --[[ Icon button (generic + HUD) ]]
        --
        -- iconButton: small accent-able click target. Default size is sizeM
        -- (24x24); pair with a size class (sizeXs..sizeXxl) to override.
        -- Pair with a withSuccess / withInfo / withWarning / withDanger
        -- class to recolor the hover state.
        --
        -- gui.Button{ icon = ... } (no `text`) returns a panel with this
        -- class automatically; see Gui.lua's gui.Button.
        --
        -- hudIconButton: larger HUD-bar button with selected/disabled
        -- states and a child hudIconButtonIcon that scales on hover.
        {
            selectors = {"iconButton"},
            bgcolor = "@fg",
            width = 24,
            height = 24,
            valign = "center",
        },
        {
            selectors = {"iconButton", "flipped"},
	        scale = {x = -1, y = 1},
        },
        {
            selectors = {"iconButton", "hover"},
            brightness = 1.5,
            transitionTime = 0.1,
        },
        {
            selectors = {"iconButton", "press"},
            brightness = 0.7,
            transitionTime = 0.1,
        },
        {
            selectors = {"iconButton", "withSuccess", "hover"},
            bgcolor = "@success",
        },
        {
            selectors = {"iconButton", "withInfo", "hover"},
            bgcolor = "@info",
        },
        {
            selectors = {"iconButton", "withWarning", "hover"},
            bgcolor = "@warning",
        },
        {
            selectors = {"iconButton", "withDanger", "hover"},
            bgcolor = "@danger",
        },
        -- Kind variants. Each registered kind class (see gui.iconButtonClasses
        -- in Gui.lua) supplies its own bgimage here; size/tint/hover/press
        -- continue to inherit from the {iconButton} family above.
        {
            selectors = {"iconButton", "addButton"},
            bgimage = "ui-icons/Plus.png",
        },
        {
            selectors = {"iconButton", "closeButton"},
            bgimage = "ui-icons/close.png",
        },
        {
            selectors = {"iconButton", "copyButton"},
            bgimage = "icons/icon_app/icon_app_108.png",
        },
        {
            selectors = {"iconButton", "deleteButton"},
            bgimage = "icons/icon_tool/icon_tool_44.png",
        },
        {
            selectors = {"iconButton", "deleteButton", "hover"},
            bgcolor = "@danger",
        },
        {
            selectors = {"iconButton", "settingsButton"},
            bgimage = "ui-icons/skills/98.png",
        },
        -- Size variants. Default is sizeM (24x24); the slot is defined
        -- explicitly so all six size names are theme-vocabulary entries.
        {
            selectors = {"iconButton", "sizeXs"},
            width = 16,
            height = 16,
        },
        {
            selectors = {"iconButton", "sizeS"},
            width = 20,
            height = 20,
        },
        {
            selectors = {"iconButton", "sizeM"},
            width = 24,
            height = 24,
        },
        {
            selectors = {"iconButton", "sizeL"},
            width = 32,
            height = 32,
        },
        {
            selectors = {"iconButton", "sizeXl"},
            width = 48,
            height = 48,
        },
        {
            selectors = {"iconButton", "sizeXxl"},
            width = 58,
            height = 58,
        },
        -- {
        --     selectors = {"hudIconButton"},
        --     width = 58,
        --     height = 58,
        --     bgimage = true,
        --     bgcolor = "@bg",
        --     borderColor = "@fg",
        --     borderWidth = 1,
        -- },
        -- {
        --     selectors = {"hudIconButton", "hover"},
        --     brightness = 2.5,
        --     transitionTime = 0.1,
        -- },
        -- {
        --     selectors = {"hudIconButton", "press"},
        --     brightness = 0.8,
        --     transitionTime = 0.1,
        -- },
        -- {
        --     selectors = {"hudIconButton", "disabled"},
        --     brightness = 0.5,
        --     saturation = 0.2,
        -- },
        -- {
        --     selectors = {"hudIconButton", "selected"},
        --     brightness = 3.0,
        --     saturation = 1.4,
        -- },
        -- {
        --     selectors = {"hudIconButton", "selected", "tab"},
        --     brightness = 1,
        --     saturation = 1,
        --     bgcolor = "@bg",
        --     border = {x1 = 1, x2 = 1, y1 = 0, y2 = 1},
        -- },
        -- {
        --     selectors = {"hudIconButtonIcon"},
        --     width = "75%",
        --     height = "75%",
        --     halign = "center",
        --     valign = "center",
        --     bgcolor = "@fg",
        -- },
        -- {
        --     selectors = {"hudIconButtonIcon", "parent:hover"},
        --     brightness = 1.5,
        --     transitionTime = 0.1,
        --     scale = 1.15,
        -- },
        -- {
        --     selectors = {"hudIconButtonIcon", "parent:press"},
        --     brightness = 0.8,
        --     transitionTime = 0.1,
        -- },
        -- {
        --     selectors = {"hudIconButtonIcon", "parent:deselected"},
        --     saturation = 0.0,
        --     brightness = 0.8,
        -- },
        -- {
        --     selectors = {"hudIconButtonIcon", "parent:disabled"},
        --     saturation = 0.2,
        --     brightness = 0.5,
        --     scale = 1,
        -- },
        -- {
        --     selectors = {"hudIconButtonIcon", "parent:selected"},
        --     saturation = 1.5,
        --     brightness = 1.5,
        -- },

        --[[ Iconographic buttons (close / plus / delete) ]]
        -- {
        --     selectors = {"closeButton"},
        --     width = 24,
        --     height = 24,
        --     margin = 6,
        --     halign = "right",
        --     valign = "top",
        --     bgcolor = "@fg",
        -- },
        -- {
        --     selectors = {"closeButton", "hover"},
        --     brightness = 2,
        -- },
        -- {
        --     selectors = {"closeButton", "press"},
        --     brightness = 0.5,
        -- },
        -- {
        --     selectors = {"plusButton"},
        --     width = 24,
        --     height = 24,
        --     bgcolor = "@fg",
        -- },
        -- {
        --     selectors = {"plusButton", "hover"},
        --     brightness = 1.4,
        -- },
        -- {
        --     selectors = {"plusButton", "press"},
        --     brightness = 0.8,
        -- },
        -- {
        --     selectors = {"deleteItemButton"},
        --     width = 24,
        --     height = 24,
        -- },

        --[[ Triangle (expand/collapse arrow) ]]
        --
        -- Defaults to "closed" (rotate = 90, pointing right). Toggling the
        -- "expanded" class rotates to point down with a short transition.
        {
            selectors = {"triangle"},
            bgimage = "panels/triangle.png",
            bgcolor = "@fg",
            width = 12,
            height = 12,
            hmargin = 4,
            valign = "center",
            halign = "left",
        },
        {
            selectors = {"triangle", "hover"},
            brightness = 1.5,
        },

        --[[ Menu (horizontal menu strip, e.g. title bar dropdowns) ]]
        {
            selectors = {"menuItem"},
            bgimage = true,
            bgcolor = "clear",
            hpad = 8,
        },
        {
            selectors = {"menuItem", "hover"},
            bgcolor = "@fg",
        },
        {
            selectors = {"menuLabel"},
            fontSize = 16,
            width = "auto",
            height = "auto",
            valign = "center",
            hmargin = 4,
            color = "@fg",
        },
        {
            selectors = {"menuLabel", "parent:hover"},
            color = "@bg",
        },
        {
            selectors = {"menuItemIcon"},
            bgcolor = "@fg",
        },
        {
            selectors = {"menuItemIcon", "parent:hover"},
            bgcolor = "@bg",
        },

        --[[ Context menu ]]

        -- The popup panel itself
        {
            selectors = {"contextMenu"},
            bgimage = true,
            bgcolor = "white",
            gradient = "@surfaceLinear",
            borderColor = "@fg",
            borderWidth = 2,
            flow = "vertical",
        },

        -- Rows: transparent at rest so the panel surface paints through;
        -- hover/press states give them distinct backgrounds.
        {
            selectors = {"contextMenuItem"},
            bgimage = true,
            bgcolor = "clear",
            color = "@fg",
            borderWidth = 0,
        },
        {
            selectors = {"contextMenuItem", "hover"},
            bgcolor = "@fg",
            color = "@bg",
            transitionTime = 0.2,
        },
        {
            selectors = {"contextMenuItem", "press"},
            brightness = 1.2,
            transitionTime = 0.2,
        },

        -- Row label
        {
            selectors = {"label", "contextMenuLabel"},
            color = "@fg",
            fontSize = 16,
        },
        {
            selectors = {"contextMenuLabel", "disabled"},
            color = "@fgMuted",
        },
        {
            selectors = {"contextMenuLabel", "parent:hover"},
            color = "@bg",
        },

        -- Bind label (keyboard shortcut hint)
        {
            selectors = {"contextMenuBind"},
            color = "@fg",
            fontSize = 16,
        },
        {
            selectors = {"contextMenuBind", "disabled"},
            color = "@fgMuted",
        },
        {
            selectors = {"contextMenuBind", "parent:hover"},
            color = "@bg",
        },

        -- Icon glyph (image-tint to text color)
        {
            selectors = {"contextMenuIcon"},
            bgcolor = "@fg",
        },
        {
            selectors = {"contextMenuIcon", "parent:hover"},
            bgcolor = "@bg",
        },

        -- Checkmark glyph
        {
            selectors = {"contextMenuCheck"},
            bgcolor = "@fg",
        },
        {
            selectors = {"contextMenuCheck", "parent:hover"},
            bgcolor = "@bg",
        },

        -- Divider
        {
            selectors = {"contextMenuDiv"},
            bgimage = true,
            bgcolor = "@fg",
            vmargin = 2,
        },

        -- Submenu arrow (bgimage is the triangle, set inline at construction)
        {
            selectors = {"contextMenuArrow"},
            bgcolor = "@fg",
        },

        --[[ Table primitives ]]
        --
        -- oddRow / evenRow / highlight are emitted by the engine's table
        -- striping. headerRow is applied by callers on the first row of a
        -- gui.Table so the theme can style it (bold, darker bg).
        {
            selectors = {"label", "tableLabel"},
            pad = 6,
            fontSize = 16,
            width = "auto",
            height = "auto",
            color = "@fg",
        },
        {
            selectors = {"row"},
            width = "auto",
            height = "auto",
            bgimage = true,
        },
        {
            selectors = {"row", "headerRow"},
            bgcolor = "@bg",
        },
        {
            selectors = {"label", "parent:headerRow"},
            bold = true,
        },
        {
            selectors = {"row", "evenRow"},
            bgcolor = "@bg",
        },
        {
            selectors = {"row", "oddRow"},
            bgcolor = "@bgAlt",
        },
        {
            selectors = {"row", "highlight"},
            bgcolor = "@info",
        },

        -- =====================================================================
        -- 2. FORMS -- label/control layouts
        -- =====================================================================

        --[[ Default form (label-left + control-right) ]]
        --
        -- Authoring pattern: row containers take `formRow` (full-width) or
        -- `formPanel` (compact, used by feature editors). Every child
        -- (label, input, dropdown, multiselect, ...) takes the single
        -- namespace class `form`. The cascade conjuncts `form` with each
        -- child's primitive class to pick the right rule; controls without
        -- a primitive-specific rule fall through to the `{form}` catch-all.
        -- `formValue` is a separate read-only-display label class.
        {
            selectors = {"formRow"},
            flow = "horizontal",
            width = "98%",
            height = "auto",
            halign = "left",
            valign = "top",
            vmargin = 4,
        },
        --[[ Compact horizontal row (used by compendium feature editors) ]]
        {
            selectors = {"formPanel"},
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            vmargin = 2,
        },
        {
            selectors = {"label", "form"},
            fontSize = 18,
            color = "@fgStrong",
            width = "auto",
            height = "auto",
            minWidth = 140,
            halign = "left",
            valign = "center",
            hmargin = 8,
        },
        -- Catch-all for any form child without a primitive-specific rule
        -- below (multiselect, custom widgets, etc.).
        {
            selectors = {"form"},
            halign = "left",
            valign = "center",
        },
        {
            selectors = {"input", "form"},
            fontSize = 16,
            width = 180,
            height = 26,
            color = "@fg",
            halign = "left",
            valign = "center",
            textAlignment = "left",
        },
        {
            selectors = {"input", "form", "multiline"},
            textAlignment = "topleft",
        },
        {
            selectors = {"dropdown", "form"},
            halign = "left",
            vmargin = 4,
            width = 240,
            height = 30,
        },
        {
            selectors = {"formValue"},
            halign = "right",
            vmargin = 4,
            width = 180,
            height = 30,
            fontSize = 14,
        },

        --[[ Stacked form (label-above-control) ]]
        --
        -- Vertical layout. The row container takes `formStackedRow`; every
        -- child (label, input, dropdown, multiselect, ...) takes the
        -- single namespace class `formStacked`. The cascade conjuncts
        -- `formStacked` with each child's primitive class to pick the
        -- right rule; controls without a primitive-specific rule fall
        -- through to the `{formStacked}` catch-all. Compound selectors on
        -- the input/dropdown rules so the size beats any surface-specific
        -- {input}/{dropdown} sizes in caller MergeStyles extras.
        {
            selectors = {"formStackedRow"},
            flow = "vertical",
            width = "70%",
            height = "auto",
            halign = "left",
            bmargin = 8,
        },
        {
            selectors = {"label", "formStacked"},
            fontSize = 18,
            width = "98%",
            height = "auto",
            halign = "left",
            valign = "top",
            bmargin = 4,
            bold = true,
        },
        -- Catch-all for any formStacked child without a primitive-specific
        -- rule below (multiselect, custom widgets, etc.).
        {
            selectors = {"formStacked"},
            width = "98%",
        },
        -- Inputs in stacked forms: 98% width, height 30 with internal padding
        -- so text isn't cramped against the borders. fontSize matches the
        -- dropdown (18) for visual consistency between input and dropdown
        -- controls in the same form.
        {
            selectors = {"input", "formStacked"},
            width = "98%",
            height = 30,
            hpad = 6,
            vpad = 4,
            fontSize = 18,
        },
        -- Dropdowns in stacked forms: 98% width and height matching inputs.
        {
            selectors = {"dropdown", "formStacked"},
            width = "98%",
            height = 30,
        },

        -- =====================================================================
        -- 3. CARDS -- collapsible feature-card layouts
        -- =====================================================================
        --
        -- A featureCard is an outer frame holding a featureCardHeader (top
        -- strip with expand triangle, name display, delete button) and a
        -- featureCardBody (the body that the card's @bgAlt shows through).
        -- featureCardNested adjusts width and bottom margin for cards
        -- rendered inside another card's option list.
        --
        -- Used by class / race / background / kit feature editors in the
        -- compendium UI.
        {
            selectors = {"featureCard"},
            bgimage = true,
            bgcolor = "@bgAlt",
            width = "70%",
            height = "auto",
            halign = "left",
            flow = "vertical",
            bmargin = 12,
        },
        {
            selectors = {"featureCardNested"},
            width = "70%+8",
            bmargin = 0,
        },
        -- Header: full border drawn here so the card's outer frame sits on
        -- the top + sides; the bottom edge separates header from body.
        -- Transparent fill so the card's bgAlt shows through.
        {
            selectors = {"featureCardHeader"},
            bgimage = true,
            bgcolor = "clear",
            border = { x1 = 1, x2 = 1, y1 = 1, y2 = 1 },
            borderColor = "@border",
            borderBox = true,
            width = "100%",
            height = 30,
            flow = "horizontal",
            hpad = 0,
        },
        -- Body: border on left/right/bottom; top edge is the header's bottom
        -- border. Same fill as the card so the inside reads as one continuous
        -- bgAlt surface.
        {
            selectors = {"featureCardBody"},
            bgimage = true,
            bgcolor = "@bgAlt",
            border = { x1 = 1, x2 = 1, y1 = 1, y2 = 0 },
            borderColor = "@border",
            borderBox = true,
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 12,
        },

        -- =====================================================================
        -- 4. DIALOGS -- modal / framed surfaces
        -- =====================================================================

        --[[ Plain dialog ]]
        --
        -- dialogTitle / dialogPanel / dialogBorder are emitted by the
        -- engine's gui.Dialog construction; theme rules must match those
        -- names verbatim.
        {
            selectors = {"panel", "dialog"},
            bgimage = true,
            bgcolor = "white",
            cornerRadius = 4,
            gradient = "@surfaceLinear",
            borderWidth = 2.2,
            borderColor = "@fg",
        },
        -- Launchable-hosted content. Use this class on the root panel
        -- returned from `LaunchablePanel.Register{ content = ... }`.
        -- The launchable host paints its own frame and chrome (close
        -- button, drag handle, etc.) around our content, so this rule
        -- stays transparent so we don't double-frame or overwrite the
        -- host's UI.
        {
            selectors = {"panel", "launchablePanel"},
        },
        {
            selectors = {"label", "dialogTitle"},
            width = "96%",
            height = "auto",
            valign = "top",
            halign = "center",
            textAlignment = "center",
            fontSize = 24,
        },
        -- bgcolor "white" is image-tint-neutral (see top of section 1).
        {
            selectors = {"dialogPanel"},
            bgimage = "panels/InventorySlot_Background.png",
            bgcolor = "white",
            bgslice = 20,
            border = 10,
        },
        {
            selectors = {"dialogPanel", "fadein"},
            opacity = 0,
            uiscale = {x = 0.01, y = 0.01},
            transitionTime = 0.2,
        },
        {
            selectors = {"dialogBorder"},
            hidden = 1,
        },

        --[[ Modal dialog ]]
        {
            selectors = {"modalDialog"},
            bgimage = true,
            bgcolor = "@bgInverse",
            borderWidth = 2,
            borderColor = "@bg",
            cornerRadius = 8,
        },
        -- {
        --     selectors = {"prettyButton"},
        --     width = 140,
        --     height = 60,
        -- },
        -- {
        --     selectors = {"prettyButtonLabel"},
        --     fontSize = 20,
        --     bold = true,
        --     textAlignment = "center",
        --     width = "auto",
        --     height = "auto",
        -- },
        {
            selectors = {"label", "modalTitle"},
            halign = "center",
            valign = "top",
            textAlignment = "center",
            width = "auto",
            height = "auto",
            margin = 16,
            fontSize = 28,
            color = "@fgStrong",
            bold = true,
        },
        {
            selectors = {"label", "modalMessage"},
            halign = "center",
            valign = "center",
            textAlignment = "left",
            width = "80%",
            height = "auto",
            fontSize = 18,
            color = "@fg",
        },

        --[[ Framed panel ]]
        -- @surfaceLinear gradient paints the visible color; bgcolor "white"
        -- is image-tint-neutral (see top of section 1).
        {
            selectors = {"framedPanel"},
            bgimage = true,
            bgcolor = "white",
            cornerRadius = 4,
            gradient = "@surfaceLinear",
            borderWidth = 2.2,
            borderColor = "@fg",
        },
        {
            selectors = {"framedPanel", "toplevel"},
            borderWidth = 0,
            opacity = 0.98,
        },
        {
            selectors = {"framedPanel", "create", "~hidden", "~collapsed"},
            soundEvent = "UI.WindowOpen",
        },

        -- =====================================================================
        -- 5. UTILITIES -- visibility, animation, scroll
        -- =====================================================================

        {
            selectors = {"hidden"},
            hidden = 1,
        },
        {
            selectors = {"collapsed"},
            collapsed = 1,
        },
        {
            selectors = {"collapseAnim"},
            collapsed = 1,
            transitionTime = 0.2,
            uiscale = {x = 1, y = 0.001},
        },
        {
            selectors = {"hideForPlayers", "player"},
            hidden = 1,
        },

        --[[ Token image ]]
        --
        -- gui.CreateTokenImage builds a 3-panel structure: outer (tokenImage)
        -- holds a portrait (tokenImagePortrait) with the token's portrait as
        -- bgimage, and a frame (tokenImageFrame) overlay. The portrait's
        -- bgcolor "white" is image-tint-neutral (see top of section 1).
        --
        -- The factory also emits the legacy kebab class names alongside these
        -- so existing non-themed consumers (Styles.lua) keep rendering.
        {
            selectors = {"tokenImage"},
            halign = "center",
            valign = "center",
            width = 60,
            height = 60,
        },
        {
            selectors = {"tokenImagePortrait"},
            bgcolor = "white",
            width = "100%",
            height = "100%",
        },
        {
            selectors = {"tokenImageFrame"},
            width = "100%",
            height = "100%",
        },
    },
}

-- After both schemes and the default theme are registered, restore the
-- user's saved selections (defaults to "default" / "default" if they
-- haven't picked anything yet).
ThemeEngine.RestoreActiveSelection()
