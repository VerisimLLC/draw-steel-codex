local mod = dmhub.GetModLoading()

local CreateFishingPanel

--[[LaunchablePanel.Register {
    name = "Fishing",
    icon = "panels/hud/56_map.png",
    halign = "center",
    valign = "center",
    content = function(options)
        return CreateFishingPanel(options)
    end,
}]]

local dice =  "ui-icons/dsdice/djordice-d10.png"
local bgcolor = "#0A0D0C"

CreateFishingPanel = function(options)
    local fishingPanel

    --king panel
    fishingPanel = gui.Panel {

        width = 700,
        height = 600,
        bgimage = false,
        bgcolor = "clear",

        

        flow = "vertical",

        --title queen panel
        gui.Panel {

            width = "100%",
            height = "10%",
            bgimage = true,
            bgcolor = bgcolor,

            border = 2,
            borderColor = "white",
            cornerRadius = {x1 = 12, x2 = 0, y1 = 12, y2 = 0},
            beveledcorners = true,

            flow = "vertical",

            gui.Label {

                text = "Fishing",

                width = "100%",
                height = "100%",

                textAlignment = "center",


            },


        },

        --middle queen panel

        gui.Panel {

            width = "100%",
            height = "85%",
            bgimage = true,
            bgcolor = "red",

            flow = "horizontal",

            --image panel
            gui.Panel {

                width = "50%",
                height = "100%",
                bgimage = mod.images.fishing,
                bgcolor = "white",


                flow = "vertical",

                gui.Panel {

                    width = 80,
                    height = 80,
                    bgimage = dice,
                    bgcolor = "white",


                    halign = "center",
                    valign = "bottom",

                    bmargin = 30,


                },


            },

            -- border = {x1 = 2, y1 = 2, x2 = 0, y2 = 0},

            gui.Panel {

                width = "50%",
                height = "100%",
                bgimage = true,
                bgcolor = bgcolor,


                flow = "vertical",

                gui.Label {

                    text = "Lake Ladoga",

                    height = "auto",
                    width = "auto",
                    color = "white",

                    textAlignment = "center",
                    halign = "center",
                    fontSize = 20,



                },

                gui.Divider {},

                gui.Label {

                    text = "Lake Ladoga[a] is a freshwater lake located in the Republic of Karelia and Leningrad Oblast in northwestern Russia, in the vicinity of Saint Petersburg.",

                    height = "35%",
                    width = "100%",
                    color = "white",

                    valign = "top",

                    textAlignment = "top",
                    halign = "center",
                    fontSize = 20,



                },

                gui.Panel{

                    bgimage = true,
                    bgcolor = "white",
                    width = "90%",
                    height = 1,

                    halign = "center",
                    valign = "top",
                },

            },



            --main info panel



        },

        --progress bar
        gui.Panel {

            width = "100%",
            height = "5%",
            bgimage = true,
            bgcolor = "green",

            flow = "horizontal",


        },


    }

    return fishingPanel
end
