local mod = dmhub.GetModLoading()

local g_goldColor = "srgb:#966D4B"
local g_accentColor = "srgb:#e9b86f"
local g_blurColor = "srgb:#000000cc"
local g_blurColorHighlight = "srgb:#000000ee"
local g_borderColor = "srgb:#A48B74"
local g_forbiddenColor = "srgb:#C73131"
local g_expendedColor = "srgb:#333333"

Styles.Ability = {
    blurColor = g_blurColor,
    borderColor = g_borderColor,
    forbiddenColor = g_forbiddenColor,
    expendedColor = g_expendedColor,
    accentColor = g_accentColor,
    goldColor = g_goldColor,
    blurColorHighlight = g_blurColorHighlight,

    gradientBar = gui.Gradient{
        point_a = { x = 0.5, y = 0 },
        point_b = { x = 0.5, y = 1 },
        stops = {
            {
                position = 0,
                color = "#000000cc",
            },
            {
                position = 0,
                color = "#00000000",
            },
            {
                position = 1,
                color = "#00000000",
            }
        }
    },

    maliceGlowGradient = gui.Gradient{
        type = "radial",
        point_a = { x = 0.5, y = 0 },
        point_b = { x = 0.8, y = 0.5 },
        stops = {
            {
                position = 0,
                color = "#DE1E47",
            },
            {
                position = 1,
                color = "#000000",
            },
        }
    },

    maliceDiamondGradient = gui.Gradient{
        point_a = { x = 1, y = 0 },
        point_b = { x = 0, y = 1 },
        stops = {
            {
                position = 0,
                color = "#000000ff",
            },
            {
                position = 0.5,
                color = "#000000ff",
            },
            {
                position = 0.5,
                color = "#00000000",
            },
            {
                position = 1,
                color = "#00000000",
            }
        }
    },

}

Styles.ActionMenu = {
    gui.Style {
        selectors = { "abilitySubMenu" },
        bgimage = true,
        bgcolor = g_blurColor,
        width = 205,
        height = "auto",
        maxHeight = 900,
        wrap = true,
        halign = "center",
        valign = "bottom",
        hmargin = 16,
        flow = "vertical",
    },
    gui.Style {
        selectors = { "submenuHeading" },
        width = 205,
        height = 24,
        fontSize = 12,
        color = g_goldColor,
        bold = true,
        textAlignment = "center",
        bgimage = true,
        bgcolor = "#1D1D1D",
        borderColor = "#606060",
        borderWidth = 1.5,
    },
    gui.Style {
        selectors = { "abilityHeading" },
        width = 205,
        minHeight = 24,
        height = "auto",
        vpad = 6,
        hpad = 0,
        vmargin = 4,
        halign = "center",
        valign = "bottom",
        bgimage = true,
        flow = "horizontal",
        bgcolor = "#00000077",
        borderColor = "#606060",
        borderWidth = 1.5,
    },
    gui.Style {
        selectors = { "abilityHeading", "hover" },
        brightness = 1.5,
        borderColor = "white",
        transitionTime = 0.1,
        soundEvent = "Mouse.Hover",
    },
    gui.Style {
        selectors = { "abilityHeading", "hover", "nonselectable" },
        borderColor = "#606060",
        transitionTime = 0.1,
    },
    gui.Style {
        selectors = { "abilityHeading", "suppressed" },
        borderColor = g_forbiddenColor,
    },
    gui.Style {
        selectors = { "abilityIconPanel" },
        width = 35,
        height = "100% width",
        valign = "center",
        halign = "left",
        hmargin = 10,
        bgcolor = "white",
        borderWidth = 0,
        bold = true,
        fontSize = 24,
        textAlignment = "center",
    },

    gui.Style {
        classes = { "costDiamond" },
        width = 30,
        height = "100% width",
        halign = "right",
        valign = "center",
        hmargin = -15,
        bgimage = true,
        borderColor = "#606060",
        bgcolor = "#1D1D1D",
        border = { x1 = 2, y1 = 2, x2 = 0, y2 = 0 },
    },
    gui.Style {
        classes = { "costDiamond", "parent:hover" },
        brightness = 1.5,
        borderColor = "white",
    },
    gui.Style {
        classes = { "costInnerDiamond" },

        width = "65%",
        height = "65%",
        bgimage = true,
        halign = "center",
        valign = "center",
        bgcolor = "#e9b86f",
        borderWidth = 2,
        borderColor = "#966D4B",
    },
    gui.Style {
        classes = { "costInnerDiamond", "cannotAfford" },
        bgcolor = g_forbiddenColor,
        borderColor = "white",
    },
    gui.Style {
        classes = { "costInnerDiamond", "malice" },
        width = "65%",
        height = "65%",
        bgimage = true,
        halign = "center",
        valign = "center",
        bgcolor = "#DE1E47",
        borderWidth = 2,
        borderColor = "#FF5076",
    },

    --"FF63494F",

    gui.Style {
        classes = { "costInnerDiamond", "cannotAfford", "malice" },
        bgcolor = "#63494F",
        borderColor = "#B899A0",
        opacity = 0.5,


    },

    gui.Style {
        selectors = { "abilityInfoPanel" },
        flow = "vertical",
        width = "100%-60",
        height = "auto",
        minHeight = 40,
        halign = "left",
        valign = "center",
    },
    gui.Style {
        selectors = { "abilityTitleArea" },
        width = "100%",
        height = "auto",
        flow = "horizontal",
    },
    gui.Style {
        selectors = { "abilityTitle" },
        fontSize = 16,
        fontFace = "Newzald",
        color = Styles.textColor,
        bold = true,
        textWrap = true,
        width = "100%-4",
        height = "auto",
        halign = "left",
        valign = "top",

    },
    gui.Style {
        selectors = { "abilityTitle", "expended" },
        color = g_expendedColor,
    },
    gui.Style {
        selectors = { "abilityTitle", "suppressed" },
        color = g_forbiddenColor,
    },

    gui.Style {
        selectors = { "abilityInfoLabel" },
        fontSize = 12,
        minFontSize = 6,
        color = Styles.textColor,
        textWrap = false,
        width = "100%-20",
        height = "auto",
        halign = "left",
        valign = "center",
        vmargin = 2,
    },
    gui.Style {
        selectors = { "abilityInfoLabel", "expended" },
        color = g_expendedColor,
    },
    gui.Style {
        selectors = { "abilityInfoLabel", "suppressed" },
        color = g_forbiddenColor,
    },


    gui.Style {
        classes = { "abilityCostLabel" },
        halign = "center",
        valign = "center",
        textAlignment = "center",
        bold = true,
        color = "white",
        fontSize = 16,
        minFontSize = 6,
        textWrap = false,
        width = "100%",
        height = "100%",
    },

    gui.Style {
        classes = { "abilityCostLabel", "malice", "cannotAfford" },
        halign = "center",
        valign = "center",
        textAlignment = "center",
        bold = true,
        color = "white",
        fontSize = 16,
        minFontSize = 6,
        textWrap = false,
        width = "100%",
        height = "100%",
        color = "#B3A0A4",
    },


}

Styles.ActionBar = {
    gui.Style {
        selectors = { "actionBarDrawer" },
        width = 205,
        height = "20% width",
        halign = "center",
        valign = "bottom",
        bgimage = true,
        bgcolor = "#10110F",
        flow = "vertical",
        cornerRadius = 10,
        beveledcorners = true,
        borderColor = g_borderColor,
        borderWidth = 2,
    },
    gui.Style {
        selectors = { "actionBarDrawer", "~available" },
        borderColor = "grey",
        transitionTime = 0.2,
    },
    gui.Style {
        selectors = { "diamond", "~available" },
        scale = 0,
        transitionTime = 0.2,
    },
    gui.Style {
        selectors = { "diamondAccent", "~available" },
        scale = { x = 1, y = 0 },
        transitionTime = 0.2,
    },
    gui.Style {
        selectors = { "actionBarDrawer", "available" },
        bgcolor = "#10110F",
    },
    gui.Style {
        selectors = { "actionBarDrawer", "hover" },
        transitionTime = 0.1,
        brightness = 1.5,
        soundEvent = "Mouse.Hover",
    },
    gui.Style {
        selectors = { "actionBarDrawer", "active" },
        bgcolor = "#10110F",
        brightness = 1.5,
        soundEvent = "Mouse.Click",
    },
    gui.Style {
        selectors = { "actionBarDrawer", "invokingAbility" },
        hidden = 1,
    },
    gui.Style {
        selectors = { "accent" },
        color = g_accentColor,
    },
    gui.Style {
        selectors = { "drawerSummary" },
        fontSize = 10,
        bgcolor = "#00000044",
        bgimage = true,
        bold = true,
        width = "100%",
        height = "25%",
        halign = "center",
        valign = "bottom",
        textAlignment = "center",
    },
    gui.Style {
        selectors = { "drawerTopPanel" },
        flow = "horizontal",
        width = "100%",
        height = "75%",
        halign = "center",
        valign = "top",
    },
    gui.Style {
        selectors = { "drawerIconPanel" },
        width = 26,
        height = 26,
        hmargin = 6,
        vmargin = 6,
        halign = "top",
        valign = "center",
        bgimage = true,
        bgcolor = "clear",
        borderColor = Styles.textColor,
        borderWidth = 1,
    },
    gui.Style {
        selectors = { "drawerIconPanel", "~available" },
        borderColor = "grey"
    },
    gui.Style {
        selectors = { "drawerIconPanel", "hover" },
        brightness = 2,
    },
    gui.Style {
        selectors = { "drawerInfoPanel" },
        flow = "vertical",
        width = "100%-44",
        height = "100%",
        halign = "left",
        valign = "center",
    },
    gui.Style {
        selectors = { "drawerTitle" },
        fontSize = 15,
        uppercase = true,
        color = g_goldColor,
        bold = true,
        tmargin = 3,
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
    },

    gui.Style {
        selectors = { "drawerTitle", "~available", "parent:active" },
        fontSize = 15,
        uppercase = true,
        color = "white",
        bold = true,
        tmargin = 3,
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
    },

    gui.Style {
        selectors = { "drawerTitle", "~available" },
        color = "grey",
    },


    gui.Style {
        selectors = { "drawerInfo" },
        fontSize = 10,
        minFontSize = 6,
        textAlignment = "topleft",
        color = Styles.textColor,
        opacity = 0.8,
        width = "100%",
        height = "30%",
        halign = "left",
        valign = "top",
    },
    gui.Style {
        selectors = { "drawerInfo", "~available" },
        color = "grey",
    },


}