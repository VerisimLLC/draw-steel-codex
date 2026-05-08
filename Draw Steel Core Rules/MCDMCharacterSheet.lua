local mod = dmhub.GetModLoading()

local g_styles = {
    gui.Style{
        selectors = {"statsHeading"},
        color = "black",
        width = "auto",
        height = "auto",
        fontSize = 16,
        bold = true,
        uppercase = true,
    },
    gui.Style{
        selectors = {"statsLabel"},
        color = "black",
        width = "auto",
        height = "auto",
        fontSize = 18,
    },
    gui.Style{
        selectors = {"charsheetTitledPane"},
    },
    gui.Style{
        selectors = {"charsheetPane"},
        borderWidth = 3,
        bgimage = "panels/square.png",
        bgcolor = "white",
        borderColor = "black",
        pad = 8,
    },
    gui.Style{
        selectors = {"heading"},
        height = 24,
        width = "100%",
        flow = "horizontal",
    },
    gui.Style{
        selectors = {"headingEndCap"},
        width = 24,
        height = 24,
        bgimage = "panels/right-angle-triangle.png",
        bgcolor = "black",
    },
    gui.Style{
        selectors = {"headingEndCap", "right"},
        scale = {x = -1, y = 1},
    },
    gui.Style{
        selectors = {"headingLabel"},
        height = 24,
        width = "100%-48",
        textAlignment = "center",
        fontSize = 16,
        bgimage = "panels/square.png",
        bgcolor = "black",
        color = "white",
        uppercase = true,
    },
}

function CharSheet.Heading(args)
    local text = args.text
    args.text = nil

    local params = {
        classes = {"heading"},
        gui.Panel{
            classes = {"headingEndCap", "left"},
        },
        gui.Label{
            classes = {"headingLabel"},
            text = text,
        },
        gui.Panel{
            classes = {"headingEndCap", "right"},
        },
    }

    for k,v in pairs(args) do
        params[k] = v
    end

    return gui.Panel(params)
end

function CharSheet.Pane(args)
    local params = {
        classes = {"charsheetPane"},
    }

    for k,v in pairs(args) do
        params[k] = v
    end

    return gui.Panel(params)
end

function CharSheet.TitledPane(args)
    local title = args.title
    args.title = nil

    local params = {
        classes = {"charsheetTitledPane"},
        CharSheet.Pane{
            width = "100%",
            height = "100%-8",
            args.content,
        },
        CharSheet.Heading{
            floating = true,
            text = title,
            valign = "top",
            y = -12,
            lmargin = 8,
        },
    }

    args.content = nil

    for k,v in pairs(args) do
        params[k] = v
    end

    return gui.Panel(params)
end

function CharSheet.HealthDisplay(args)
    local contents = gui.Panel{
        flow = "horizontal",

        gui.Label{
            classes = {"statsLabel"},
            fontSize = 32,
            halign = "center",
            valign = "center",
            y = 10,

            refreshToken = function(element, info)
			    local c = info.token.properties
                element.text = tostring(c:CurrentHitpoints())
            end,
        },

        gui.Panel{
            floating = true,
            x = 120,
            flow = "vertical",
            halign = "right",
            width = 100,
            height = "auto",

            CharSheet.Pane{
                width = "100%",
                height = 40,
                vmargin = 16,
                flow = "vertical",

                gui.Label{
                    classes = {"statsHeading"},
                    width = "100%",
                    textAlignment = "left",
                    text = "Max",
                },
                gui.Label{
                    classes = {"statsLabel"},
                    width = "100%",
                    textAlignment = "center",
                    refreshToken = function(element, info)
                        local c = info.token.properties
                        element.text = tostring(c:MaxHitpoints())
                    end,
                }

            },

            CharSheet.Pane{
                width = "100%",
                height = 40,
                flow = "vertical",

                gui.Label{
                    classes = {"statsHeading"},
                    width = "100%",
                    textAlignment = "left",
                    text = "Bloodied",
                },
                gui.Label{
                    classes = {"statsLabel"},
                    width = "100%",
                    textAlignment = "center",
                    refreshToken = function(element, info)
                        local c = info.token.properties
                        element.text = tostring(c:BloodiedThreshold())
                    end,
                }
            },
        },

    }

    local params ={
        title = "Health",
        content = contents,
        width = 196,
        height = 128,
    }

    for k,v in pairs(args) do
        params[k] = v
    end

    return CharSheet.TitledPane(params)
end

function MCDMCharacterSheet()
    return gui.Panel{
        styles = ThemeEngine.MergeStyles(g_styles),

        width = "100%",
        height = "100%",
        flow = "horizontal",

        CharSheet.HealthDisplay{
            halign = "center",
            valign = "center",
        },


    }

end

--CharSheet.RegisterTab{
--	id = "CharacterSheet",
--	text = "Character",
--	panel = MCDMCharacterSheet,
--}