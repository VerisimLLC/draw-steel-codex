local mod = dmhub.GetModLoading()

--- DefaultStyles — registers ThemeEngine's default color scheme and default theme.
---
--- ============================================================================
--- WHAT BELONGS IN THIS FILE
--- ============================================================================
---
--- This file holds **first-class widget vocabulary** — the selectors used by
--- reusable widgets that ship as part of the codebase (label, button, input,
--- dropdown, multiselect chips, hudIconButton, etc.). Both the generic shared
--- selectors AND each widget's internal/private namespace belong here:
---
---   * Generic:  label, button, input, dropdown, panel, framedPanel, tab, row,
---               imagePanel (opt-in for image-displaying panels), ...
---   * Widget internals:  dropdownLabel, dropdownTriangle, dropdownBorder,
---                        dropdownMenuSub, dropdownOption, multiselect-chip,
---                        multiselect-chip-text, multiselect-chip-remove, ...
---
--- Even though some of those names are "private" to one widget, the widget
--- itself is generic and reusable, so its vocabulary belongs in the default
--- theme. That lets the active scheme reach descendants through the ordinary
--- ancestor cascade — no control-level MergeStyles tricks, no ancestor
--- coupling.
---
--- ============================================================================
--- WHAT DOES NOT BELONG
--- ============================================================================
---
--- Surface-specific or ad-hoc rules. Examples:
---
---   * A selector used in one specific dialog or feature (DTHelpHover,
---     weaponHighlight, my-special-banner, etc.).
---   * "I want this one button red" overrides.
---
--- Those live in the *caller's* `ThemeEngine.MergeStyles({extras})` call, where
--- the extras get folded into the resolved theme for that caller's panel only.
---
--- ============================================================================
--- HOW THIS FILE IS ORGANIZED
--- ============================================================================
---
--- 1. Default color scheme registration — semantic color names and gradients,
---    grouped by purpose (surfaces, borders, text, accents, statuses, etc.).
---
--- 2. Loud test color scheme — bright neon override scheme used by the Theme
---    Test panel to verify scheme switching reaches every themed widget.
---    Gated behind `if devmode() then ... end` so only registered when the
---    game is running in dev mode; production users never see it.
---
--- 3. Default theme registration — fonts and the styles array. Within the
---    styles array, rules are grouped by widget. Each group has a comment
---    header naming the widget and the selectors it owns. Rules within a
---    group typically appear in order: base rule first, then state modifiers
---    (hover, press, selected, disabled), then variants (size variants,
---    semantic variants, etc.).
---
--- 4. Style rule conventions:
---    * Use @-name refs (@text, @background, @accent, @danger, etc.) for
---      properties that should follow the active scheme. Literal hex is
---      reserved for cases where the engine can't help (alpha-composites,
---      bespoke one-off colors that don't have a scheme name).
---    * `selectors = {...}` is the matching identity — never substituted.
---      Multi-selector rules are AND-matched (all must be classes on the widget).
---      Negation (`~classname`) and parent state (`parent:hover`) supported.
---    * Order properties for readability: structure (width/height/halign/valign)
---      → spacing (margin/pad) → visual (bg/border/cornerRadius/gradient)
---      → text (color/fontFace/fontSize) → state (brightness/saturation)
---      → interaction (transitionTime).
---
--- 5. Theme Test launchable panel — visible smoke test for the registered
---    theme. Exercises representative widgets and lets the user toggle between
---    the Default and Loud schemes to confirm theme reach. Gated behind
---    `if devmode() then ... end` so the launchable only appears in the
---    tools menu when the game is running in dev mode.
---
--- ============================================================================
--- ADDING A NEW WIDGET'S VOCABULARY
--- ============================================================================
---
--- 1. Decide the widget's selector names. Use a clear prefix that identifies
---    the widget (e.g. `dropdown*`, `multiselect-chip*`, `hudIconButton*`).
--- 2. Add a comment header in the styles array: `--[[ MyWidget ]]` with one
---    line about what the widget does and the selectors it owns.
--- 3. Add the rules in the order described above (base, states, variants).
--- 4. Use @-refs for theme-tracking properties; document any literal you keep
---    intentionally with a brief inline comment about why.
--- 5. In the widget's own .lua file, do NOT set a `styles =` array on the
---    widget's panel — that would cut the ancestor cascade. Just apply
---    classes; the cascade will reach them via the ancestor that owns
---    `ThemeEngine.MergeStyles(...)`.

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
        backgroundInv = "#BC9B7B",

        -- borders
        border        = "#DFDFDF",
        borderInv     = "#666666",

        -- text
        text          = "#EFEFEF",
        textLabel     = "#AEAEAE",
        textMuted     = "#666666",
        textPending   = "#999999",
        textInverse   = "#040404",

        -- accent family
        accent        = "#966D4B",
        accentStrong  = "#F1D3A5",
        accentHover   = "#E9B86F",

        disabled      = "#343432",

        -- rich black ramp (mirrors Styles.lua RichBlack02-04)
        richBlack02   = "#10110F",
        richBlack03   = "#191A18",
        richBlack04   = "#343432",

        -- grey ramp
        grey01        = "#9F9F9B",
        grey02        = "#666666",

        -- cream ramp
        cream01       = "#F3EDE7",
        cream02       = "#DFCFC0",
        cream03       = "#BC9B7B",

        -- gold ramp
        gold02        = "#49362C",
        gold03        = "#F1D3A5",
        gold04        = "#E9B86F",

        -- semantic statuses
        success       = "#6BA84F",
        info          = "#E9C868",
        warning       = "#E08A2E",
        danger        = "#C73131",
        modifierBuff  = "#2A4DFF",
        modifierDebuff= "#FF0000",

        -- trigger family
        triggerColor              = "#CCCC00",
        freeColor                 = "#9999FF",
        passiveColor              = "#006300",
        triggerColorAgainstText   = "#AAAA00",
        freeColorAgainstText      = "#7777EE",
        passiveColorAgainstText   = "#006300",

        -- implementation status (pink/red/bronze/silver/gold)
        implStatus0   = "#F82FCD",
        implStatus1   = "#FF0000",
        implStatus2   = "#CD7F32",
        implStatus3   = "#C0C0C0",
        implStatus4   = "#FFD700",
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

        dialogGradient = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 1},
            stops = {
                {position = 0, color = "#000000"},
                {position = 1, color = "#060606"},
            },
        },

        barGradient = {
            point_a = {x = -0.02, y = 0},
            point_b = {x = 1.02,  y = 0},
            stops = {
                {position = 0, color = "#060605"},
                {position = 1, color = "@richBlack03"},
            },
        },

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
                {position = 1, color = "@text"},
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

        horizontalGradient = {
            point_a = {x = 0, y = 0},
            point_b = {x = 1, y = 0},
            stops = {
                {position = 0,   color = "#FFFFFF00"},
                {position = 0.2, color = "#FFFFFFFF"},
                {position = 0.8, color = "#FFFFFFFF"},
                {position = 1,   color = "#FFFFFF00"},
            },
        },

        verticalGradient = {
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

if devmode() then
-- =============================================================================
-- Loud test color scheme — sparse override for visual diff testing.
-- Registers under id "loud". The engine falls back to the default scheme for
-- any color name this scheme doesn't define, so we only override the most
-- visible slots. Used by the Theme Test panel's scheme picker; not intended
-- for production use.
-- =============================================================================

ThemeEngine.RegisterColorScheme{
    id          = "loud",
    name        = "Loud (Test)",
    description = "Bright neon palette for verifying ThemeEngine recolors live.",
    colors = {
        -- surfaces
        background    = "#330066",
        backgroundAlt = "#5500AA",
        backgroundInv = "#00FFFF",

        -- borders
        border        = "#FFFF00",
        borderInv     = "#00FF00",

        -- text
        text          = "#00FF66",
        textLabel     = "#008833",
        textMuted     = "#FFAA00",
        textPending   = "#FF66CC",
        textInverse   = "#220033",

        -- accent family
        accent        = "#FF0088",
        accentStrong  = "#FFFF00",
        accentHover   = "#00FFFF",

        disabled      = "#444444",

        -- semantic accents (clearly different from default green/yellow/orange/red
        -- so the iconButton withX hover swaps are obvious when toggling schemes)
        success       = "#FF00CC",
        info          = "#00FFFF",
        warning       = "#AA00FF",
        danger        = "#88FF00",
    },
}
end -- devmode

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
        -- Base widget rules. Variants and utilities follow.

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
        -- Image-displaying panels: opt out of the inherited @background tint
        -- so a bgimage asset paints with natural colors. bgcolor stays white
        -- (image-tint-neutral). Borders are intentionally NOT set here —
        -- callers manage borderWidth / borderColor per their needs.
        {
            selectors = {"panel", "imagePanel"},
            bgcolor = "white",
        },

        --[[ Labels ]]
        {
            selectors = {"label"},
            fontFace = "@label",
            fontSize = 14,
            color = "@textLabel",
            bold = false,
        },
        {
            selectors = {"label", "number"},
            fontFace = "@number",
        },
        {
            selectors = {"label", "pending"},
            color = "@textPending",
        },
        {
            selectors = {"label", "dialogTitle"},
            fontSize = 24,
            halign = "center",
            width = "auto",
            height = "auto",
            valign = "top",
            tmargin = 12,
            bmargin = 0,
        },
        {
            selectors = {"label", "link"},
            priority = 5,
            color = "#C49562",
        },
        {
            selectors = {"label", "link", "hover"},
            priority = 5,
            color = "#FF99FFFF",
        },
        {
            selectors = {"label", "link", "press"},
            priority = 5,
            color = "#99FFFFFF",
        },

        --[[ Buttons ]]
        {
            selectors = {"label", "button"},
            height = 31,
            width = 129,
            fontFace = "@label",
            fontSize = 16,
            color = "@text",
            bgcolor = "@background",
            borderColor = "@border",
            border = 1,
            borderWidth = 1,
            cornerRadius = 5,
            fontWeight = "light",
            bold = false,
        },
        {
            selectors = {"button", "btn-sm"},
            height = 31,
            width = 57,
        },
        {
            selectors = {"button", "btn-md"},
            height = 31,
            width = 129,
        },
        {
            selectors = {"button", "btn-lg"},
            height = 35,
            width = 175,
            beveledcorners = true,
        },
        {
            selectors = {"button", "disabled"},
            bgcolor = "@disabled",
        },
        {
            selectors = {"label", "button", "~disabled", "hover"},
            bgcolor = "@backgroundInv",
            color = "@textInverse",
            borderColor = "@borderInv",
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
            color = "@textInverse",
            bgcolor = "@backgroundInv",
            textAlignment = "center",
            fontWeight = "bold",
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
            selectors = {"label", "button", "prettyButton"},
            fontSize = 24,
            hmargin = 16,
            vmargin = 16,
            width = "130% auto",
            height = "130% auto",
            borderWidth = 3,
        },
        {
            selectors = {"label", "button", "focus"},
            borderColor = "@text",
        },

        --[[ Rollable text styles ]]
        {
            selectors = {"rollable"},
            color = "#FFAAAA",
            textAlignment = "center",
            borderWidth = 0,
            priority = 10,
        },
        {
            selectors = {"rollable", "hover"},
            bgcolor = "@background",
            borderWidth = 2,
            color = "#FFCCCC",
            borderColor = "#FFCCCC",
            priority = 10,
        },
        {
            selectors = {"rollable", "hover", "press"},
            borderWidth = 4,
            color = "#FFDDDD",
            borderColor = "#FFDDDD",
            priority = 10,
        },

        --[[ Inputs ]]
        {
            selectors = {"input"},
            fontFace = "@input",
            fontSize = 14,
            color = "@text",
            bgcolor = "@background",
            borderColor = "@border",
        },
        {
            selectors = {"input", "focus"},
            borderColor = "@text",
        },
        {
            selectors = {"inputFaded"},
            borderColor = "@background",
            borderWidth = 3,
            borderFade = true,
            bgcolor = "@background",
        },
        -- Default search input has no border. Surfaces that want a bordered
        -- search input add it via their own MergeStyles extras.
        {
            selectors = {"searchInput"},
            hpad = 6,
            fontSize = 16,
            bold = true,
            borderFade = false,
            color = "@text",
            bgcolor = "@background",
            borderWidth = 0,
        },

        --[[ Dropdowns ]]
        {
            selectors = {"dropdown"},
            fontFace = "@input",
            fontSize = 14,
            color = "@text",
            bgcolor = "@backgroundAlt",
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
            bgcolor = "@text",
        },
        {
            selectors = {"label", "dropdownLabel"},
            -- priority = 10 to beat DMHub's engine-level dropdownLabel
            -- defaults. Layout-related properties (width / height / margins)
            -- on this 2-selector rule appear to take effect at priority 3,
            -- but fontFace specifically required a higher priority to win
            -- against the engine's 1-selector {dropdownLabel} rule. See
            -- DS_EDITOR_STYLING.md and AbilityEditor.lua:1690 for context.
            priority = 10,
            fontFace = "@input",
            fontSize = 18,
            minFontSize = 10,
            color = "@text",
            halign = "left",
            valign = "center",
            width = "100%-40",
            height = "100%",
            hmargin = 6,
        },
        -- Engine targets {dropdownLabel} (single selector) directly. Mirror
        -- that selector at priority 10 so our fontFace wins regardless of
        -- whether the engine merges by-selector or by-classes.
        {
            selectors = {"dropdownLabel"},
            priority = 10,
            fontFace = "@input",
        },
        {
            selectors = {"label", "dropdownLabel", "parent:hover"},
            color = "@textInverse",
        },
        {
            selectors = {"dropdownTriangle"},
            height = "30%",
            width = "160% height",
            bgcolor = "@text",
            halign = "right",
            valign = "center",
            hmargin = 6,
        },
        {
            selectors = {"dropdownTriangle", "parent:hover"},
            bgcolor = "@textInverse",
        },

        --[[ Dropdown popup (open state) ]]
        -- The popup panel that appears when a dropdown is opened. Composed of
        -- a dropdownBorder container holding a dropdownMenu (or dropdownMenuSub
        -- for submenus) full of dropdownOption rows.
        {
            selectors = {"dropdownBorder"},
            bgcolor = "@background",
            border = {x1 = 2, x2 = 2, y1 = 2, y2 = 0},
            borderColor = "@text",
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
            bgcolor = "@background",
            border = {x1 = 2, x2 = 2, y1 = 2, y2 = 2},
            borderColor = "@text",
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
            color = "@text",
        },
        {
            selectors = {"dropdownOption", "hover"},
            color = "@background",
            bgcolor = "@text",
        },
        {
            selectors = {"dropdownOption", "searchfocus"},
            color = "@background",
            bgcolor = "@text",
        },
        {
            selectors = {"dropdownOption", "disabled"},
            color = "@grey02",
        },
        -- Submenu-indicator triangle inside dropdown options that have a submenu.
        {
            selectors = {"submenuArrow"},
            bgcolor = "@text",
        },
        {
            selectors = {"submenuArrow", "parent:hover"},
            bgcolor = "@background",
        },

        --[[ Multiselect chips ]]
        --
        -- gui.Multiselect renders selected items as removable chips next to
        -- a Dropdown for adding new ones. Each chip is a {panel,
        -- multiselect-chip} container holding a {label, multiselect-chip-text}
        -- text label and a {panel, multiselect-chip-remove} delete button
        -- (with its own X label inside) that's hidden until the parent chip
        -- is hovered.

        -- Chip container.
        {
            selectors = {"panel", "multiselect-chip"},
            flow = "horizontal",
            width = "auto",
            height = "auto",
            pad = 4,
            margin = 4,
            bgimage = "panels/square.png",
            bgcolor = "@background",
            border = 1,
            borderColor = "@text",
            cornerRadius = 2,
        },
        {
            selectors = {"panel", "multiselect-chip", "hover"},
            brightness = 1.2,
        },

        -- Chip text label.
        {
            selectors = {"label", "multiselect-chip-text"},
            width = "auto",
            height = "auto",
            valign = "center",
            margin = 0,
            pad = 0,
            fontFace = "@input",
            fontSize = 14,
        },

        -- Remove button (X). Hidden until the parent chip is hovered.
        -- bgcolor stays a literal alpha-composite (#D530310F = faint red wash);
        -- the engine doesn't compose alphas, and a solid @danger here would be
        -- too heavy for a hover-only hint. Border + X-text use @danger so they
        -- recolor with the theme.
        {
            selectors = {"panel", "multiselect-chip-remove"},
            width = 14,
            height = 14,
            halign = "right",
            valign = "center",
            lmargin = 4,
            bgimage = true,
            bgcolor = "#D530310F",
            border = 1,
            borderColor = "@danger",
            cornerRadius = 2,
            bold = true,
            hidden = 1,
        },
        {
            selectors = {"panel", "multiselect-chip-remove", "parent:hover"},
            hidden = 0,
        },
        {
            selectors = {"panel", "multiselect-chip-remove", "hover"},
            brightness = 1.5,
        },

        -- The "X" label inside the remove button. Color is @text (not @danger)
        -- so the letter contrasts against its own red-bordered red-wash
        -- container; the parent's border + faint bg already carry the
        -- "danger zone" signal so the X just needs to be readable.
        {
            selectors = {"label", "multiselect-chip-remove"},
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "center",
            margin = 0,
            pad = 0,
            textAlignment = "center",
            color = "@text",
            fontFace = "@input",
            fontSize = 8,
        },
        {
            selectors = {"label", "multiselect-chip-remove", "parent:hover"},
            brightness = 1.5,
        },

        --[[ Sliders ]]
        {
            selectors = {"sliderHandleBorder"},
            borderWidth = 2,
            borderColor = "@text",
            bgcolor = "@background",
            bgimage = "panels/square.png",
            width = "60%",
            height = "60%",
            halign = "center",
            valign = "center",
        },
        {
            selectors = {"sliderHandleInner"},
            bgimage = "panels/square.png",
            bgcolor = "@text",
            width = "30%",
            height = "30%",
            halign = "center",
            valign = "center",
        },

        --[[ Utility classes ]]
        {
            scrollHandleColor = "@grey02",
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
            selectors = {"hideForPlayers", "player"},
            hidden = 1,
        },
        {
            selectors = {"collapsedForPlayers", "player"},
            collapsed = 1,
        },
        {
            priority = 100,
            selectors = {"collapsed-anim"},
            collapsed = 1,
            transitionTime = 0.2,
            uiscale = {x = 1, y = 0.001},
        },
        {
            selectors = {"hidden-unless-parent-hover"},
            hidden = 1,
        },
        {
            selectors = {"hidden-unless-parent-hover", "parent:hover"},
            hidden = 0,
        },
        {
            selectors = {"dockablePanel"},
            bgimage = "panels/square.png",
        },

        --[[ Highlight bars (good/bad) ]]
        {
            selectors = {"highlight_good"},
            priority = 5,
            transitionTime = 1,
            bgcolor = "green",
        },
        {
            selectors = {"highlight_bad"},
            priority = 5,
            transitionTime = 1,
            bgcolor = "red",
        },

        --[[ Clickable icons ]]
        {
            selectors = {"clickableIcon"},
            bgcolor = "@text",
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

        --[[ Generic icon buttons ]]
        {
            selectors = {"iconButton"},
            bgcolor = "@text",
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
            selectors = {"iconButton", "settingsButton"},
            blend = "add",
        },
        -- Semantic accent variants for icon buttons. Caller adds e.g. `withSuccess`
        -- as a class on top of `iconButton`; the default state stays @text, only
        -- hover recolors. Press inherits the generic brightness=0.8 dim.
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

        --[[ Close / delete / plus buttons ]]
        {
            priority = 5,
            selectors = {"close-button"},
            width = 24,
            height = 24,
            margin = 6,
            halign = "right",
            valign = "top",
            bgcolor = "@text",
        },
        {
            priority = 5,
            selectors = {"close-button", "hover"},
            brightness = 2,
        },
        {
            priority = 5,
            selectors = {"close-button", "press"},
            brightness = 0.5,
        },
        {
            priority = 5,
            selectors = {"delete-item-button"},
            width = 24,
            height = 24,
        },
        {
            priority = 5,
            selectors = {"plus-button"},
            width = 24,
            height = 24,
            bgcolor = "white",
        },
        {
            priority = 5,
            selectors = {"plus-button", "hover"},
            brightness = 1.4,
        },
        {
            priority = 5,
            selectors = {"plus-button", "press"},
            brightness = 0.8,
        },

        --[[ Dialogs ]]
        {
            selectors = {"panel", "dialog"},
            -- bgimage = true,
            -- gradient = "@panelRadial",
        },
        {
            selectors = {"label", "dlg-title"},
            width = "96%",
            height = "auto",
            valign = "top",
            halign = "center",
            textAlignment = "center",
            fontSize = 24,
        },
        {
            priority = 5,
            selectors = {"dialog-panel"},
            bgimage = "panels/InventorySlot_Background.png",
            bgcolor = "white",
            bgslice = 20,
            border = 10,
        },
        {
            priority = 5,
            selectors = {"dialog-panel", "fadein"},
            opacity = 0,
            uiscale = {x = 0.01, y = 0.01},
            transitionTime = 0.2,
        },
        {
            priority = 20,
            selectors = {"dialog-border"},
            hidden = 1,
        },

        --[[ Modal dialogs ]]
        {
            selectors = {"modal-dialog"},
            priority = 10,
            bgimage = "panels/square.png",
            bgcolor = "#888888FF",
            borderWidth = 2,
            borderColor = "@background",
            cornerRadius = 8,
        },
        {
            selectors = {"modal-button-panel"},
            priority = 10,
            width = "100%-50",
            height = 100,
            valign = "bottom",
            halign = "center",
            flow = "horizontal",
        },
        {
            selectors = {"pretty-button"},
            priority = 10,
            width = 140,
            height = 60,
        },
        {
            selectors = {"pretty-button-label"},
            priority = 2,
            fontSize = 20,
            bold = true,
            textAlignment = "center",
            width = "auto",
            height = "auto",
        },

        --[[ Tokens ]]
        {
            selectors = {"token-image"},
            halign = "center",
            valign = "center",
            width = 60,
            height = 60,
        },
        {
            selectors = {"token-image-portrait"},
            bgcolor = "white",
            width = "100%",
            height = "100%",
        },
        {
            selectors = {"token-image-frame"},
            width = "100%",
            height = "100%",
        },

        --[[ Checkboxes ]]
        {
            selectors = {"check-mark"},
            bgimage = "panels/square.png",
            bgcolor = "@text",
            halign = "center",
            valign = "center",
            width = "50%",
            height = "50%",
        },
        {
            selectors = {"check-background"},
            bgimage = "panels/square.png",
            bgcolor = "@background",
            halign = "left",
            valign = "center",
            height = "70%",
            width = "100% height",
            rmargin = 6,
            borderColor = "@text",
            borderWidth = 2,
        },
        {
            selectors = {"checkbox-label"},
            halign = "left",
            valign = "center",
            textAlignment = "left",
            borderWidth = 0,
            fontSize = 18,
            width = "auto",
            height = "auto",
        },
        {
            selectors = {"checkbox-label", "rightAlign"},
            rmargin = 8,
        },
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
            bgcolor = "#FFFFFF44",
            borderWidth = 1,
            borderColor = "white",
        },
        {
            selectors = {"check-background", "disabled"},
            saturation = 0,
        },
        {
            selectors = {"check-mark", "disabled"},
            saturation = 0,
        },
        {
            selectors = {"checkbox-label", "disabled"},
            color = "#777777FF",
        },

        --[[ HUD icon buttons ]]
        {
            selectors = {"hudIconButton"},
            width = 58,
            height = 58,
            bgimage = "panels/square.png",
            bgcolor = "@background",
            borderColor = "@text",
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
            bgcolor = "#0D0D0D",
            border = {x1 = 1, x2 = 1, y1 = 0, y2 = 1},
        },
        {
            selectors = {"hudIconButtonIcon"},
            width = "75%",
            height = "75%",
            halign = "center",
            valign = "center",
            bgcolor = "@text",
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

        --[[ Tabs ]]
        {
            selectors = {"tab"},
            bgimage = true,
            borderWidth = 1,
            borderColor = "#CCCCCC",
            width = 100,
            height = 40,
            fontSize = 18,
            bgcolor = "@background",
            color = "@grey02",
            hpad = 6,
        },
        {
            selectors = {"tab", "selected"},
            bold = true,
            color = "white",
            borderColor = "white",
            borderWidth = 2,
        },
        {
            selectors = {"tab", "hover"},
            brightness = 1.2,
        },

        --[[ Item tooltip ]]
        {
            selectors = {"label", "tooltipLabel"},
            color = "white",
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
            color = "#AAAAFF",
        },
        {
            selectors = {"hasTooltip", "hover"},
            color = "#FFAAFF",
        },

        --[[ Framed panel ]]
        {
            selectors = {"framedPanel"},
            bgimage = "panels/square.png",
            bgcolor = "white",
            cornerRadius = 4,
            gradient = "@dialogGradient",
            borderWidth = 2.2,
            borderColor = "@text",
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

        --[[ Tables ]]
        {
            selectors = {"label", "tableLabel"},
            pad = 6,
            fontSize = 16,
            width = "auto",
            height = "auto",
            color = "white",
        },
        {
            selectors = {"row"},
            width = "auto",
            height = "auto",
            bgimage = "panels/square.png",
        },
        {
            selectors = {"row", "oddRow"},
            bgcolor = "#222222FF",
        },
        {
            selectors = {"row", "evenRow"},
            bgcolor = "#444444FF",
        },
        {
            selectors = {"row", "highlight"},
            bgcolor = "#999944FF",
        },

        --[[ Context menu ]]
        {
            selectors = {"context-menu-label"},
            fontSize = 20,
            color = "@text",
        },
        {
            selectors = {"context-menu-label", "disabled"},
            fontSize = 20,
            color = "@grey02",
        },
        {
            selectors = {"context-menu-item"},
            fontSize = 20,
            color = "@text",
            height = "auto",
            width = "100%",
            bgcolor = "#994444",
            borderColor = "@background",
            borderWidth = 1,
        },
        {
            selectors = {"context-menu-item", "hover"},
            borderColor = "@text",
            borderWidth = 1,
            transitionTime = 0.2,
        },
        {
            selectors = {"context-menu-item", "press"},
            brightness = 1.2,
            transitionTime = 0.2,
        },

        --[[ Inventory slot ]]
        {
            selectors = {"inventory-slot-highlight"},
            bgimage = "panels/InventorySlot_Focus.png",
            bgcolor = "white",
            width = 90,
            height = 90,
            halign = "center",
            valign = "center",
            opacity = 0,
        },
        {
            selectors = {"inventory-slot-highlight", "hover"},
            opacity = 1,
        },
        {
            selectors = {"inventory-slot-highlight", "press"},
            bgcolor = "red",
        },
        {
            selectors = {"inventory-slot-background"},
            bgimage = "panels/InventorySlot_Background.png",
            bgcolor = "white",
            width = 72,
            height = 72,
            margin = 0,
            pad = 0,
        },
        {
            selectors = {"inventory-slot-icon"},
            bgcolor = "white",
            halign = "center",
            valign = "center",
            width = "100%",
            height = "100%",
            hmargin = 0,
        },

        --[[ Advantage bar ]]
        {
            selectors = {"advantage-bar"},
            halign = "center",
            height = 30,
            width = 340,
            flow = "horizontal",
        },
        {
            selectors = {"advantage-element-lock-icon"},
            hidden = 1,
        },
        {
            selectors = {"advantage-element-lock-icon", "parent:locked"},
            hidden = 0,
            margin = 2,
            bgcolor = "white",
            width = 16,
            height = 16,
            halign = "right",
            valign = "center",
        },
        {
            selectors = {"advantage-element"},
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
            selectors = {"advantage-element", "hover", "~selected"},
            bgcolor = "#FFFFFF66",
        },
        {
            selectors = {"advantage-element", "selected", "~press"},
            borderWidth = 2,
            borderColor = "white",
            bgcolor = "white",
            gradient = "@advantageSelectedGradient",
        },
        {
            selectors = {"advantage-element", "locked"},
            bgcolor = "#FF7777FF",
        },
        {
            selectors = {"advantage-element", "press"},
            bgcolor = "white",
            color = "@background",
        },
        {
            selectors = {"advantage-rules-panel"},
            bgcolor = "#000000AA",
            width = "auto",
            height = "auto",
            pad = 8,
            flow = "vertical",
        },
        {
            selectors = {"advantage-rules-label"},
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

        --[[ Forms ]]
        {
            selectors = {"formPanel"},
            flow = "horizontal",
            width = "100%",
            height = "auto",
            valign = "top",
            vmargin = 4,
        },
        {
            selectors = {"formLabel"},
            fontSize = 18,
            color = "white",
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
            color = "white",
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

        --[[ Stacked forms ]]
        --
        -- Vertical "label-above-control" form layout. Each row is a panel with
        -- class formStackedRow, holding a label (formStackedLabel) directly
        -- above its control (formStackedControl). Use this in place of the
        -- horizontal {formPanel}/{formLabel}/{formInput} vocabulary when a
        -- compendium-style stacked layout is desired.
        --
        -- Compound selectors are used for control width so the rule beats any
        -- surface-specific {input}/{dropdown} size rules in caller MergeStyles
        -- extras. The bare {formStackedControl} rule covers anything else
        -- (multiselects, etc.).
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
        -- Generic formStackedControl rule (catch-all for multiselect/etc.).
        {
            selectors = {"formStackedControl"},
            priority = 3,
            width = "98%",
        },
        -- Inputs in stacked forms: 98% width, height 30 with internal padding
        -- so text isn't cramped against the borders. fontSize matches the
        -- dropdown (18) for visual consistency between input and dropdown
        -- controls in the same form.
        {
            selectors = {"input", "formStackedControl"},
            priority = 3,
            width = "98%",
            height = 30,
            hpad = 6,
            vpad = 4,
            fontSize = 18,
        },
        -- Dropdowns in stacked forms: 98% width and height matching inputs
        -- so the two control types render at consistent dimensions.
        {
            selectors = {"dropdown", "formStackedControl"},
            priority = 3,
            width = "98%",
            height = 30,
        },

        --[[ Feature cards ]]
        --
        -- Collapsible "card" wrapping a single feature inside a class / race /
        -- background / kit / etc. editor. The card is the visual unit; the
        -- outer features-list container (built by ClassLevel:CreateEditor) is
        -- transparent so cards stack cleanly without nested fills.
        --
        -- Structure:
        --   featureCard          outer frame: @backgroundAlt fill, 1px border,
        --                        70% width to match formStackedRow.
        --   featureCardHeader    top strip: expando triangle, name display,
        --                        delete button. Separated from the body by a
        --                        borderBottom line.
        --   featureCardBody      transparent (no bgimage), holds the form
        --                        rows. Card's @backgroundAlt shows through.
        {
            selectors = {"featureCard"},
            bgimage = "panels/square.png",
            bgcolor = "@backgroundAlt",
            width = "70%",
            height = "auto",
            halign = "left",
            flow = "vertical",
            bmargin = 12,
        },
        -- Header: border on all four sides so the card's outer frame is drawn
        -- here on the top + sides, and its bottom edge serves as the separator
        -- between header and body. Fill is transparent so the card's bg shows
        -- through unmodified.
        {
            selectors = {"featureCardHeader"},
            bgimage = "panels/square.png",
            bgcolor = "clear",
            border = 1,
            borderColor = "@border",
            borderBox = true,
            width = "100%",
            height = 30,
            flow = "horizontal",
            hpad = 8,
        },
        -- Body: border on left, right, bottom (y1 = bottom). Top edge is the
        -- header's bottom border, already drawn. Same fill as the card so the
        -- inside reads as one continuous @backgroundAlt surface.
        {
            selectors = {"featureCardBody"},
            bgimage = "panels/square.png",
            bgcolor = "@backgroundAlt",
            border = { x1 = 1, x2 = 1, y1 = 1, y2 = 0 },
            borderColor = "@border",
            borderBox = true,
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 12,
        },

        --[[ Triangle (general) ]]
        --
        -- Expand/collapse arrow. Defaults to "closed" (rotate = 90, pointing
        -- right). Toggling the "expanded" class rotates to point down with a
        -- short transition. Call sites should use this cascade rather than
        -- attaching their own `styles = ...triangleStyles` override.
        {
            selectors = {"triangle"},
            bgimage = "panels/triangle.png",
            bgcolor = "@text",
            width = 12,
            height = 12,
            hmargin = 4,
            valign = "center",
            halign = "left",
            rotate = 90,
            transitionTime = 0.2,
        },
        {
            selectors = {"triangle", "expanded"},
            priority = 5,
            rotate = 0,
            transitionTime = 0.2,
        },
        {
            selectors = {"triangle", "hover"},
            brightness = 1.5,
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
            bgcolor = "@text",
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
            bgcolor = "@background",
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
            color = "@background",
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
            color = "@background",
        },
    },
}

if devmode() then
-- =============================================================================
-- Theme Test panel — visual smoke test for the registered default theme.
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
    -- The label class `merge-test` should resolve via @danger and follow scheme switches.
    local mergeTestExtras = {
        { selectors = {"label", "merge-test"}, color = "@danger", bold = true },
    }

    rootPanel = gui.Panel{
        styles = ThemeEngine.MergeStyles(mergeTestExtras),
        classes = {"dialog"},
        width = 1110,
        height = 640,
        flow = "vertical",
        gui.Label{
            classes = {"dlg-title"},
            text = "Theme Test",
        },

        -- Color scheme picker — switches active scheme and refreshes the panel
        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = 160, height = 28,
                valign = "center",
                text = "Color Scheme:",
            },
            gui.Dropdown{
                width = 220,
                height = 28,
                valign = "center",
                idChosen = ThemeEngine.GetActiveColorScheme() or "default",
                options = buildSchemeOptions(),
                change = function(element)
                    ThemeEngine.SetActiveColorScheme(element.idChosen)
                    rootPanel.styles = ThemeEngine.MergeStyles(mergeTestExtras)
                end,
            },
            gui.Button{
                classes = {"btn-sm"},
                valign = "center",
                hmargin = 8,
                text = "Reset",
                click = function()
                    ThemeEngine.SetActiveColorScheme("default")
                    rootPanel.styles = ThemeEngine.MergeStyles(mergeTestExtras)
                end,
            },
        },

        -- MergeStyles validation: this label's color comes from a custom rule
        -- merged in via ThemeEngine.MergeStyles, with @danger as a @-ref.
        -- Should be red on default, acid-green on Loud.
        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                classes = {"merge-test"},
                width = 400, height = "auto",
                text = "MergeStyles test (custom class -> @danger)",
            },
        },

        -- Buttons row
        gui.Panel{
            width = "96%",
            height = "auto",
            valign = "top",
            halign = "left",
            flow = "horizontal",
            vmargin = 8,
            gui.Button{
                classes = {"btn-sm"},
                valign = "center",
                text = "small",
            },
            gui.Button{
                classes = {"btn-md"},
                valign = "center",
                text = "medium",
            },
            gui.Button{
                classes = {"btn-lg"},
                valign = "center",
                text = "large",
            },
            gui.Button{
                classes = {"disabled"},
                valign = "center",
                text = "disabled",
            },
        },

        -- Labels row (base, number, pending, link)
        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = 200, height = "auto",
                text = "Base label",
            },
            gui.Label{
                classes = {"number"},
                width = 200, height = "auto",
                text = "Number 12345",
            },
            gui.Label{
                classes = {"pending"},
                width = 200, height = "auto",
                text = "Pending text",
            },
            gui.Label{
                classes = {"link"},
                width = 200, height = "auto",
                text = "Link label",
            },
        },

        -- Input
        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Input{
                classes = {"input"},
                width = 320, height = 28,
                placeholderText = "type something...",
                text = "",
            },
        },

        -- Dropdown
        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Dropdown{
                width = 260,
                height = 28,
                idChosen = "a",
                options = {
                    {id = "a", text = "Option A"},
                    {id = "b", text = "Option B"},
                    {id = "c", text = "Option C"},
                },
            },
        },

        -- Enumerated slider — exercises gui.EnumeratedSliderControl theming.
        -- Each option recolors live on scheme switch via the control's own
        -- OnThemeChanged subscription.
        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = 160, height = 24,
                valign = "center",
                text = "Slider:",
            },
            gui.Panel{
                width = 320,
                height = 28,
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

        -- Progress dice — intentionally theme-blind (renders the codex logo
        -- at natural color regardless of active scheme; bgcolor="white" is
        -- image tint, not panel background).
        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = 160, height = 64,
                valign = "center",
                text = "Progress dice:",
            },
            gui.ProgressDice{
                width = 64,
                height = 64,
                progress = 0.4,
                halign = "left",
                valign = "center",
            },
        },

        -- Particle value — exercises gui.ParticleValue which overrides the
        -- generic `label` selector inside its own subtree via MergeStyles.
        -- The internal labels recolor live on scheme switch.
        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = 160, height = 24,
                valign = "center",
                text = "Particle value:",
            },
            gui.ParticleValue{
                value = 10,
                halign = "left",
                valign = "center",
            },
        },

        -- Multiselect — chips + dropdown, all themed via the controller's
        -- merged styles. Hover a chip to reveal the @danger remove button.
        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Label{
                width = 160, height = 24,
                valign = "top",
                text = "Multiselect:",
            },
            gui.Multiselect{
                width = 320,
                halign = "left",
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

        -- Checkbox
        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "left",
            flow = "horizontal",
            vmargin = 4,
            gui.Check{
                text = "Enable example",
                value = true,
            },
        },

        -- Tabs
        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "left",
            flow = "horizontal",
            vmargin = 8,
            gui.Panel{
                classes = {"tab", "selected"},
                gui.Label{ text = "Tab 1", halign = "center", valign = "center" },
            },
            gui.Panel{
                classes = {"tab"},
                gui.Label{ text = "Tab 2", halign = "center", valign = "center" },
            },
            gui.Panel{
                classes = {"tab"},
                gui.Label{ text = "Tab 3", halign = "center", valign = "center" },
            },
        },

        -- Framed panel (for radial gradient + framed look)
        gui.Panel{
            classes = {"panel", "radial-gradient"},
            width = "96%",
            height = 80,
            halign = "left",
            vmargin = 8,
            gui.Label{
                halign = "center",
                valign = "center",
                text = "Radial-gradient panel",
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