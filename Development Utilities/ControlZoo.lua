local mod = dmhub.GetModLoading()

local g_formStyles = {
    gui.Style{
        classes = {"formPanel"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        vmargin = 8,
    },
    gui.Style{
        classes = {"formLabel"},
        width = "auto",
        minWidth = 160,
        fontSize = 18,
    },
    gui.Style{
        classes = {"controlArea"},
        width = "70%",
        halign = "right",
        valign = "center",
        height = "auto",
        flow = "vertical",
    },
}

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
            local labelChildren = {}
            labelChildren[1] = gui.Label {
                classes = { "formLabel" },
                text = args.name,
            }
            if args.snippet then
                labelChildren[2] = gui.Label {
                    text = "[copy]",
                    fontSize = 11,
                    color = "#6688aa",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    hmargin = 4,
                    click = function(element)
                        dmhub.CopyToClipboard(args.snippet)
                        gui.Tooltip("Copied to clipboard")(element)
                    end,
                    linger = gui.Tooltip("Copy example code"),
                }
            end
            return gui.Panel {
                classes = { "formPanel" },
                gui.Panel {
                    flow = "horizontal",
                    width = "auto",
                    minWidth = 160,
                    height = "auto",
                    valign = "top",
                    tmargin = 4,
                    children = labelChildren,
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

                styles = g_formStyles,

                ControlEntry{
                    name = "Action Button",
                    snippet = [[gui.ActionButton{
    text = "MOVEMENT",
    available = true,
    selected = false,
}]],
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
                            tmargin = 6,
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

                ControlEntry{
                    name = "Selector Button",
                    snippet = [[gui.SelectorButton{
    text = "Devil",
    available = true,
    selected = false,
}]],
                    control = gui.Panel{
                        classes = {"selector-btn-test-controller"},
                        height = "auto",
                        vpad = 10,
                        halign = "center",
                        flow = "vertical",
                        setAvailable = function(element, isAvailable)
                            local selectorButton = element:Get("test-selector-button")
                            if selectorButton then
                                selectorButton:FireEvent("setAvailable", isAvailable)
                            end
                        end,
                        setSelected = function(element, isSelected)
                            local selectorButton = element:Get("test-selector-button")
                            if selectorButton then
                                selectorButton:FireEvent("setSelected", isSelected)
                            end
                        end,
                        gui.SelectorButton{
                            id = "test-selector-button",
                            text = "Devil",
                            available = true,
                            selected = false,
                        },
                        gui.Check{
                            tmargin = 6,
                            text = "Selected",
                            value = false,
                            placement = "left",
                            change = function(element)
                                local controller = element:FindParentWithClass("selector-btn-test-controller")
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
                                local controller = element:FindParentWithClass("selector-btn-test-controller")
                                if controller then
                                    controller:FireEvent("setAvailable", element.value)
                                end
                            end
                        }
                    }
                },

                ControlEntry {
                    name = "Beveled panel",
                    snippet = [[gui.Panel{
    width = 100,
    height = 100,
    bgimage = true,
    bgcolor = "black",
    borderColor = "white",
    borderWidth = 2,
    cornerRadius = 10,
    beveledcorners = true,
}]],
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
                    snippet = [[gui.Button{
    text = "Click Me",
    click = function() end,
    linger = gui.Tooltip("This is a button"),
}]],
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
                    snippet = [[gui.Button{
    text = "Click me",
    width = 120,
    height = 36,
    fontSize = 20,
    cornerRadius = 8,
    beveledcorners = true,
    borderColor = Styles.Cream03,
}]],
                    control = gui.Button{
                        text = "Click me, too",
                        halign = "center",
                        valign = "center",
                        width = 120,
                        height = 36,
                        fontSize = 20,
                        cornerRadius = 8,
                        beveledcorners = true,
                        borderColor = Styles.Cream03,
                        
                    }
                },

                ControlEntry {
                    name = "Delete Button",
                    snippet = [[gui.DeleteItemButton{
    click = function() end,
}]],
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
                    snippet = [[gui.Dropdown{
    options = {
        {id = "option1", text = "Option 1"},
        {id = "option2", text = "Option 2"},
        {id = "option3", text = "Option 3"},
    },
    idChosen = "option1",
    change = function(element)
        -- element.idChosen has the selected id
    end,
}]],
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
                    snippet = [[gui.Check{
    text = "Check me!",
    value = true,
    change = function(element)
        -- element.value is the boolean state
    end,
}]],
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
                    snippet = [[gui.Input{
    width = 180,
    height = 20,
    fontSize = 16,
    placeholderText = "Enter text...",
    characterLimit = 80,
    editlag = 0.2,
    edit = function(element)
        -- fires while typing (after editlag delay)
    end,
    change = function(element)
        -- fires on submit (Enter/blur)
    end,
}]],
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
                    snippet = [[gui.Input{
    width = 180,
    height = "auto",
    minHeight = 40,
    fontSize = 16,
    multiline = true,
    textAlignment = "topleft",
    placeholderText = "Enter multiline text...",
    characterLimit = 400,
    editlag = 0.2,
    edit = function(element) end,
    change = function(element) end,
}]],
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
                    snippet = [[gui.Slider{
    minValue = 0,
    maxValue = 100,
    value = 50,
    height = 20,
    width = 180,
    change = function(element)
        -- element.value has the current value
    end,
}]],
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
                    snippet = [[gui.IconEditor{
    library = "Avatar",
    width = 64,
    height = 64,
    change = function(element)
        -- element.value has the selected image path
    end,
}]],
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
                    snippet = [[gui.ColorPicker{
    value = "#ffffffff",
    width = 32,
    height = 32,
    change = function(element)
        -- element.value.tostring has the color hex
    end,
}]],
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
                    snippet = [[gui.ProgressDice{
    progress = 0.4,  -- 0.0 to 1.0
    width = 256,
    height = 256,
}]],
                    control = gui.ProgressDice({

                        progress = 0.4,
                        width = 256,
                        height = 256,


                    })
                },

                ControlEntry {
                    name = "Divider (layout=line)",
                    snippet = [[gui.Divider{layout = "line", width = "50%"}]],
                    control = gui.Divider{
                        layout = "line",
                        width = "50%",
                    }
                },

                ControlEntry {
                    name = "Divider (layout=dot)",
                    snippet = [[gui.Divider{layout = "dot", width = "50%"}]],
                    control = gui.Divider{
                        layout = "dot",
                        width = "50%",
                    }
                },

                ControlEntry {
                    name = "Divider (layout=v)",
                    snippet = [[gui.Divider{layout = "v", width = "50%"}]],
                    control = gui.Divider{
                        layout = "v",
                        width = "50%",
                    }
                },

                ControlEntry {
                    name = "Divider (layout=peak)",
                    snippet = [[gui.Divider{layout = "peak", width = "50%"}]],
                    control = gui.Divider{
                        layout = "peak",
                        width = "50%",
                    }
                },

                ControlEntry {
                    name = "Divider (layout=vdot)",
                    snippet = [[gui.Divider{layout = "vdot", width = "50%"}]],
                    control = gui.Divider{
                        layout = "vdot",
                        width = "50%",
                    }
                },

                ControlEntry{
                    name = "Dynamic List",
                    snippet = [==[gui.Panel{
    flow = "vertical",
    vscroll = true,
    create = function(element)
        local children = {}
        -- Replace "tableName" below with your actual table name
        for key, obj in unhidden_pairs(dmhub.GetTable("tableName")) do
            children[#children+1] = gui.Label{
                text = obj.name,
                click = function(el) --[[ handle click ]] end,
            }
        end
        element.children = children
    end,
}]==],
                    control = gui.Panel{
                        height = 160,
                        flow = "vertical",
                        vscroll = true,
                        create = function(element)
                            -- Simulate data-driven list (in real code: dmhub.GetTable())
                            local items = {"Warrior", "Mage", "Rogue", "Cleric", "Ranger",
                                           "Bard", "Paladin", "Monk", "Druid", "Sorcerer"}
                            local children = {}
                            for i, name in ipairs(items) do
                                children[#children+1] = gui.Label{
                                    text = string.format("%d. %s", i, name),
                                    fontSize = 14,
                                    width = "100%",
                                    height = 24,
                                    hmargin = 8,
                                    -- cond() is a global ternary from DMHub Utils
                                    bgimage = cond(i % 2 == 0, "panels/square.png", nil),
                                    bgcolor = cond(i % 2 == 0, "#ffffff10", nil),
                                    click = function(el)
                                        outputLabel.text = "Selected: " .. name
                                    end,
                                }
                            end
                            element.children = children
                        end,
                    },
                },


                ControlEntry{
                    name = "Tab Navigation",
                    snippet = [[gui.Panel{
    styles = {
        {selectors = {"tab"}, bgimage = "panels/square.png", bgcolor = "#444444", height = 32},
        {selectors = {"tab", "selected"}, bgcolor = "#886644", brightness = 1.5},
        {selectors = {"tabContent"}, collapsed = 1},
        {selectors = {"tabContent", "visible"}, collapsed = 0},
    },
    -- Tab bar
    gui.Panel{flow = "horizontal",
        gui.Label{classes = {"tab", "selected"}, text = "Tab 1", data = {tabId = "t1"},
            press = function(element)
                for _,child in ipairs(element.parent.children) do
                    child:SetClass("selected", element == child)
                end
                for _,child in ipairs(element.parent.parent.children) do
                    if child:HasClass("tabContent") then
                        child:SetClass("visible", child.data and child.data.tabId == element.data.tabId)
                    end
                end
            end,
        },
    },
    -- Content panels
    gui.Panel{classes = {"tabContent", "visible"}, data = {tabId = "t1"}, -- content here},
}]],
                    control = gui.Panel{
                        height = 140,
                        flow = "vertical",
                        styles = {
                            gui.Style{
                                classes = {"tab"},
                                bgimage = "panels/square.png",
                                bgcolor = Styles.RichBlack04,
                                width = "auto",
                                minWidth = 80,
                                height = 32,
                                fontSize = 14,
                                hmargin = 2,
                                cornerRadius = 6,
                                textAlignment = "center",
                            },
                            gui.Style{
                                classes = {"tab", "selected"},
                                bgcolor = "#886644",
                                brightness = 1.5,
                            },
                            gui.Style{
                                classes = {"tab", "hover"},
                                brightness = 1.3,
                            },
                            gui.Style{
                                classes = {"tabContent"},
                                width = "100%",
                                height = "100%-40",
                                valign = "bottom",
                                collapsed = 1,
                            },
                            gui.Style{
                                classes = {"tabContent", "visible"},
                                collapsed = 0,
                            },
                        },
                        gui.Panel{
                            flow = "horizontal",
                            width = "100%",
                            height = 36,
                            valign = "top",
                            halign = "center",
                            gui.Label{
                                classes = {"tab", "selected"},
                                text = "Stats",
                                data = {tabId = "stats"},
                                press = function(element)
                                    for _,child in ipairs(element.parent.children) do
                                        child:SetClass("selected", element == child)
                                    end
                                    local contentParent = element.parent.parent
                                    for _,child in ipairs(contentParent.children) do
                                        if child:HasClass("tabContent") then
                                            child:SetClass("visible", child.data ~= nil and child.data.tabId == element.data.tabId)
                                        end
                                    end
                                    outputLabel.text = "Tab: " .. element.data.tabId
                                end,
                            },
                            gui.Label{
                                classes = {"tab"},
                                text = "Skills",
                                data = {tabId = "skills"},
                                press = function(element)
                                    for _,child in ipairs(element.parent.children) do
                                        child:SetClass("selected", element == child)
                                    end
                                    local contentParent = element.parent.parent
                                    for _,child in ipairs(contentParent.children) do
                                        if child:HasClass("tabContent") then
                                            child:SetClass("visible", child.data ~= nil and child.data.tabId == element.data.tabId)
                                        end
                                    end
                                    outputLabel.text = "Tab: " .. element.data.tabId
                                end,
                            },
                            gui.Label{
                                classes = {"tab"},
                                text = "Items",
                                data = {tabId = "items"},
                                press = function(element)
                                    for _,child in ipairs(element.parent.children) do
                                        child:SetClass("selected", element == child)
                                    end
                                    local contentParent = element.parent.parent
                                    for _,child in ipairs(contentParent.children) do
                                        if child:HasClass("tabContent") then
                                            child:SetClass("visible", child.data ~= nil and child.data.tabId == element.data.tabId)
                                        end
                                    end
                                    outputLabel.text = "Tab: " .. element.data.tabId
                                end,
                            },
                        },
                        gui.Panel{
                            classes = {"tabContent", "visible"},
                            data = {tabId = "stats"},
                            gui.Label{text = "STR 10  DEX 14  CON 12", fontSize = 14, halign = "center"},
                        },
                        gui.Panel{
                            classes = {"tabContent"},
                            data = {tabId = "skills"},
                            gui.Label{text = "Athletics +3, Stealth +5", fontSize = 14, halign = "center"},
                        },
                        gui.Panel{
                            classes = {"tabContent"},
                            data = {tabId = "items"},
                            gui.Label{text = "Sword, Shield, Potion x3", fontSize = 14, halign = "center"},
                        },
                    },
                },


                ControlEntry{
                    name = "Floating Edge Tab",
                    snippet = [[-- Floating tab on left edge of parent panel (Timeline pattern)
gui.Panel{
    x = -32,
    floating = true,
    valign = "top",
    halign = "left",
    height = 166 * 0.8,
    width = 33 * 0.8,
    bgimage = ActivatedAbility.TabBGImage(),
    bgcolor = "white",
    gui.Label{
        color = "black",
        width = "auto", height = "auto",
        fontSize = 22, bold = true,
        text = "Results",
        y = -18,
        rotate = 90,
        halign = "center", valign = "center",
    },
}
-- Use class selectors + collapsed = 1 to show/hide:
-- styles = {{selectors = {"tab", "~active"}, collapsed = 1}}]],
                    control = gui.Panel{
                        width = "100%",
                        height = 280,
                        lmargin = 40,
                        bgimage = "panels/square.png",
                        bgcolor = Styles.RichBlack03,
                        cornerRadius = 8,

                        -- Floating tab on the left edge (Timeline pattern)
                        gui.Panel{
                            x = -39,
                            floating = true,
                            valign = "top",
                            halign = "left",
                            height = 166 * 0.8,
                            width = 33 * 0.8,
                            bgimage = ActivatedAbility.TabBGImage(),
                            bgcolor = "white",
                            click = function(element)
                                local content = element.parent:Get("edgeTabContent")
                                if content then
                                    local isVisible = not content:HasClass("hidden")
                                    content:SetClass("hidden", isVisible)
                                    outputLabel.text = cond(isVisible, "Tab hidden", "Tab shown")
                                end
                            end,
                            gui.Label{
                                color = "black",
                                width = "auto",
                                height = "auto",
                                fontSize = 22,
                                bold = true,
                                text = "Results",
                                y = -18,
                                rotate = 90,
                                halign = "center",
                                valign = "center",
                            },
                        },

                        -- Second floating tab below
                        gui.Panel{
                            x = -39,
                            floating = true,
                            valign = "top",
                            halign = "left",
                            y = 166 * 0.8 + 4,
                            height = 166 * 0.8,
                            width = 33 * 0.8,
                            bgimage = ActivatedAbility.TabBGImage(),
                            bgcolor = "white",
                            click = function(element)
                                outputLabel.text = "Triggers tab clicked"
                            end,
                            gui.Label{
                                color = "black",
                                width = "auto",
                                height = "auto",
                                fontSize = 22,
                                bold = true,
                                text = "Triggers",
                                y = -18,
                                rotate = 90,
                                halign = "center",
                                valign = "center",
                            },
                        },

                        -- Content area
                        gui.Panel{
                            id = "edgeTabContent",
                            styles = {
                                gui.Style{
                                    classes = {"hidden"},
                                    collapsed = 1,
                                },
                            },
                            width = "100%",
                            height = "100%",
                            flow = "vertical",
                            halign = "center",
                            valign = "center",
                            gui.Label{
                                text = "Content area",
                                fontSize = 14,
                                halign = "center",
                                valign = "center",
                            },
                            gui.Label{
                                text = "Click 'Results' tab to toggle",
                                fontSize = 11,
                                color = "#888888",
                                halign = "center",
                            },
                        },
                    },
                },


                ControlEntry{
                    name = "Search/Filter",
                    snippet = [[gui.Input{
    placeholderText = "Type to filter...",
    editlag = 0.2,
    edit = function(element)
        local listPanel = element.parent:Get("myList")
        local filterText = string.lower(element.text)
        local children = {}
        for _, item in ipairs(allItems) do
            if filterText == "" or string.find(string.lower(item), filterText, 1, true) then
                children[#children+1] = gui.Label{text = item}
            end
        end
        listPanel.children = children
    end,
}]],
                    control = gui.Panel{
                        height = 140,
                        flow = "vertical",
                        gui.Input{
                            width = "80%",
                            height = 20,
                            fontSize = 14,
                            halign = "center",
                            placeholderText = "Type to filter...",
                            editlag = 0.2,
                            edit = function(element)
                                local listPanel = element.parent:Get("filterList")
                                if listPanel == nil then return end

                                local allItems = {"Goblin", "Dragon", "Skeleton", "Orc",
                                                  "Troll", "Giant", "Vampire", "Lich"}
                                local filterText = string.lower(element.text)
                                local children = {}
                                for _, name in ipairs(allItems) do
                                    if filterText == "" or string.find(string.lower(name), filterText, 1, true) then
                                        children[#children+1] = gui.Label{
                                            text = name,
                                            fontSize = 14,
                                            width = "100%",
                                            height = 22,
                                            hmargin = 8,
                                        }
                                    end
                                end
                                if #children == 0 then
                                    children[#children+1] = gui.Label{
                                        text = "(no matches)",
                                        fontSize = 12,
                                        color = "#888888",
                                        halign = "center",
                                    }
                                end
                                listPanel.children = children
                                outputLabel.text = #children .. " results"
                            end,
                        },
                        gui.Panel{
                            id = "filterList",
                            width = "90%",
                            height = "100%-30",
                            halign = "center",
                            flow = "vertical",
                            vscroll = true,
                            create = function(element)
                                local items = {"Goblin", "Dragon", "Skeleton", "Orc",
                                               "Troll", "Giant", "Vampire", "Lich"}
                                local children = {}
                                for _, name in ipairs(items) do
                                    children[#children+1] = gui.Label{
                                        text = name,
                                        fontSize = 14,
                                        width = "100%",
                                        height = 22,
                                        hmargin = 8,
                                    }
                                end
                                element.children = children
                            end,
                        },
                    },
                },


                ControlEntry{
                    name = "Context Menu (right-click)",
                    snippet = [[create = function(element)
    element.events.rightClick = function(el)
        el.popup = gui.ContextMenu{
            entries = {
                {text = "Option A", click = function() el.popup = nil end},
                {text = "Option B", click = function() el.popup = nil end},
            }
        }
    end
end]],
                    control = gui.Panel{
                        width = 200,
                        height = 60,
                        bgimage = "panels/square.png",
                        bgcolor = "#333344",
                        cornerRadius = 8,
                        halign = "center",
                        valign = "center",
                        gui.Label{
                            text = "Right-click me",
                            fontSize = 14,
                            halign = "center",
                            valign = "center",
                        },
                        create = function(element)
                            element.events.rightClick = function(el)
                                el.popup = gui.ContextMenu{
                                    entries = {
                                        {
                                            text = "Option A",
                                            click = function()
                                                outputLabel.text = "Context: Option A"
                                                el.popup = nil
                                            end,
                                        },
                                        {
                                            text = "Option B",
                                            click = function()
                                                outputLabel.text = "Context: Option B"
                                                el.popup = nil
                                            end,
                                        },
                                        {
                                            text = "Delete (danger)",
                                            click = function()
                                                outputLabel.text = "Context: Delete clicked"
                                                el.popup = nil
                                            end,
                                        },
                                    }
                                }
                            end
                        end,
                    },
                },


                ControlEntry{
                    name = "Collapsible Section",
                    snippet = [[gui.Panel{
    styles = {{selectors = {"section-body", "collapsed"}, collapsed = 1}},
    -- Header (click to toggle)
    gui.Panel{
        click = function(element)
            local body = element.parent:Get("bodyId")
            if body then
                body:SetClass("collapsed", not body:HasClass("collapsed"))
            end
        end,
        gui.Label{text = "Section Header"},
    },
    -- Collapsible body
    gui.Panel{
        id = "bodyId",
        classes = {"section-body", "collapsed"},
        -- children here
    },
}]],
                    control = gui.Panel{
                        height = "auto",
                        minHeight = 30,
                        flow = "vertical",
                        width = "100%",
                        styles = {
                            gui.Style{
                                classes = {"section-body", "collapsed"},
                                collapsed = 1,
                            },
                        },
                        gui.Panel{
                            flow = "horizontal",
                            width = "100%",
                            height = 28,
                            bgimage = "panels/square.png",
                            bgcolor = Styles.RichBlack04,
                            cornerRadius = 4,
                            click = function(element)
                                local body = element.parent:Get("collapseBody")
                                if body then
                                    local isCollapsed = body:HasClass("collapsed")
                                    body:SetClass("collapsed", not isCollapsed)
                                    local arrow = element:Get("collapseArrow")
                                    if arrow then
                                        arrow.text = cond(isCollapsed, "v", ">")
                                    end
                                    outputLabel.text = cond(isCollapsed, "Expanded", "Collapsed")
                                end
                            end,
                            gui.Label{
                                id = "collapseArrow",
                                text = ">",
                                fontSize = 14,
                                width = 20,
                                hmargin = 6,
                            },
                            gui.Label{
                                text = "Section Header (click to toggle)",
                                fontSize = 14,
                            },
                        },
                        gui.Panel{
                            id = "collapseBody",
                            classes = {"section-body", "collapsed"},
                            width = "100%",
                            height = "auto",
                            flow = "vertical",
                            hmargin = 20,
                            vmargin = 4,
                            gui.Label{text = "Hidden content line 1", fontSize = 12},
                            gui.Label{text = "Hidden content line 2", fontSize = 12},
                            gui.Label{text = "Hidden content line 3", fontSize = 12},
                        },
                    },
                },


                ControlEntry{
                    name = "Styles & Classes",
                    snippet = [[gui.Panel{
    styles = {
        {selectors = {"myClass"}, bgcolor = "#333344", cornerRadius = 6},
        {selectors = {"myClass", "hover"}, brightness = 1.4},
        {selectors = {"myClass", "variant"}, bgcolor = "#664422", borderColor = "#bc9b7b"},
    },
    gui.Label{classes = {"myClass"}, text = "Normal"},
    gui.Label{classes = {"myClass", "variant"}, text = "Variant"},
}]],
                    control = gui.Panel{
                        height = "auto",
                        flow = "vertical",
                        halign = "center",
                        styles = {
                            gui.Style{
                                classes = {"card"},
                                bgimage = "panels/square.png",
                                bgcolor = "#333344",
                                cornerRadius = 6,
                                width = "auto",
                                minWidth = 100,
                                height = 36,
                                hmargin = 4,
                                fontSize = 14,
                                textAlignment = "center",
                            },
                            gui.Style{
                                classes = {"card", "hover"},
                                brightness = 1.4,
                            },
                            gui.Style{
                                classes = {"card", "highlight"},
                                bgcolor = "#664422",
                                borderColor = Styles.Cream03,
                                borderWidth = 1,
                            },
                        },
                        gui.Panel{
                            flow = "horizontal",
                            width = "100%",
                            height = 44,
                            halign = "center",
                            gui.Label{
                                classes = {"card"},
                                text = "Normal Card",
                                click = function(element)
                                    outputLabel.text = "Clicked normal card"
                                end,
                            },
                            gui.Label{
                                classes = {"card", "highlight"},
                                text = "Highlight Card",
                                click = function(element)
                                    outputLabel.text = "Clicked highlight card"
                                end,
                            },
                        },
                        gui.Label{
                            text = "Both cards share 'card' style; right one adds 'highlight' class",
                            fontSize = 11,
                            color = "#888888",
                            halign = "center",
                            vmargin = 4,
                        },
                    },
                },


                ControlEntry{
                    name = "Form Rows",
                    snippet = [[gui.Panel{
    styles = {
        {selectors = {"formRow"}, flow = "horizontal", width = "100%", height = 32},
        {selectors = {"formRowLabel"}, width = "35%", fontSize = 14, valign = "center"},
        {selectors = {"formRowControl"}, width = "60%", halign = "right", valign = "center"},
    },
    gui.Panel{classes = {"formRow"},
        gui.Label{classes = {"formRowLabel"}, text = "Field Name"},
        gui.Panel{classes = {"formRowControl"},
            gui.Input{placeholderText = "Value...", change = function(el) end},
        },
    },
}]],
                    control = gui.Panel{
                        height = "auto",
                        flow = "vertical",
                        width = "100%",
                        styles = {
                            gui.Style{
                                classes = {"formRow"},
                                flow = "horizontal",
                                width = "100%",
                                height = 32,
                                vmargin = 2,
                            },
                            gui.Style{
                                classes = {"formRowLabel"},
                                width = "35%",
                                fontSize = 14,
                                valign = "center",
                            },
                            gui.Style{
                                classes = {"formRowControl"},
                                width = "60%",
                                halign = "right",
                                valign = "center",
                            },
                        },
                        gui.Panel{
                            classes = {"formRow"},
                            gui.Label{classes = {"formRowLabel"}, text = "Name"},
                            gui.Panel{
                                classes = {"formRowControl"},
                                gui.Input{
                                    width = "100%",
                                    height = 20,
                                    fontSize = 14,
                                    placeholderText = "Enter name...",
                                    change = function(element)
                                        outputLabel.text = "Name: " .. element.text
                                    end,
                                },
                            },
                        },
                        gui.Panel{
                            classes = {"formRow"},
                            gui.Label{classes = {"formRowLabel"}, text = "Level"},
                            gui.Panel{
                                classes = {"formRowControl"},
                                gui.Dropdown{
                                    options = {
                                        {id = "1", text = "1"},
                                        {id = "2", text = "2"},
                                        {id = "3", text = "3"},
                                    },
                                    idChosen = "1",
                                    change = function(element)
                                        outputLabel.text = "Level: " .. element.idChosen
                                    end,
                                },
                            },
                        },
                        gui.Panel{
                            classes = {"formRow"},
                            gui.Label{classes = {"formRowLabel"}, text = "Active"},
                            gui.Panel{
                                classes = {"formRowControl"},
                                gui.Check{
                                    text = "",
                                    value = true,
                                    change = function(element)
                                        outputLabel.text = "Active: " .. tostring(element.value)
                                    end,
                                },
                            },
                        },
                    },
                },


                ControlEntry{
                    name = "Tooltip (linger)",
                    snippet = [[-- Static tooltip
linger = gui.Tooltip("Tooltip text"),

-- Dynamic tooltip
linger = function(element)
    local info = "Computed: " .. someValue
    gui.Tooltip(info)(element)
end]],
                    control = gui.Panel{
                        flow = "horizontal",
                        height = 50,
                        halign = "center",
                        gui.Panel{
                            width = 120,
                            height = 40,
                            bgimage = "panels/square.png",
                            bgcolor = "#334433",
                            cornerRadius = 8,
                            halign = "center",
                            valign = "center",
                            -- Standard pattern: gui.Tooltip(text)(element)
                            linger = gui.Tooltip("Simple text tooltip"),
                            gui.Label{
                                text = "Hover me",
                                fontSize = 14,
                                halign = "center",
                                valign = "center",
                            },
                        },
                        gui.Panel{
                            width = 120,
                            height = 40,
                            bgimage = "panels/square.png",
                            bgcolor = "#443333",
                            cornerRadius = 8,
                            halign = "center",
                            valign = "center",
                            hmargin = 8,
                            -- Dynamic tooltip: compute text in handler
                            linger = function(element)
                                local info = "Computed at " .. os.date("%H:%M:%S")
                                gui.Tooltip(info)(element)
                            end,
                            gui.Label{
                                text = "Dynamic tip",
                                fontSize = 14,
                                halign = "center",
                                valign = "center",
                            },
                        },
                    },
                },


                ControlEntry{
                    name = "Reactive Update (refreshGame)",
                    snippet = [[gui.Panel{
    monitorGame = mod:GetDocumentSnapshot("myDocId").path,
    refreshGame = function(element)
        local doc = mod:GetDocumentSnapshot("myDocId")
        -- update UI from doc.data
    end,
}]],
                    control = gui.Panel{
                        height = 100,
                        flow = "vertical",
                        width = "100%",

                        -- Explanation label
                        gui.Label{
                            text = "refreshGame fires when monitored data changes.",
                            fontSize = 11,
                            color = "#888888",
                            halign = "center",
                            height = "auto",
                        },
                        gui.Label{
                            text = "monitorGame = doc.path or table name string",
                            fontSize = 11,
                            color = "#888888",
                            halign = "center",
                            height = "auto",
                            vmargin = 2,
                        },

                        -- Code reference panel
                        gui.Panel{
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            bgimage = "panels/square.png",
                            bgcolor = "#222233",
                            cornerRadius = 6,
                            vmargin = 6,
                            flow = "vertical",
                            gui.Label{
                                text = "Pattern:",
                                fontSize = 12,
                                bold = true,
                                width = "100%",
                                height = "auto",
                                hmargin = 8,
                                vmargin = 4,
                            },
                            gui.Label{
                                text = "monitorGame = mod:GetDocumentSnapshot(id).path",
                                fontSize = 11,
                                color = "#aaccaa",
                                width = "100%",
                                height = "auto",
                                hmargin = 12,
                            },
                            gui.Label{
                                text = "refreshGame = function(element) ... end",
                                fontSize = 11,
                                color = "#aaccaa",
                                width = "100%",
                                height = "auto",
                                hmargin = 12,
                                vmargin = 4,
                            },
                        },

                        gui.Label{
                            text = "See ChatPanel.lua:876 for a live example",
                            fontSize = 11,
                            color = Styles.Grey02,
                            italics = true,
                            halign = "center",
                            height = "auto",
                        },
                    },
                },


            },

            outputLabel,
        }

        return resultPanel
    end,
}
