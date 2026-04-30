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
        success       = "#6BA84F",
        info          = "#E9C868",
        warning       = "#E08A2E",
        danger        = "#C73131",

        -- Disabled
        disabled      = "#343434",

        -- ---------------------------------------------------------------------
        -- QUARANTINE: feature-specific colors awaiting relocation into their
        -- consumers' MergeStyles extras. Inside a Lua block comment so they
        -- are inert -- visible for reference, not registered.
        -- ---------------------------------------------------------------------
        --[==[
        triggerColor              = "#CCCC00",
        freeColor                 = "#9999FF",
        passiveColor              = "#006300",
        triggerColorAgainstText   = "#AAAA00",
        freeColorAgainstText      = "#7777EE",
        passiveColorAgainstText   = "#006300",
        modifierBuff              = "#2A4DFF",
        modifierDebuff            = "#FF0000",
        implStatus0               = "#F82FCD",
        implStatus1               = "#FF0000",
        implStatus2               = "#CD7F32",
        implStatus3               = "#C0C0C0",
        implStatus4               = "#FFD700",
        ]==]
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
                {position = 0, color = "#000000"},
                {position = 1, color = "#060606"},
            },
        },

        -- Bars
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

        -- ---------------------------------------------------------------------
        -- QUARANTINE: feature-specific gradients awaiting relocation. Inside
        -- a Lua block comment so they are inert.
        -- ---------------------------------------------------------------------
        --[==[
        tempGradient = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 0},
            stops = {
                {position = 0, color = "#6666AA"},
                {position = 1, color = "#6666FF"},
            },
        },
        grayscaleGradient = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 0},
            stops = {
                {position = 0, color = "#484848"},
                {position = 1, color = "#C1C1C1"},
            },
        },
        healthGradient = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 0},
            stops = {
                {position = 0, color = "#004D52"},
                {position = 1, color = "#00B8C4"},
            },
        },
        bloodiedGradient = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 0},
            stops = {
                {position = 0, color = "#A15102"},
                {position = 1, color = "#FA9A00"},
            },
        },
        damagedGradient = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 0},
            stops = {
                {position = 0, color = "#440000"},
                {position = 1, color = "#BB0000"},
            },
        },
        conditionGradient = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 0},
            stops = {
                {position = 0, color = "#000000"},
                {position = 1, color = "@fg"},
            },
        },
        advantageSelectedGradient = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 1},
            stops = {
                {position = 0, color = "#111111"},
                {position = 1, color = "#222222"},
            },
        },
        ]==]
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
        input   = "Inter",
        number  = "Newzald",
    },

    styles = {

        -- =====================================================================
        -- 1. BASICS -- generic widget vocabulary
        -- =====================================================================

        --[[ Panel ]]
        {
            selectors = {"panel"},
            bgcolor = "@bg",
        },
        {
            selectors = {"panel", "panelRadial"},
            bgimage = true,
            gradient = "@surfaceRadial",
        },
        {
            selectors = {"panel", "bordered"},
            bgimage = true,
            border = 1,
            borderColor = "@border",
        },
        -- Image-displaying panels: opt out of the inherited @bg tint so a
        -- bgimage asset paints with natural colors. bgcolor stays white
        -- (image-tint-neutral). Borders are intentionally NOT set here --
        -- callers manage borderWidth / borderColor per their needs.
        {
            selectors = {"panel", "image"},
            bgcolor = "white",
        },
        -- Portrait image editor (compendium sidebars on Race / Class /
        -- Career / etc.). 196x294 with a 2px @border frame; bgcolor =
        -- "white" is image-tint-neutral so the avatar paints in its
        -- natural colors (same convention as {panel, image}).
        {
            selectors = {"portraitImage"},
            bgcolor = "white",
            borderColor = "@border",
            borderWidth = 2,
            width = 196,
            height = "150% width",
        },
        -- The icon child gui.Button auto-creates when called with `icon = ...`.
        -- Tints the bgimage to @fg so the glyph reads against the surrounding
        -- button surface and follows the active scheme.
        {
            selectors = {"panel", "buttonIcon"},
            bgcolor = "@fg",
            width = "100%",
            height = "100%",
        },
        {
            selectors = {"panel", "buttonIcon", "hover"},
            bgcolor = "@fgStrong",
        },

        --[[ Label ]]
        {
            selectors = {"label"},
            fontFace = "@label",
            fontSize = 14,
            color = "@fgStrong",
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
            selectors = {"label", "tinyLabel"},
            fontSize = 12,
            color = "@fg",
            textAlignment = "center",
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
            fontFace = "@label",
            fontSize = 16,
            color = "@fg",
            bgcolor = "@bg",
            borderColor = "@border",
            border = 1,
            borderWidth = 1,
            cornerRadius = 5,
            fontWeight = "light",
            bold = false,
        },
        {
            selectors = {"button", "btnSm"},
            height = 31,
            width = 57,
        },
        {
            selectors = {"button", "btnMd"},
            height = 31,
            width = 129,
        },
        {
            selectors = {"button", "btnLg"},
            height = 35,
            width = 175,
            beveledcorners = true,
        },
        {
            selectors = {"label", "button", "tiny"},
            fontSize = 12,
            fontWeight = "thin",
            borderWidth = 1,
            hmargin = 2,
            vmargin = 2,
        },
        {
            selectors = {"button", "hasIcon"},
            border = 0,
            borderWidth = 0,
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
            selectors = {"label", "button", "~disabled", "hover"},
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
            fontFace = "@input",
            fontSize = 14,
            color = "@fg",
            bgcolor = "@bg",
            borderColor = "@border",
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
            hpad = 6,
            fontSize = 16,
            bold = true,
            borderFade = false,
            color = "@fg",
            bgcolor = "@bg",
            borderWidth = 0,
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
            selectors = {"dropdownLabel"},
            fontFace = "@input",
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
            bgimage = "panels/square.png",
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
            bgimage = "panels/square.png",
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
            bgimage = "panels/square.png",
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
            bgimage = "panels/square.png",
            width = "60%",
            height = "60%",
            halign = "center",
            valign = "center",
        },
        {
            selectors = {"sliderHandleInner"},
            bgimage = "panels/square.png",
            bgcolor = "@fg",
            width = "30%",
            height = "30%",
            halign = "center",
            valign = "center",
        },
        {
            selectors = {"enumSlider"},
            width = "100%",
            height = 24,
            flow = "horizontal",
        },
        {
            selectors = {"enumSliderOption"},
            bgimage = "panels/square.png",
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
            bgimage = "panels/square.png",
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
            bgimage = "panels/square.png",
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
            bgimage = "panels/square.png",
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
            width = 100,
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
        -- Image-tint-neutral on the tooltip icon's bgimage -- "white" opts
        -- out of the cascade's @bg tint so the icon paints in natural color.
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
        -- iconButton: small accent-able click target (24x24 by default).
        -- Add a withSuccess / withInfo / withWarning / withDanger class
        -- to recolor the hover state.
        --
        -- hudIconButton: larger HUD-bar button with selected/disabled
        -- states and a child hudIconButtonIcon that scales on hover.
        {
            selectors = {"iconButton"},
            bgcolor = "@fg",
            width = 24,
            height = 24,
        },
        {
            selectors = {"iconButton", "hover"},
            brightness = 2,
        },
        {
            selectors = {"iconButton", "press"},
            brightness = 0.8,
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
        {
            selectors = {"hudIconButton"},
            width = 58,
            height = 58,
            bgimage = "panels/square.png",
            bgcolor = "@bg",
            borderColor = "@fg",
            borderWidth = 1,
        },
        {
            selectors = {"hudIconButton", "hover"},
            brightness = 2.5,
            transitionTime = 0.1,
        },
        {
            selectors = {"hudIconButton", "press"},
            brightness = 0.8,
            transitionTime = 0.1,
        },
        {
            selectors = {"hudIconButton", "disabled"},
            brightness = 0.5,
            saturation = 0.2,
        },
        {
            selectors = {"hudIconButton", "selected"},
            brightness = 3.0,
            saturation = 1.4,
        },
        {
            selectors = {"hudIconButton", "selected", "tab"},
            brightness = 1,
            saturation = 1,
            bgcolor = "@bg",
            border = {x1 = 1, x2 = 1, y1 = 0, y2 = 1},
        },
        {
            selectors = {"hudIconButtonIcon"},
            width = "75%",
            height = "75%",
            halign = "center",
            valign = "center",
            bgcolor = "@fg",
        },
        {
            selectors = {"hudIconButtonIcon", "parent:hover"},
            brightness = 1.5,
            transitionTime = 0.1,
            scale = 1.15,
        },
        {
            selectors = {"hudIconButtonIcon", "parent:press"},
            brightness = 0.8,
            transitionTime = 0.1,
        },
        {
            selectors = {"hudIconButtonIcon", "parent:deselected"},
            saturation = 0.0,
            brightness = 0.8,
        },
        {
            selectors = {"hudIconButtonIcon", "parent:disabled"},
            saturation = 0.2,
            brightness = 0.5,
            scale = 1,
        },
        {
            selectors = {"hudIconButtonIcon", "parent:selected"},
            saturation = 1.5,
            brightness = 1.5,
        },

        --[[ Iconographic buttons (close / plus / delete) ]]
        {
            selectors = {"closeButton"},
            width = 24,
            height = 24,
            margin = 6,
            halign = "right",
            valign = "top",
            bgcolor = "@fg",
        },
        {
            selectors = {"closeButton", "hover"},
            brightness = 2,
        },
        {
            selectors = {"closeButton", "press"},
            brightness = 0.5,
        },
        {
            selectors = {"plusButton"},
            width = 24,
            height = 24,
            bgcolor = "@fg",
        },
        {
            selectors = {"plusButton", "hover"},
            brightness = 1.4,
        },
        {
            selectors = {"plusButton", "press"},
            brightness = 0.8,
        },
        {
            selectors = {"deleteItemButton"},
            width = 24,
            height = 24,
        },

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
            -- transitionTime = 0.2,
            -- rotate = 90,
        },
        -- {
        --     selectors = {"triangle", "expanded"},
        --     rotate = 0,
        --     transitionTime = 0.2,
        -- },
        {
            selectors = {"triangle", "hover"},
            brightness = 1.5,
        },

        --[[ Context menu ]]
        {
            selectors = {"contextMenuLabel"},
            fontSize = 20,
            color = "@fg",
        },
        {
            selectors = {"contextMenuLabel", "disabled"},
            fontSize = 20,
            color = "@fgMuted",
        },
        {
            selectors = {"contextMenuItem"},
            fontSize = 20,
            color = "@fg",
            height = "auto",
            width = "100%",
            bgcolor = "@bgAlt",
            borderColor = "@bg",
            borderWidth = 1,
        },
        {
            selectors = {"contextMenuItem", "hover"},
            borderColor = "@fg",
            borderWidth = 1,
            transitionTime = 0.2,
        },
        {
            selectors = {"contextMenuItem", "press"},
            brightness = 1.2,
            transitionTime = 0.2,
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
            bgimage = "panels/square.png",
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

        --[[ Inline form (label-left + control-right) ]]
        {
            selectors = {"formRow"},
            flow = "horizontal",
            width = "100%",
            height = "auto",
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
            selectors = {"formLabel"},
            fontSize = 18,
            color = "@fgStrong",
            width = "auto",
            height = "auto",
            minWidth = 140,
            halign = "right",
            valign = "center",
            hmargin = 8,
        },
        {
            selectors = {"formInput"},
            fontSize = 16,
            width = 180,
            height = 26,
            color = "@fg",
            halign = "right",
            valign = "center",
            textAlignment = "left",
        },
        {
            selectors = {"formInput", "multiline"},
            textAlignment = "topleft",
        },
        {
            selectors = {"formDropdown"},
            halign = "right",
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
        -- Vertical layout. Each row is {formStackedRow}, holding a
        -- {label, formStackedLabel} directly above its control
        -- ({formStackedControl}). Compound selectors on the control rules
        -- so the size beats any surface-specific {input}/{dropdown} sizes
        -- in caller MergeStyles extras.
        {
            selectors = {"formStackedRow"},
            flow = "vertical",
            width = "70%",
            height = "auto",
            halign = "left",
            bmargin = 8,
        },
        {
            selectors = {"label", "formStackedLabel"},
            fontSize = 18,
            width = "98%",
            height = "auto",
            halign = "left",
            valign = "top",
            bmargin = 4,
            bold = true,
        },
        -- Catch-all for any formStackedControl (multiselect, etc.).
        {
            selectors = {"formStackedControl"},
            width = "98%",
        },
        -- Inputs in stacked forms: 98% width, height 30 with internal padding
        -- so text isn't cramped against the borders. fontSize matches the
        -- dropdown (18) for visual consistency between input and dropdown
        -- controls in the same form.
        {
            selectors = {"input", "formStackedControl"},
            width = "98%",
            height = 30,
            hpad = 6,
            vpad = 4,
            fontSize = 18,
        },
        -- Dropdowns in stacked forms: 98% width and height matching inputs.
        {
            selectors = {"dropdown", "formStackedControl"},
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
            bgimage = "panels/square.png",
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
            bgimage = "panels/square.png",
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
            bgimage = "panels/square.png",
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
            -- bgimage = true,
            -- gradient = "@surfaceRadial",
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
        -- Image-tint-neutral on the InventorySlot bgimage -- "white" opts
        -- out of the cascade's @bg tint so the asset paints in natural color.
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
            bgimage = "panels/square.png",
            bgcolor = "@bgInverse",
            borderWidth = 2,
            borderColor = "@bg",
            cornerRadius = 8,
        },
        {
            selectors = {"modalButtonPanel"},
            width = "100%-50",
            height = 100,
            valign = "bottom",
            halign = "center",
            flow = "horizontal",
        },
        {
            selectors = {"prettyButton"},
            width = 140,
            height = 60,
        },
        {
            selectors = {"prettyButtonLabel"},
            fontSize = 20,
            bold = true,
            textAlignment = "center",
            width = "auto",
            height = "auto",
        },

        --[[ Framed panel ]]
        -- Image-tint-neutral on the square bgimage -- the @surfaceLinear
        -- gradient paints the visible color; "white" lets it through
        -- without being multiplied by the cascade's @bg.
        {
            selectors = {"framedPanel"},
            bgimage = "panels/square.png",
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
            scrollHandleColor = "@fgMuted",
        },
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
        {
            selectors = {"collapseForPlayers", "player"},
            collapsed = 1,
        },
        {
            selectors = {"hideUnlessParentHover"},
            hidden = 1,
        },
        {
            selectors = {"hideUnlessParentHover", "parent:hover"},
            hidden = 0,
        },

        -- =====================================================================
        -- 6. QUARANTINE -- feature-specific rules awaiting relocation
        -- =====================================================================
        --
        -- These rules don't belong in DefaultStyles per the file header
        -- doctrine -- they live here only because their consumers haven't
        -- been migrated yet. They are wrapped in a Lua block comment so
        -- they are inert (visible to readers, easy to relocate, not
        -- registered with the engine).
        --
        -- Re-enable an entry only as a short-term measure while a consumer
        -- is being migrated. The goal is to drain this block over time.

        --[==[
        --[[ rollable -- text styles for clickable rollable values ]]
        {
            selectors = {"rollable"},
            color = "#FFAAAA",
            textAlignment = "center",
            borderWidth = 0,
        },
        {
            selectors = {"rollable", "hover"},
            bgcolor = "@bg",
            borderWidth = 2,
            color = "#FFCCCC",
            borderColor = "#FFCCCC",
        },
        {
            selectors = {"rollable", "hover", "press"},
            borderWidth = 4,
            color = "#FFDDDD",
            borderColor = "#FFDDDD",
        },

        --[[ Pretty button (label-button decorative variant) ]]
        --
        -- NOTE: shares the kebab name with the modal prettyButton rule
        -- above. If reactivated, rename to disambiguate (e.g. button-pretty).
        {
            selectors = {"label", "button", "prettyButton"},
            fontSize = 24,
            hmargin = 16,
            vmargin = 16,
            width = "130% auto",
            height = "130% auto",
            borderWidth = 3,
        },

        --[[ Highlight bars ]]
        {
            selectors = {"highlightGood"},
            transitionTime = 1,
            bgcolor = "green",
        },
        {
            selectors = {"highlightBad"},
            transitionTime = 1,
            bgcolor = "red",
        },

        --[[ Clickable icon (generic hover-brightening icon) ]]
        {
            selectors = {"clickableIcon"},
            bgcolor = "@fg",
            width = 16,
            height = 16,
        },
        {
            selectors = {"clickableIcon", "hover"},
            brightness = 1.5,
        },
        {
            selectors = {"dice", "parent:clickableIcon", "parent:hover"},
            brightness = 1.5,
        },

        --[[ Settings button -- additive blend variant of iconButton ]]
        {
            selectors = {"iconButton", "settingsButton"},
            blend = "add",
        },

        --[[ Dockable panel ]]
        {
            selectors = {"dockablePanel"},
            bgimage = "panels/square.png",
        },

        --[[ Token image ]]
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

        --[[ Inventory slot ]]
        {
            selectors = {"inventorySlotHighlight"},
            bgimage = "panels/InventorySlot_Focus.png",
            bgcolor = "white",
            width = 90,
            height = 90,
            halign = "center",
            valign = "center",
            opacity = 0,
        },
        {
            selectors = {"inventorySlotHighlight", "hover"},
            opacity = 1,
        },
        {
            selectors = {"inventorySlotHighlight", "press"},
            bgcolor = "red",
        },
        {
            selectors = {"inventorySlotBackground"},
            bgimage = "panels/InventorySlot_Background.png",
            bgcolor = "white",
            width = 72,
            height = 72,
            margin = 0,
            pad = 0,
        },
        {
            selectors = {"inventorySlotIcon"},
            bgcolor = "white",
            halign = "center",
            valign = "center",
            width = "100%",
            height = "100%",
            hmargin = 0,
        },

        --[[ Advantage bar ]]
        {
            selectors = {"advantageBar"},
            halign = "center",
            height = 30,
            width = 340,
            flow = "horizontal",
        },
        {
            selectors = {"advantageElementLockIcon"},
            hidden = 1,
        },
        {
            selectors = {"advantageElementLockIcon", "parent:locked"},
            hidden = 0,
            margin = 2,
            bgcolor = "white",
            width = 16,
            height = 16,
            halign = "right",
            valign = "center",
        },
        {
            selectors = {"advantageElement"},
            bgimage = "panels/square.png",
            bgcolor = "#FFFFFF00",
            color = "white",
            width = 140,
            height = 22,
            fontSize = 14,
            textAlignment = "center",
            halign = "center",
        },
        {
            selectors = {"advantageElement", "hover", "~selected"},
            bgcolor = "#FFFFFF66",
        },
        {
            selectors = {"advantageElement", "selected", "~press"},
            borderWidth = 2,
            borderColor = "white",
            bgcolor = "white",
            gradient = "@advantageSelectedGradient",
        },
        {
            selectors = {"advantageElement", "locked"},
            bgcolor = "#FF7777FF",
        },
        {
            selectors = {"advantageElement", "press"},
            bgcolor = "white",
            color = "@bg",
        },
        {
            selectors = {"advantageRulesPanel"},
            bgcolor = "#000000AA",
            width = "auto",
            height = "auto",
            pad = 8,
            flow = "vertical",
        },
        {
            selectors = {"advantageRulesLabel"},
            color = "white",
            width = "auto",
            height = "auto",
            fontSize = 14,
        },
        {
            selectors = {"advantage"},
            color = "#AAFFAA",
        },
        {
            selectors = {"disadvantage"},
            color = "#FFAAAA",
        },

        --[[ Folder library ]]
        {
            selectors = {"folderContainer"},
            flow = "vertical",
            width = "100%",
            height = "auto",
            valign = "top",
        },
        {
            selectors = {"folderHeader"},
            width = "100%",
            flow = "horizontal",
            height = 24,
            bgimage = "panels/square.png",
            bgcolor = "@fg",
        },
        {
            selectors = {"folderHeader", "hover"},
            brightness = 1.5,
        },
        {
            selectors = {"folderHeader", "parent:drag-target"},
            brightness = 1.5,
        },
        {
            selectors = {"folderHeader", "parent:drag-target-hover"},
            brightness = 3,
        },
        {
            selectors = {"triangle", "folderTriangle"},
            bgimage = "panels/triangle.png",
            bgcolor = "@bg",
            width = 16,
            height = 12,
            hmargin = 4,
            valign = "center",
            halign = "left",
        },
        {
            selectors = {"triangle", "folderTriangle", "parent:expanded"},
            scale = {x = 1, y = -1},
            transitionTime = 0.1,
        },
        {
            selectors = {"folderLabel"},
            color = "@bg",
            fontSize = 18,
            width = "80%",
            height = "100%",
            halign = "left",
            textAlignment = "left",
        },

        --[[ Spell implementation status icons ]]
        {
            selectors = {"spellImplementationIcon"},
            width = 16,
            height = 16,
            hmargin = 4,
        },
        {
            selectors = {"spellImplementationIcon", "wontimplement"},
            bgimage = "icons/icon_common/icon_common_29.png",
            bgcolor = "@implStatus0",
        },
        {
            selectors = {"spellImplementationIcon", "unimplemented"},
            bgimage = "icons/icon_common/icon_common_29.png",
            bgcolor = "@implStatus1",
        },
        {
            selectors = {"spellImplementationIcon", "bronze"},
            bgimage = "icons/icon_common/icon_common_29.png",
            bgcolor = "@implStatus2",
        },
        {
            selectors = {"spellImplementationIcon", "silver"},
            bgimage = "icons/icon_common/icon_common_29.png",
            bgcolor = "@implStatus3",
        },
        {
            selectors = {"spellImplementationIcon", "gold"},
            bgimage = "icons/icon_common/icon_common_29.png",
            bgcolor = "@implStatus4",
        },

        --[[ Triggered action panels ]]
        {
            selectors = {"triggeredActionPanel"},
            bgcolor = "@triggerColor",
            color = "white",
            bold = true,
            textAlignment = "center",
        },
        {
            selectors = {"triggeredActionPanel", "free"},
            bgcolor = "@freeColor",
            color = "white",
        },
        {
            selectors = {"triggeredActionPanel", "passive"},
            bgcolor = "@passiveColor",
            color = "white",
        },
        {
            selectors = {"triggeredActionPanel", "expended"},
            saturation = 0.3,
            brightness = 0.3,
            color = "@bg",
        },
        ]==]
    },
}

-- After both schemes and the default theme are registered, restore the
-- user's saved selections (defaults to "default" / "default" if they
-- haven't picked anything yet).
ThemeEngine.RestoreActiveSelection()

if devmode() then
-- =============================================================================
-- Theme Test panel -- visual smoke test for the registered default theme.
-- Exercises the categories the engine currently covers so a glance at this
-- panel surfaces regressions when DefaultStyles changes.
-- =============================================================================

local function _themeTest()
    local rootPanel

    local function buildSchemeOptions()
        local opts = {}
        for _, s in ipairs(ThemeEngine.ListColorSchemes()) do
            table.insert(opts, {id = s.id, text = s.name})
        end
        return opts
    end

    -- Custom rules to validate ThemeEngine.MergeStyles end-to-end.
    -- The label class `mergeTest` should resolve via @danger and follow
    -- scheme switches.
    local mergeTestExtras = {
        { selectors = {"label", "mergeTest"}, color = "@danger", bold = true },
    }

    -- Fixed-size rebuild: every panel and every child uses an explicit
    -- width and height. Rows stack vertically inside a fixed-size root
    -- with a known total height. No "auto", no percentages, no overlap.

    local DIALOG_W   = 1100
    local DIALOG_H   = 720
    local ROW_W      = 1080
    local ROW_H      = 36
    local PAD        = 8
    local LABEL_W    = 160
    local LABEL_H    = 28
    local CTL_H      = 28

    rootPanel = gui.Panel{
        styles = ThemeEngine.MergeStyles(mergeTestExtras),
        classes = {"dialog"},
        width = DIALOG_W,
        height = DIALOG_H,
        flow = "vertical",
        pad = PAD,
        vscroll = true,

        gui.Label{
            classes = {"dialogTitle"},
            width = ROW_W,
            height = 32,
            text = "Theme Test",
        },

        -- Color scheme picker row
        gui.Panel{
            width = ROW_W,
            height = ROW_H,
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = LABEL_W,
                height = LABEL_H,
                valign = "center",
                text = "Color Scheme:",
            },
            gui.Dropdown{
                width = 220,
                height = CTL_H,
                valign = "center",
                idChosen = ThemeEngine.GetActiveColorScheme() or "default",
                options = buildSchemeOptions(),
                change = function(element)
                    ThemeEngine.SetActiveColorScheme(element.idChosen)
                    rootPanel.styles = ThemeEngine.MergeStyles(mergeTestExtras)
                end,
            },
            gui.Button{
                classes = {"btnSm"},
                width = 80,
                height = 32,
                valign = "center",
                hmargin = 8,
                text = "Reset",
                click = function()
                    ThemeEngine.SetActiveColorScheme("default")
                    rootPanel.styles = ThemeEngine.MergeStyles(mergeTestExtras)
                end,
            },
        },

        -- MergeStyles validation row
        gui.Panel{
            width = ROW_W,
            height = ROW_H,
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                classes = {"mergeTest"},
                width = 600,
                height = LABEL_H,
                valign = "center",
                text = "MergeStyles test (custom class -> @danger)",
            },
        },

        -- Buttons row
        gui.Panel{
            width = ROW_W,
            height = 44,
            halign = "left",
            flow = "horizontal",
            vmargin = 8,
            gui.Button{
                classes = {"btnSm"},
                width = 57, height = 31,
                valign = "center",
                text = "small",
            },
            gui.Button{
                classes = {"btnMd"},
                width = 129, height = 31,
                valign = "center", hmargin = 8,
                text = "medium",
            },
            gui.Button{
                classes = {"btnLg"},
                width = 175, height = 35,
                valign = "center", hmargin = 8,
                text = "large",
            },
            gui.Button{
                classes = {"disabled"},
                width = 129, height = 31,
                valign = "center", hmargin = 8,
                text = "disabled",
            },
            gui.Button{
                width = 36, height = 36,
                valign = "center", hmargin = 8,
                icon = "game-icons/griffin-symbol.png",
            },
        },

        -- Labels row (base, number, pending, link)
        gui.Panel{
            width = ROW_W,
            height = ROW_H,
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = 200, height = LABEL_H,
                valign = "center",
                text = "Base label",
            },
            gui.Label{
                classes = {"number"},
                width = 200, height = LABEL_H,
                valign = "center",
                text = "Number 12345",
            },
            gui.Label{
                classes = {"pending"},
                width = 200, height = LABEL_H,
                valign = "center",
                text = "Pending text",
            },
            gui.Label{
                classes = {"link"},
                width = 200, height = LABEL_H,
                valign = "center",
                text = "Link label",
            },
        },

        -- Input row
        gui.Panel{
            width = ROW_W,
            height = ROW_H,
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = LABEL_W, height = LABEL_H,
                valign = "center",
                text = "Input:",
            },
            gui.Input{
                classes = {"input"},
                width = 320, height = CTL_H,
                valign = "center",
                placeholderText = "type something...",
                text = "",
            },
        },

        -- Dropdown row
        gui.Panel{
            width = ROW_W,
            height = ROW_H,
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = LABEL_W, height = LABEL_H,
                valign = "center",
                text = "Dropdown:",
            },
            gui.Dropdown{
                width = 260, height = CTL_H,
                valign = "center",
                idChosen = "a",
                options = {
                    {id = "a", text = "Option A"},
                    {id = "b", text = "Option B"},
                    {id = "c", text = "Option C"},
                },
            },
        },

        -- Slider row
        gui.Panel{
            width = ROW_W,
            height = ROW_H,
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = LABEL_W, height = LABEL_H,
                valign = "center",
                text = "Slider:",
            },
            gui.Panel{
                width = 320, height = CTL_H,
                valign = "center",
                gui.EnumeratedSliderControl{
                    value = "two",
                    options = {
                        {id = "one",   text = "One"},
                        {id = "two",   text = "Two"},
                        {id = "three", text = "Three"},
                    },
                },
            },
        },

        -- Progress dice row
        gui.Panel{
            width = ROW_W,
            height = 72,
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = LABEL_W, height = 64,
                valign = "center",
                text = "Progress dice:",
            },
            gui.ProgressDice{
                width = 64, height = 64,
                valign = "center",
                progress = 0.4,
            },
        },

        -- Particle value row
        gui.Panel{
            width = ROW_W,
            height = ROW_H,
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = LABEL_W, height = LABEL_H,
                valign = "center",
                text = "Particle value:",
            },
            gui.ParticleValue{
                width = 140, height = 20,
                valign = "center",
                value = 10,
            },
        },

        -- Multiselect row (taller -- chips can wrap)
        gui.Panel{
            width = ROW_W,
            height = 100,
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = LABEL_W, height = LABEL_H,
                valign = "top",
                text = "Multiselect:",
            },
            gui.Multiselect{
                width = 320, height = 100,
                valign = "top",
                value = { red = true, blue = true },
                options = {
                    {id = "red",    text = "Red"},
                    {id = "blue",   text = "Blue"},
                    {id = "green",  text = "Green"},
                    {id = "yellow", text = "Yellow"},
                    {id = "purple", text = "Purple"},
                },
            },
        },

        -- Checkbox row
        gui.Panel{
            width = ROW_W,
            height = 40,
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Check{
                width = 240, height = 30,
                text = "Enable example",
                value = true,
            },
        },

        -- Tabs row
        gui.Panel{
            width = ROW_W,
            height = 44,
            halign = "left",
            flow = "horizontal",
            vmargin = 8,
            gui.Panel{
                classes = {"tab", "selected"},
                width = 100, height = 40,
                gui.Label{
                    width = 100, height = 40,
                    halign = "center", valign = "center",
                    text = "Tab 1",
                },
            },
            gui.Panel{
                classes = {"tab"},
                width = 100, height = 40,
                gui.Label{
                    width = 100, height = 40,
                    halign = "center", valign = "center",
                    text = "Tab 2",
                },
            },
            gui.Panel{
                classes = {"tab"},
                width = 100, height = 40,
                gui.Label{
                    width = 100, height = 40,
                    halign = "center", valign = "center",
                    text = "Tab 3",
                },
            },
        },

        -- panelRadial row
        gui.Panel{
            classes = {"panel", "panelRadial"},
            width = ROW_W,
            height = 80,
            halign = "left",
            vmargin = 8,
            gui.Label{
                width = ROW_W, height = 80,
                halign = "center", valign = "center",
                text = "panelRadial",
            },
        },
    }

    return rootPanel
end

LaunchablePanel.Register{
    name = "Theme Test",
    menu = "tools",
    icon = "icons/icon_tool/icon_tool_79.png",
    halign = "center",
    valign = "center",
    draggable = true,
    content = function()
        return _themeTest()
    end,
}
end -- devmode
