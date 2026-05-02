local mod = dmhub.GetModLoading()

local fonts = gui.availableFonts
local fontOptions = {}
for _, font in ipairs(fonts) do
    table.insert(fontOptions, {text = font, id = font})
end

LaunchablePanel.Register{
	name = "Font Map",
    folder = "Development Tools",

	halign = "center",
	valign = "center",
    draggable = true,

	content = function(args)

        local m_font = fonts[1]

        local resultPanel
        resultPanel = gui.Panel{
            width = 900,
            height = 768,
            gui.Label{
                valign = "top",
                halign = "center",
                fontSize = 24,
                width = "auto",
                height = "auto",
                text = "Font Map",
            },

            gui.Panel{
                halign = "center",
                valign = "center",
                flow = "vertical",
                width = "90%",
                height = 640,
                gui.Dropdown{
                    idChosen = m_font,
                    options = fontOptions,
                    change = function(element)
                        m_font = element.idChosen
                        resultPanel:FireEventTree("refreshFont")
                    end,
                },

                gui.Panel{
                    width = "100%",
                    height = 600,
                    flow = "vertical",
                    vscroll = true,
                    create = function(element)
                        element:FireEventTree("refreshFont")
                    end,
                    refreshFont = function(element)
                        local s = ""
                        for i = 32, 126 do
                            s = s .. string.char(i)
                        end
                        local children = {}
                        children[#children+1] = gui.Label{
                            valign = "top",
                            halign = "center",
                            fontSize = 24,
                            width = "90%",
                            height = "auto",
                            text = s,
                            fontFace = m_font,
                        }
                        children[#children+1] = gui.Panel{
                            width = 1,
                            height = 8,
                        }

                        for i=32,126 do
                            local c = string.char(i)

                            children[#children+1] = gui.Panel{
                                flow = "horizontal",
                                height = 30,
                                width = "100%",
                                bgimage = true,
                                bgcolor = cond(i%2 == 0, "black", "#444444"),

                                gui.Label{
                                    valign = "top",
                                    halign = "left",
                                    lmargin = 8,
                                    fontSize = 24,
                                    width = 120,
                                    height = "auto",
                                    text = i,
                                },

                                gui.Label{
                                    valign = "top",
                                    halign = "left",
                                    lmargin = 8,
                                    fontSize = 24,
                                    width = 120,
                                    height = "auto",
                                    text = c,
                                },

                                gui.Label{
                                    valign = "top",
                                    halign = "left",
                                    lmargin = 8,
                                    fontSize = 24,
                                    width = 120,
                                    height = "auto",
                                    text = c,
                                    fontFace = m_font,
                                },
                            }

                        end

                        element.children = children

                    end,
                }
            },

        }

        return resultPanel
	end,
}

