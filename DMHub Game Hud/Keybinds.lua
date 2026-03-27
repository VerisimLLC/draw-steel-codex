local mod = dmhub.GetModLoading()

RegisterGameType("Keybinds")

Keybinds.sections = {}
function Keybinds.RegisterSection(args)
    local targetIndex = #Keybinds.sections+1
    for i,entry in ipairs(Keybinds.sections) do
        if entry.key == args.key then
            targetIndex = i
            break
        end
    end

    Keybinds.sections[targetIndex] = args
end

Keybinds.RegisterSection{
    key = "camera",
    name = tr("Camera"),
}
Keybinds.RegisterSection{
    key = "gameplay",
    name = tr("Gameplay"),
}
Keybinds.RegisterSection{
    key = "editor",
    name = tr("Editor"),
}
Keybinds.RegisterSection{
    key = "commands",
    name = tr("Actions"),
}
Keybinds.RegisterSection{
    key = "interface",
    name = tr("User Interface"),
}
Keybinds.RegisterSection{
    key = "system",
    name = tr("System"),
}



Keybinds.binds = {}

function Keybinds.Register(args)
    Keybinds.binds[args.command] = args
end

function Keybinds.GetBindings()
    local result = DeepCopy(Keybinds.binds)

    local takenNames = {}
    for key,bind in pairs(result) do
        takenNames[string.lower(bind.name)] = true
    end

    local launchableItems = LaunchablePanel.GetMenuItems()
    for _,item in ipairs(launchableItems) do
        local name = item.name or item.text
        local lcname = string.lower(name)
        if not takenNames[lcname] then
            takenNames[lcname] = true
            result[#result+1] = {
                command = string.format("togglepanel %s", lcname),
                name = name,
                section = "commands",
            }
        end
    end

    local dockableItems = DockablePanel.GetMenuItems(true)
    for _,item in ipairs(dockableItems) do
        local name = item.name or item.text
        local lcname = string.lower(name)
        if not takenNames[lcname] then
            takenNames[lcname] = true
            result[#result+1] = {
                command = string.format("togglepanel %s", lcname),
                name = name,
                section = "interface",
            }
        end
    end

    return result
end

function Keybinds.GetCurrentBinding(binds, keystroke)
    for k,bind in pairs(binds) do
        if dmhub.GetCommandBinding(bind.command) == keystroke then
            return k
        end
    end

    return nil
end

for key,bind in pairs(dmhub.GetBuiltinBindings()) do
    Keybinds.Register(bind)
end

Keybinds.Register{
    command = "ping",
    name = tr("Ping"),
    section = "gameplay",
}

Keybinds.Register{
    command = "togglefreeze",
    name = tr("Freeze Game"),
    dmonly = true,
    section = "gameplay",
}

Keybinds.Register{
    command = "synccamera",
    name = tr("Ping and Summon Camera"),
    dmonly = true,
    section = "gameplay",
}

Keybinds.Register{
    command = "next",
    name = tr("Next Character"),
    section = "gameplay",
}

Keybinds.Register{
    command = "copy",
    name = tr("Copy"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "cut",
    name = tr("Cut"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "paste",
    name = tr("Paste"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "undo",
    name = tr("Undo"),
    section = "editor",
}

Keybinds.Register{
    command = "redo",
    name = tr("Redo"),
    section = "editor",
}

Keybinds.Register{
    command = "find",
    name = tr("Find"),
    section = "misc",
}

Keybinds.Register{
    command = "decreasebrush",
    name = tr("Decrease Brush Size"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "increasebrush",
    name = tr("Increase Brush Size"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "rotateobject -90",
    name = tr("Rotate Object Right"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "rotateobject 90",
    name = tr("Rotate Object Left"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "sheet",
    name = tr("Character Sheet"),
    section = "gameplay",
}

Keybinds.Register{
    command = "emoji",
    name = tr("Emotes"),
    section = "gameplay",
}

Keybinds.Register{
    command = "spells",
    name = tr("Spells"),
    section = "gameplay",
}

Keybinds.Register{
    command = "inventory",
    name = tr("Inventory"),
    section = "gameplay",
}

Keybinds.Register{
    command = "tokenflip",
    name = tr("Flip Token"),
    section = "gameplay",
}

Keybinds.Register{
    command = "togglevisibility",
    name = tr("Toggle Visibility of Tokens and Objects"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "randobj; resetobj; randrot; randscale",
    name = tr("Randomize Object"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "objectstotop",
    name = tr("Move Objects to Top"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "objectstobottom",
    name = tr("Move Objects to Bottom"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "nextobj",
    name = tr("Next Object in Palette"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "prevobj",
    name = tr("Previous Object in Palette"),
    section = "editor",
    dmonly = true,
}


Keybinds.Register{
    command = "tokenmove -1 0",
    name = tr("Move Token Left"),
    section = "gameplay",
}

Keybinds.Register{
    command = "tokenmove 1 0",
    name = tr("Move Token Right"),
    section = "gameplay",
}

Keybinds.Register{
    command = "tokenmove 0 1",
    name = tr("Move Token Up"),
    section = "gameplay",
}

Keybinds.Register{
    command = "tokenmove 0 -1",
    name = tr("Move Token Down"),
    section = "gameplay",
}

Keybinds.Register{
    command = "tokenmove -1 -1",
    name = tr("Move Token Diagonal Down-Left"),
    section = "gameplay",
}

Keybinds.Register{
    command = "tokenmove 1 -1",
    name = tr("Move Token Diagonal Down-Right"),
    section = "gameplay",
}

Keybinds.Register{
    command = "tokenmove -1 1",
    name = tr("Move Token Diagonal Up-Left"),
    section = "gameplay",
}

Keybinds.Register{
    command = "tokenmove 1 1",
    name = tr("Move Token Diagonal Up-Right"),
    section = "gameplay",
}



Keybinds.Register{
    command = "flyup",
    name = tr("Fly Token Up"),
    section = "gameplay",
}

Keybinds.Register{
    command = "flydown",
    name = tr("Fly Token Down"),
    section = "gameplay",
}


Keybinds.Register{
    command = "center",
    name = tr("Center on Current Token"),
    section = "camera",
}

Keybinds.Register{
    command = "zoomin",
    name = tr("Zoom In"),
    section = "camera",
}

Keybinds.Register{
    command = "zoomout",
    name = tr("Zoom Out"),
    section = "camera",
}

Keybinds.Register{
    command = "tokenvar -1",
    name = tr("Previous Token Variation"),
    section = "gameplay",
}

Keybinds.Register{
    command = "tokenvar 1",
    name = tr("Next Token Variation"),
    section = "gameplay",
}

Keybinds.Register{
    command = "light",
    name = tr("Toggle Light"),
    section = "gameplay",
}

Keybinds.Register{
    command = "toggle gmbroadcastmouse",
    name = tr("Toggle Broadcast Director Mouse Cursor"),
    section = "system",
}

Keybinds.Register{
    command = "console",
    name = tr("Debug Console"),
    section = "system",
}


local g_KeybindStyles = {
    {
        selectors = {"sectionPanel"},
        flow = "vertical",
        width = "100%",
        height = "auto",
    },
    {
        selectors = {"sectionDivider"},
        vmargin = 24,
        width = "100%",
        height = 1,
    },
    {
        selectors = {"bindPanel"},
        flow = "horizontal",
        width = "100%",
        height = 40,
        bgimage = "panels/square.png",
        bgcolor = "clear",
        border = {x1 = 0, x2 = 0, y1 = 0, y2 = 1},
        borderColor = "#ffffff77"
    },
    {
        selectors = {"sectionTitle"},
        width = "auto",
        height = "auto",
        fontSize = 32,
        halign = "left",
        hmargin = 6,
        color = Styles.textColor,
    },
    {
        selectors = {"bindLabel"},
        width = 400,
        height = "100%",
        fontSize = 18,
        color = Styles.textColor,
        halign = "left",
        valign = "center",
        hmargin = 6,
        textAlignment = "left",
    },
    {
        selectors = {"shortcutLabel"},
        bgimage = "panels/square.png",
        bgcolor = "#ffffff22",
        width = "100%-412",
        height = "100%",
        fontSize = 18,
        textAlignment = "center",
        color = Styles.textColor,
    },
    {
        selectors = {"shortcutLabel", "hover"},
        bgcolor = "#ffffff44",
        transitionTime = 0.1,
    },
    {
        selectors = {"shortcutLabel", "press"},
        bgcolor = "#ffffff77",
        transitionTime = 0.1,
    },
    {
        selectors = {"shortcutLabel", "active"},
        bgcolor = "#aaaaff99",
        transitionTime = 0.1,
    },
}


CreateKeybindsSettingsPanel = function()
    local resultPanel

    printf("KEYBINDS::")

    local binds = Keybinds.GetBindings()
    local children = {}

    local sections = Keybinds.sections

    for _,section in ipairs(sections) do
        local sectionChildren = {}

        for key,bind in pairs(binds) do
            if bind.section == section.key and ((not section.dmonly) or dmhub.isDM) then
                local bindingText = dmhub.GetCommandBinding(bind.command)
                if (not section.hideUnlessBound) or bindingText then
                    local createfn
                    createfn = function(element)

                        return gui.Panel{
                            classes = {"bindPanel"},
                            data = {
                                ord = bind.ord or bind.name,
                            },

                            search = function(element, text, results)
                                results[#results+1] = {
                                    id = bind.name,
                                    create = function() return gui.Panel{
                                        width = "auto",
                                        height = "auto",
                                        styles = g_KeybindStyles,
                                        children = {createfn()},
                                    } end,
                                    shown = string.find(string.lower(bind.name), string.lower(text)),
                                }
                            end,

                            gui.Label{
                                classes = {"bindLabel"},
                                text = bind.name,
                            },
                            gui.Label{
                                classes = {"shortcutLabel"},
                                text = bindingText,

                                process = function(element)
                                    if element:HasClass("active") then
                                        local keystroke = dmhub.DetectBindableKeystroke()
                                        if keystroke ~= nil then
                                            print("Bindable:: Got", keystroke)
                                            --local current = Keybinds.GetCurrentBinding(keystroke)

                                            local previousKeystroke = dmhub.GetCommandBinding(bind.command)
                                            if previousKeystroke ~= nil then
                                                dmhub.SetCommandBinding(previousKeystroke, nil)
                                            end

                                            dmhub.SetCommandBinding(keystroke, bind.command)
                                            element.root:FireEventTree("clearKeybinds")
                                            return
                                        end
                                        element:ScheduleEvent("process", 0.01)
                                    end
                                end,
                                escape = function(element)
                                    element.root:FireEventTree("clearKeybinds")
                                end,
                                clearKeybinds = function(element)
                                    element:SetClass("active", false)
                                    element.text = dmhub.GetCommandBinding(bind.command)
                                    element.captureEscape = false
                                    element.children = {}
                                end,
                                click = function(element)
                                    element.root:FireEventTree("clearKeybinds")
                                    element:SetClass("active", true)
                                    element.text = "Press key..."
                                    element.captureEscape = true
                                    element.children = {
                                        gui.DeleteItemButton{
                                            width = 16,
                                            height = 16,
                                            halign = "right",
                                            valign = "top",
                                            press = function(element)
                                                local previousKeystroke = dmhub.GetCommandBinding(bind.command)
                                                if previousKeystroke ~= nil then
                                                    dmhub.SetCommandBinding(previousKeystroke, nil)
                                                end

                                                element.root:FireEventTree("clearKeybinds")
                                            end,
                                        }
                                    }
                                    element:FireEvent("process")
                                end,

                            },
                        }
                    end

                    sectionChildren[#sectionChildren+1] = createfn()
                end
            end
        end

        if #sectionChildren > 0 then
            table.sort(sectionChildren, function(a,b) return a.data.ord < b.data.ord end)
            table.insert(sectionChildren, 1, gui.Label{
                classes = {"sectionTitle"},
                text = section.name,
            })

            if #children > 0 then
                children[#children+1] = gui.Panel{
                    classes = {"sectionDivider"}
                }
            end

            children[#children+1] = gui.Panel{
                classes = {"sectionPanel"},
                children = sectionChildren,
            }

        end
    end

    children[#children+1] = gui.PrettyButton{
        halign = "right",
        valign = "bottom",
        margin = 8,
        width = 220,
        height = 30,
        fontSize = 22,
        text = "Reset to Defaults",
        click = function(element)
            dmhub.ResetKeybindings()
            resultPanel:FireEventTree("clearKeybinds")
        end,
    }

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        styles = g_KeybindStyles,

        children = children,
    }

    return resultPanel
end

--shows a popup which allows editing of a specific keybind.
--@param args table: Configuration options for the popup.
--@field args.command string: the command being bound.
--@field args.name string: the name of the command being bound.
function Keybinds.ShowBindPopup(args)
    local resultPanel

    resultPanel = gui.Panel{
        styles = {Styles.Panel, g_KeybindStyles},
        classes = {"framedPanel"},
        width = 600,
        height = 300,
        halign = "center",
        valign = "center",
        destroy = args.destroy,
        gui.Label{
            halign = "center",
            valign = "top",
            vmargin = 8,
            fontSize = 24,
            minFontSize = 10,
            bold = true,
            maxWidth = 500,
            width = "auto",
            height = "auto",
            text = string.format("Binding: %s", args.name),
        },

        gui.Panel{
            classes = {"bindPanel"},
            width = 500,
            halign = "center",
            valign = "center",
            gui.Label{
                classes = {"bindLabel"},
                width = 300,
                text = args.name,
            },
            gui.Label{
                classes = {"shortcutLabel"},
                width = 160,
                text = dmhub.GetCommandBinding(args.command),

                process = function(element)
                    if element:HasClass("active") then
                        local keystroke = dmhub.DetectBindableKeystroke()
                        if keystroke ~= nil then
                            --local current = Keybinds.GetCurrentBinding(keystroke)

                            local previousKeystroke = dmhub.GetCommandBinding(args.command)
                            if previousKeystroke ~= nil then
                                dmhub.SetCommandBinding(previousKeystroke, nil)
                            end

                            dmhub.SetCommandBinding(keystroke, args.command)
                            element.root:FireEventTree("clearKeybinds")
                            return
                        end
                        element:ScheduleEvent("process", 0.01)
                    end
                end,
                escape = function(element)
                    element.root:FireEventTree("clearKeybinds")
                end,
                clearKeybinds = function(element)
                    element:SetClass("active", false)
                    element.text = dmhub.GetCommandBinding(args.command)
                    element.captureEscape = false
                    element.children = {}
                end,
                click = function(element)
                    element.root:FireEventTree("clearKeybinds")
                    element:SetClass("active", true)
                    element.text = "Press key..."
                    element.captureEscape = true
                    element.children = {
                        gui.DeleteItemButton{
                            width = 16,
                            height = 16,
                            halign = "right",
                            valign = "top",
                            press = function(element)
                                local previousKeystroke = dmhub.GetCommandBinding(args.command)
                                if previousKeystroke ~= nil then
                                    dmhub.SetCommandBinding(previousKeystroke, nil)
                                end

                                element.root:FireEventTree("clearKeybinds")
                            end,
                        }
                    }
                    element:FireEvent("process")
                end,


            },
        },


    }

    return resultPanel
end