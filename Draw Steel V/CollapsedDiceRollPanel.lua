local mod = dmhub.GetModLoading()

local CreateCollapsedDiceRollPanel

--[[LaunchablePanel.Register{
	name = "Roll Dice",
	icon = "game-icons/dice-twenty-faces-twenty.png",
	halign = "center",
	valign = "center",

    content = function()
        return CreateCollapsedDiceRollPanel()
    end,
}]]


CreateCollapsedDiceRollPanel = function()


    --king panel
    local collapsedDiceRollPanel = gui.Panel {

        height = 535,
        width = 400,

        bgimage = true,
        bgcolor = "#1F1D1A",
        border = 1.6,
        borderColor = "#826A49",

        flow = "vertical",

        beveledcorners = true,
        cornerRadius = 30,

        --top queen panel - "Power Roll", "Ability Outcome"
        gui.Panel {

            height = "25%",
            width = "100%",

            bgimage = true,
            bgcolor = "clear",

            flow = "vertical",

            gui.Panel {

                width = "auto",
                height = 60,

                halign = "center",
                valign = "top",

                tmargin = 25, 
                bmargin = 40,

                flow = "vertical",

                --"Power Roll"
                gui.Label {

                    text = "Power Roll",
                    fontFace = "Newzald",
                    fontSize = 34,
                    color = "white",

                    width = "auto",
                    height = "auto",

                    bgimage = true,
                    bgcolor = "clear",

                    halign = "center",
                    valign = "center",


                },

                --"Ability Outcome"
                gui.Label {

                    text = "Ability Outcome",
                    fontFace = "Newzald",
                    fontSize = 22,
                    color = "#A9977E",

                    width = "auto",
                    height = "auto",

                    bgimage = true,
                    bgcolor = "clear",

                    halign = "center",

                },

                gui.Panel{

                    bgimage = mod.images.divider1,
                    bgcolor = "white",

                    height = 15*1.32,
                    width = 300*1.32,

                    valign = "bottom",
                    tmargin = 15,


                },


            },

        

        },

        gui.Panel {

            height = "50%",
            width = "100%",

            bgimage = true,
            bgcolor = "clear",

            flow = "vertical",

            --dice queen panel THE DICE PANEL BELOW IS NOT VISIBLE. PLACEHOLDER!!!!!!!!
            gui.Panel {

                height = 110,
                width = "auto",

                bgimage = true,
                bgcolor = "clear",

                halign = "center",
                valign = "center",

                flow = "horizontal",


                gui.Panel {

                    height = 118*1.3,
                    width = 108*1.3,

                    bgimage = mod.images.d20,
                    bgcolor = "clear",

                    halign = "center",
                    valign = "center",


                },


                gui.Panel {

                    height = 100,
                    width = 10,

                    bgimage = true,
                    bgcolor = "clear",

                    halign = "center",
                    valign = "center",

                },

                gui.Panel {

                    height = 118*1.3,
                    width = 108*1.3,

                    bgimage = mod.images.d20,
                    bgcolor = "clear",

                    halign = "center",
                    valign = "center",

                },



            },

            
            gui.Label {

                text = "Click dice to roll",
                fontFace = "Newzald",
                fontSize = 20,
                textAlignment = "center",
                color = "#AE9B82",

                height = 35,
                width = 170,

                bgimage = true,
                bgcolor = "#131411",

                halign = "center",
                valign = "bottom",

                bmargin = 20,

                cornerRadius = 4,


            },

            gui.Panel {

                bgimage = mod.images.divider2,
                bgcolor = "white",

                valign = "bottom",
                halign = "center",
                height = 10 * 1.32,
                width = 280 * 1.32,


            },

        

        },

        gui.Panel {

            height = "25%",
            width = "100%",

            bgimage = true,
            bgcolor = "clear",

            flow = "vertical",

            gui.Panel {

                height = "100%",
                width = "auto",

                bgimage = true,
                bgcolor = "clear",

                valign = "center",
                halign = "center",


                flow = "horizontal",

                gui.Panel {


                    height = 80,
                    width = 160,

                    bgimage = true,
                    bgcolor = "clear",

                    valign = "top",
                    halign = "center",

                    tmargin = 11,
  

                    flow = "vertical",

                    gui.Label {

                        text = "Dice",
                        fontFace = "Newzald",
                        fontSize = 18,
                        textAlignment = "bottom",
                        color = "#896F4C",

                        height = "auto",
                        width = "auto",

                        halign = "center",
                        valign = "bottom",


                    },

                    gui.Label {

                        text = "2d10",
                        fontFace = "Newzald",
                        fontSize = 30,
                        color = "#FFCA79",
                        textAlignment = "center",

                        bgimage = true,
                        bgcolor = "#131411",

                        border = 1.6,
                        borderColor = "#4A3C30",
                        

                        height = 50,
                        width = 130,

                        halign = "center",
                        valign = "center",

                        cornerRadius = 4,


                    },


                },

                
                gui.Panel {

                    height = 80,
                    width = 160,

                    bgimage = true,
                    bgcolor = "clear",

                    valign = "top",
                    halign = "center",

                    tmargin = 11,

                    flow = "vertical",

                    gui.Label {

                        text = "Modifier",
                        fontFace = "Newzald",
                        fontSize = 18,
                        textAlignment = "bottom",
                        color = "#896F4C",

                        height = "auto",
                        width = "auto",

                        halign = "center",
                        valign = "bottom",


                    },
                    
                    gui.Label {

                        text = "+2",
                        fontFace = "Newzald",
                        fontSize = 30,
                        color = "#FFCA79",
                        textAlignment = "center",

                        bgimage = true,
                        bgcolor = "#131411",

                        border = 1.6,
                        borderColor = "#4A3C30",
                        

                        height = 50,
                        width = 130,

                        halign = "center",
                        valign = "center",

                        cornerRadius = 4,


                    },



                },
        

            },
        

        },



    }

    return collapsedDiceRollPanel

end
