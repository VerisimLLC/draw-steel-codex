local mod = dmhub.GetModLoading()

LaunchablePanel.Register {
    name = "Control Zoo",
    folder = "Development Tools",

    halign = "center",
    valign = "center",
    draggable = true,

    content = function(args)
        local outputLabel = gui.Label {
            halign = "center",
            valign = "bottom",
            fontSize = 16,
            width = "auto",
            height = "auto",
            vmargin = 8,
        }

        local ControlEntry = function(args)
            return gui.Panel {
                classes = { "formPanel" },
                gui.Label {
                    classes = { "formLabel" },
                    text = args.name,
                },
                gui.Panel {
                    classes = { "controlArea" },
                    args.control,
                },
            }
        end



        local resultPanel
        resultPanel = gui.Panel {
            width = 900,
            height = 768,
            styles = Styles.Default,
            gui.Label {
                valign = "top",
                halign = "center",
                fontSize = 24,
                width = "auto",
                height = "auto",
                text = "Control Samples",
            },

            gui.Panel {
                halign = "center",
                valign = "center",
                flow = "vertical",
                width = "90%",
                height = 640,
                vscroll = true,

                styles = {
                    {
                        selectors = { "formPanel" },
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                    },
                    {
                        selectors = { "formLabel" },
                        width = "auto",
                        minWidth = 160,
                        fontSize = 18,
                    },
                    {
                        selectors = { "controlArea" },
                        width = "70%",
                        halign = "right",
                        valign = "center",
                        height = "auto",
                    },
                },

                ControlEntry{
                    name = "Action Button",
                    control = gui.Panel{
                        classes = {"action-btn-test-controller"},
                        height = "auto",
                        vpad = 10,
                        halign = "center",
                        flow = "vertical",
                        setAvailable = function(element, isAvailable)
                            local actionButton = element:Get("test-action-button")
                            if actionButton then
                                actionButton:FireEvent("setAvailable", isAvailable)
                            end
                        end,
                        setSelected = function(element, isSelected)
                            local actionButton = element:Get("test-action-button")
                            if actionButton then
                                actionButton:FireEvent("setSelected", isSelected)
                            end
                        end,
                        gui.ActionButton{
                            id = "test-action-button",
                            text = "MOVEMENT",
                            available = true,
                            selected = false,
                        },
                        gui.Check{
                            text = "Selected",
                            value = false,
                            placement = "left",
                            change = function(element)
                                local controller = element:FindParentWithClass("action-btn-test-controller")
                                if controller then
                                    controller:FireEvent("setSelected", element.value)
                                end
                            end
                        },
                        gui.Check{
                            text = "Available",
                            value = true,
                            placement = "left",
                            change = function(element)
                                local controller = element:FindParentWithClass("action-btn-test-controller")
                                if controller then
                                    controller:FireEvent("setAvailable", element.value)
                                end
                            end
                        }
                    }
                },

                ControlEntry {
                    name = "Beveled panel",
                    control = gui.Panel {
                        width = 100,
                        height = 100,
                        bgimage = true,
                        bgcolor = "black",
                        borderColor = "white",
                        borderWidth = 2,
                        cornerRadius = 10,
                        beveledcorners = true,
                        halign = "center",
                        valign = "center",

                    },
                },

                ControlEntry {
                    name = "Button",
                    control = gui.Button {
                        halign = "center",
                        valign = "center",
                        text = "Click Me",
                        click = function()
                            outputLabel.text = "Button clicked!"
                        end,

                        linger = gui.Tooltip("This is a button"),
                    },
                },

                ControlEntry{
                    name = "Beveled Button",
                    control = gui.Button{
                        text = "Click me, too",
                        halign = "center",
                        valign = "center",
                        width = 120,
                        height = 36,
                        fontSize = 20,
                        cornerRadius = 8,
                        beveledcorners = true,
                        borderColor = "#bc9b7b",
                        
                    }
                },

                ControlEntry {
                    name = "Delete Button",
                    control = gui.DeleteItemButton {
                        halign = "center",
                        valign = "center",
                        click = function()
                            outputLabel.text = "DELETE clicked!"
                        end,
                    },
                },

                ControlEntry {
                    name = "Dropdown",
                    control = gui.Dropdown {
                        halign = "center",
                        valign = "center",
                        options = {
                            {
                                id = "option1",
                                text = "Option 1",
                            },
                            {
                                id = "option2",
                                text = "Option 2",
                            },
                            {
                                id = "option3",
                                text = "Option 3",
                            },
                        },
                        idChosen = "option1",
                        change = function(element)
                            outputLabel.text = "Dropdown changed to " .. element.idChosen
                        end,

                    },
                },

                ControlEntry {
                    name = "Checkbox",
                    control = gui.Check {
                        halign = "center",
                        valign = "center",
                        text = "Check me!",
                        value = true,
                        change = function(element)
                            outputLabel.text = "Checkbox changed to " .. tostring(element.value)
                        end,
                    },
                },

                ControlEntry {
                    name = "Text Input (single line)",
                    control = gui.Input {
                        halign = "center",
                        valign = "center",

                        width = 180,
                        height = 20,
                        fontSize = 16,

                        placeholderText = "Enter text...",
                        characterLimit = 80,
                        editlag = 0.2,
                        edit = function(element)
                            outputLabel.text = "Text input changed to " .. element.text
                        end,

                        change = function(element)
                            outputLabel.text = "Text input submitted: " .. element.text
                        end,

                    },
                },

                ControlEntry {
                    name = "Text Input (multi line)",
                    control = gui.Input {
                        halign = "center",
                        valign = "center",
                        textAlignment = "topleft",

                        width = 180,
                        height = 20,
                        fontSize = 16,
                        multiline = true,
                        height = "auto",
                        minHeight = 40,

                        placeholderText = "Enter multiline text...",
                        characterLimit = 400,
                        editlag = 0.2,
                        edit = function(element)
                            outputLabel.text = "Text input changed to " .. element.text
                        end,

                        change = function(element)
                            outputLabel.text = "Text input submitted: " .. element.text
                        end,

                    },
                },

                ControlEntry {
                    name = "Slider",
                    control = gui.Slider {
                        halign = "center",
                        valign = "center",
                        minValue = 0,
                        maxValue = 100,
                        value = 50,
                        height = 20,
                        width = 180,
                        change = function(element)
                            outputLabel.text = "Slider changed to " .. element.value
                        end,
                    },
                },

                ControlEntry {
                    name = "Image Picker",
                    control = gui.IconEditor {
                        library = "Avatar",
                        width = 64,
                        height = 64,
                        halign = "center",
                        valign = "center",
                        change = function(element)
                            outputLabel.text = "Image selected: " .. element.value
                        end,
                    },
                },

                ControlEntry {
                    name = "Color Picker",
                    control = gui.ColorPicker {
                        value = "#ffffffff",
                        width = 32,
                        height = 32,
                        halign = "center",
                        valign = "center",
                        change = function(element)
                            outputLabel.text = "Color selected: " .. element.value.tostring
                        end,
                    },
                },

                ControlEntry {
                    name = "Progress Dice",
                    control = gui.ProgressDice({

                        progress = 0.4,
                        width = 256,
                        height = 256,


                    })
                },

                ControlEntry {
                    name = "Divider (layout=line)",
                    control = gui.Divider{
                        layout = "line",
                        width = "50%",
                    }
                },

                ControlEntry {
                    name = "Divider (layout=dot)",
                    control = gui.Divider{
                        layout = "dot",
                        width = "50%",
                    }
                },

                ControlEntry {
                    name = "Divider (layout=v)",
                    control = gui.Divider{
                        layout = "v",
                        width = "50%",
                    }
                },

                ControlEntry {
                    name = "Divider (layout=peak)",
                    control = gui.Divider{
                        layout = "peak",
                        width = "50%",
                    }
                },

                ControlEntry {
                    name = "Divider (layout=vdot)",
                    control = gui.Divider{
                        layout = "vdot",
                        width = "50%",
                    }
                },


            },

            outputLabel,
        }

        return resultPanel
    end,
}
