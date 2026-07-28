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

--Find the binding, if any, that a keystroke is already assigned to. The engine gives
--a keystroke to exactly one command, so binding a key that is already taken silently
--unbinds whatever had it -- callers use this to warn first.
--@param binds table: bindings to search, as returned by Keybinds.GetBindings().
--@param keystroke nil|string: the keystroke being assigned.
--@param ignoreCommand nil|string: the command being rebound. Re-pressing the key a
--       command already has is not a conflict, so it is excluded from the search.
--@return nil|table the bind entry that currently owns the keystroke.
function Keybinds.FindConflictingBind(binds, keystroke, ignoreCommand)
    if keystroke == nil then
        return nil
    end

    for _,bind in pairs(binds) do
        if bind.command ~= ignoreCommand and dmhub.GetCommandBinding(bind.command) == keystroke then
            return bind
        end
    end

    return nil
end

--Assign a keystroke to a command, first releasing the keystroke the command already
--had so a command never ends up answering to two keys.
--@param command string: the command to bind.
--@param keystroke nil|string: the keystroke to bind it to, or nil to just unbind.
function Keybinds.SetBinding(command, keystroke)
    local previousKeystroke = dmhub.GetCommandBinding(command)
    if previousKeystroke ~= nil then
        dmhub.SetCommandBinding(previousKeystroke, nil)
    end

    if keystroke ~= nil then
        dmhub.SetCommandBinding(keystroke, command)
    end
end

--Ask the user before taking a keystroke away from the command that already owns it.
--
--In a game this must go through gui.ModalMessage: the hud's modal layer is the only
--thing that reliably receives pointer input above the settings screen (which is itself
--hosted inside the hud). A panel merely AddChild'd into the hud tree draws fine but
--never gets clicks. The shortcuts settings are also reachable from the titlescreen,
--where there is no game hud at all, so fall back to an overlay on the settings screen's
--own sheet -- the same two-branch approach SettingsScreen.lua uses for its own messages.
--@param args table
--@field args.element Panel: a panel in the keybind UI; the titlescreen overlay is
--       parented to its root.
--@field args.keystroke string: the keystroke being taken over.
--@field args.conflictName string: name of the command that currently owns the keystroke.
--@field args.confirm function: called if the user chooses Continue.
--@field args.cancel nil|function: called if the user cancels.
function Keybinds.ShowRebindConflictDialog(args)
    local title = "Key Already Bound"
    local message = string.format("%s is already bound to %s.", args.keystroke, args.conflictName)
    local confirm = args.confirm
    local cancel = args.cancel

    if rawget(_G, "gamehud") ~= nil then
        gui.ModalMessage{
            title = title,
            message = message,
            options = {
                { text = "Cancel", execute = cancel },
                { text = "Continue", execute = confirm },
            },
        }
        return
    end

    local root = nil
    if args.element ~= nil and args.element.valid then
        root = args.element.root
    end
    if root == nil then
        return
    end

    local overlay
    overlay = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        floating = true,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#000000cc",
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,

        escape = function(element)
            element:DestroySelf()
            if cancel ~= nil then
                cancel()
            end
        end,

        gui.Panel{
            classes = {"framedPanel"},
            width = 520,
            height = 220,
            halign = "center",
            valign = "center",
            flow = "vertical",

            gui.Label{
                classes = {"modalTitle"},
                text = title,
            },

            gui.Label{
                classes = {"modalMessage"},
                width = "90%",
                height = "auto",
                textWrap = true,
                text = message,
            },

            gui.Panel{
                width = "90%",
                height = 40,
                halign = "center",
                valign = "bottom",
                vmargin = 16,
                flow = "horizontal",

                gui.Button{
                    classes = {"sizeL"},
                    halign = "left",
                    text = "Cancel",
                    click = function(element)
                        overlay:FireEvent("escape")
                    end,
                },

                gui.Button{
                    classes = {"sizeL"},
                    halign = "right",
                    text = "Continue",
                    click = function(element)
                        overlay:DestroySelf()
                        confirm()
                    end,
                },
            },
        },
    }

    root:AddChild(overlay)
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
    name = tr("Toggle Invisibility of Tokens and Objects"),
    section = "editor",
    dmonly = true,
}

Keybinds.Register{
    command = "toggleparallax",
    name = tr("Toggle parallax"),
    section = "camera",
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
        width = "100%-6",
        height = "auto",
        halign = "left",
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
        bgimage = true,
        bgcolor = "clear",
        border = {x1 = 0, x2 = 0, y1 = 0, y2 = 1},
        borderColor = "@border",
    },
    {
        selectors = {"bindLabel"},
        width = 400,
        height = "100%",
        fontSize = 18,
        color = "@fg",
        halign = "left",
        valign = "center",
        hmargin = 6,
        textAlignment = "left",
    },
    {
        selectors = {"shortcutLabel"},
        bgimage = true,
        bgcolor = "@bgAlt",
        color = "@fg",
        width = "100%-412",
        height = "100%",
        fontSize = 18,
        textAlignment = "center",
        border = {x1 = 0, x2 = 0, y1 = 0, y2 = 1},
        borderColor = "@border",
    },
    {
        selectors = {"shortcutLabel", "hover"},
        brightness = 1.5,
        transitionTime = 0.1,
    },
    {
        selectors = {"shortcutLabel", "press"},
        brightness = 0.7,
        transitionTime = 0.1,
    },
    {
        selectors = {"shortcutLabel", "active"},
        bgcolor = "@fgPending",
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
                                        styles = ThemeEngine.MergeTokens(g_KeybindStyles),
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
                                            local conflict = Keybinds.FindConflictingBind(binds, keystroke, bind.command)

                                            --stop listening for keys either way, so the row is not
                                            --still capturing while the prompt is up. The row keeps
                                            --showing its old binding until the rebind is confirmed.
                                            local root = element.root
                                            root:FireEventTree("clearKeybinds")

                                            if conflict ~= nil then
                                                Keybinds.ShowRebindConflictDialog{
                                                    element = element,
                                                    keystroke = keystroke,
                                                    conflictName = conflict.name or conflict.command,
                                                    confirm = function()
                                                        Keybinds.SetBinding(bind.command, keystroke)
                                                        if root.valid then
                                                            root:FireEventTree("clearKeybinds")
                                                        end
                                                    end,
                                                }
                                                return
                                            end

                                            Keybinds.SetBinding(bind.command, keystroke)
                                            root:FireEventTree("clearKeybinds")
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
                                        gui.Button{
                                            classes = {"deleteButton", "sizeS"},
                                            halign = "right",
                                            valign = "top",
                                            press = function(element)
                                                Keybinds.SetBinding(bind.command, nil)
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
                classes = {"sizeL", "bold"},
                width = "auto",
                height = "auto",
                fontSize = 24,
                bmargin = 0,
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

    children[#children+1] = gui.Button{
        classes = {"sizeL"},
        halign = "right",
        valign = "bottom",
        margin = 8,
        width = 220,
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
        styles = ThemeEngine.MergeTokens(g_KeybindStyles),

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
        styles = {ThemeEngine.GetStyles(), ThemeEngine.MergeTokens(g_KeybindStyles)},
        classes = {"framedPanel"},
        width = 600,
        height = 300,
        halign = "center",
        valign = "center",
        destroy = args.destroy,
        gui.Label{
            classes = {"sizeXl", "bold"},
            halign = "center",
            valign = "top",
            vmargin = 8,
            minFontSize = 10,
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
                            local conflict = Keybinds.FindConflictingBind(Keybinds.GetBindings(), keystroke, args.command)

                            --stop listening for keys either way, so the row is not still
                            --capturing while the prompt is up. The row keeps showing its
                            --old binding until the rebind is confirmed.
                            local root = element.root
                            root:FireEventTree("clearKeybinds")

                            if conflict ~= nil then
                                Keybinds.ShowRebindConflictDialog{
                                    element = element,
                                    keystroke = keystroke,
                                    conflictName = conflict.name or conflict.command,
                                    confirm = function()
                                        Keybinds.SetBinding(args.command, keystroke)
                                        if root.valid then
                                            root:FireEventTree("clearKeybinds")
                                        end
                                    end,
                                }
                                return
                            end

                            Keybinds.SetBinding(args.command, keystroke)
                            root:FireEventTree("clearKeybinds")
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
                        gui.Button{
                            classes = {"deleteButton", "sizeS"},
                            halign = "right",
                            valign = "top",
                            press = function(element)
                                Keybinds.SetBinding(args.command, nil)
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