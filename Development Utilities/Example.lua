print("MONSTERS:: READING BESTIARY...")

for k,v in pairs(assets.monsters) do
    print("MONSTERS:: FOUND MONSTER", v.name, "with id", k)
end

print("MONSTERS:: BESTIARY READ COMPLETE.")

-- DMHub-compatible panel styling gallery.
-- F7: inspector, F8: swap inspector side, F6: copy selected panel report.

local linearSky = gui.Gradient{
    type = "linear",
    point_a = {x = 0, y = 0},
    point_b = {x = 1, y = 1},
    easing = "EaseInOutSine",
    stops = {
        {position = 0.00, color = "#4866E8FF"},
        {position = 0.48, color = "#704ACBFF"},
        {position = 1.00, color = "#D35A91FF"},
    },
}

local radialGlow = gui.Gradient{
    type = "radial",
    point_a = {x = 0.32, y = 0.28},
    point_b = {x = 0.92, y = 0.82},
    easing = "EaseOutQuad",
    stops = {
        {position = 0.00, color = "#8BF4D9FF"},
        {position = 0.28, color = "#2AA4BFFF"},
        {position = 0.72, color = "#153864FF"},
        {position = 1.00, color = "#0B172BFF"},
    },
}

local card = gui.Style{
    selectors = {"card"},
    bgimage = true,
    bgcolor = "#111827F4",
    borderWidth = 1,
    borderColor = "#34445FFF",
    cornerRadius = 16,
    pad = 14,
    margin = 7,
    flow = "vertical",
    borderBox = true,
}

local heading = gui.Style{
    selectors = {"heading"},
    height = 30,
    width = "100%",
    fontSize = 18,
    color = "#F6E7C9FF",
    textAlignment = "left",
    bold = true,
}

local caption = gui.Style{
    selectors = {"caption"},
    width = "100%",
    fontSize = 13,
    color = "#9AAAC3FF",
    textAlignment = "topLeft",
    textWrap = true,
}

local demoTile = gui.Style{
    selectors = {"demo-tile"},
    bgimage = true,
    bgcolor = "#172238FF",
    borderColor = "#4D6384FF",
    borderWidth = 1,
    cornerRadius = 10,
    margin = 5,
    borderBox = true,
}

local interactive = gui.Style{
    selectors = {"interactive"},
    bgimage = true,
    bgcolor = "#23324BFF",
    borderColor = "#60789CFF",
    borderWidth = 1,
    cornerRadius = 11,
    scale = 1,
    borderBox = true,
}

local interactiveHover = gui.Style{
    selectors = {"interactive", "hover"},
    transitionTime = 0.18,
    easing = "EaseOutCubic",
    bgcolor = "#2D817DFF",
    borderColor = "#9CF5E1FF",
    borderWidth = 3,
    scale = 1.035,
    brightness = 1.08,
}

local interactivePress = gui.Style{
    selectors = {"interactive", "press"},
    priority = 1,
    transitionTime = 0.08,
    easing = "EaseOutQuad",
    bgcolor = "#E19A4BFF",
    borderColor = "#FFE3B7FF",
    scale = 0.975,
}

-- Later equal-specificity rules win.
local tieFirst = gui.Style{selectors = {"tie"}, bgcolor = "#7B3349FF"}
local tieLast = gui.Style{selectors = {"tie"}, bgcolor = "#315B91FF"}
-- ID specificity (10) beats class specificity (1).
local idWins = gui.Style{selectors = {"#id-winner"}, bgcolor = "#713F98FF", borderColor = "#D8A9FFFF"}
-- Priority is the strongest tier: priority * 1000 + specificity.
local priorityWins = gui.Style{selectors = {"priority-winner"}, priority = 1, bgcolor = "#387B55FF", borderColor = "#98F2B5FF"}

local parentHoverChild = gui.Style{
    selectors = {"parent:hover", "parent-child"},
    transitionTime = 0.2,
    easing = "EaseOutQuad",
    bgcolor = "#D27843FF",
    borderColor = "#FFD2A8FF",
    translate = {x = 7, y = 0},
}

local inheritedTheme = gui.Style{
    selectors = {"ocean-theme", "inherited-label"},
    inherit_selectors = true,
    color = "#A8FFF0FF",
    bgcolor = "#174B5BFF",
    borderColor = "#62D8C7FF",
}

local mutedUnlessHover = gui.Style{
    selectors = {"~hover", "negative-demo"},
    transitionTime = 0.15,
    opacity = 0.54,
    saturation = 0.25,
}

local eventActive = gui.Style{
    selectors = {"event-active"},
    priority = 2,
    transitionTime = 0.18,
    easing = "EaseOutCubic",
    bgcolor = "#A84F76FF",
    borderColor = "#FFD0E4FF",
    brightness = 1.16,
}

local eventReceived = gui.Style{
    selectors = {"event-received"},
    priority = 2,
    transitionTime = 0.45,
    easing = "EaseOutQuad",
    bgcolor = "#2B8A70FF",
    borderColor = "#B4FFE9FF",
    brightness = 1.12,
}

local dragToken = gui.Style{
    selectors = {"drag-token"},
    bgimage = true,
    bgcolor = "#3A4E76FF",
    borderColor = "#91B8F5FF",
    borderWidth = 2,
    cornerRadius = 12,
}

local dragTokenMoving = gui.Style{
    selectors = {"drag-token", "dragging"},
    priority = 2,
    transitionTime = 0.12,
    easing = "EaseOutQuad",
    bgcolor = "#A95C86FF",
    borderColor = "#FFD3E8FF",
    scale = 1.06,
    opacity = 0.92,
}

local dropZone = gui.Style{
    selectors = {"drop-zone"},
    bgimage = true,
    bgcolor = "#172238FF",
    borderColor = "#405372FF",
    borderWidth = 1,
    cornerRadius = 10,
}

local availableDropZone = gui.Style{
    selectors = {"drop-zone", "drag-target"},
    transitionTime = 0.12,
    bgcolor = "#214C55FF",
    borderColor = "#65CDBAFF",
    borderWidth = 2,
}

local hoveredDropZone = gui.Style{
    selectors = {"drop-zone", "drag-target-hover"},
    priority = 2,
    transitionTime = 0.08,
    bgcolor = "#B7773FFF",
    borderColor = "#FFE0AFFF",
    borderWidth = 4,
    brightness = 1.1,
}

local successfulDropZone = gui.Style{
    selectors = {"drop-zone", "drop-success"},
    priority = 3,
    transitionTime = 0.5,
    easing = "EaseOutQuad",
    bgcolor = "#3FA46FFF",
    borderColor = "#C9FFDCFF",
    brightness = 1.22,
}

local inputSurface = gui.Style{
    selectors = {"input-field"},
    bgimage = true,
    bgcolor = "#111A2AFF",
    borderColor = "#43536FFF",
    borderWidth = 1,
    cornerRadius = 7,
    hpad = 9,
    vpad = 5,
    color = "#F2E9D8FF",
    fontSize = 15,
    textAlignment = "left",
    selectedColor = "#537CC0A0",
    scrollHandleColor = "#8FB8D8C0",
    borderBox = true,
}

local inputHover = gui.Style{
    selectors = {"input-field", "hover"},
    transitionTime = 0.12,
    borderColor = "#6E8EB9FF",
}

local inputFocus = gui.Style{
    selectors = {"input-field", "focus"},
    priority = 1,
    transitionTime = 0.12,
    borderColor = "#8FE3D2FF",
    borderWidth = 2,
    brightness = 1.08,
}

local inputStatus = gui.Style{
    selectors = {"input-status"},
    width = "100%-8",
    height = 22,
    fontSize = 12,
    color = "#8FA8C8FF",
    textAlignment = "left",
    textWrap = false,
}

local function title(text)
    return gui.Label{classes = {"heading"}, text = text}
end

local function captionLabel(text, height)
    return gui.Label{classes = {"caption"}, text = text, height = height or 42}
end

local function CreateExample()
return gui.Panel{
    id = "style-gallery",
    width = "100%-48",
    height = "100%-122",
    hmargin = 24,
    tmargin = 78,
    bmargin = 24,
    borderBox = true,
    pad = 12,
    flow = "vertical",
    bgimage = true,
    bgcolor = "#0B101AF6",
    borderColor = "#354663FF",
    borderWidth = 1,
    cornerRadius = 20,

    styles = {
        card, heading, caption, demoTile,
        interactive, interactiveHover, interactivePress,
        tieFirst, tieLast, idWins, priorityWins,
        parentHoverChild, inheritedTheme, mutedUnlessHover,
        eventActive, eventReceived,
        dragToken, dragTokenMoving, dropZone,
        availableDropZone, hoveredDropZone, successfulDropZone,
        inputSurface, inputHover, inputFocus, inputStatus,
    },

    gui.Panel{
        width = "100%",
        height = 68,
        flow = "horizontal",
        gui.Panel{
            width = 11,
            height = 48,
            bgimage = true,
            gradient = linearSky,
            cornerRadius = 6,
            vmargin = 5,
            rmargin = 14,
        },
        gui.Label{
            width = "58%",
            height = 58,
            text = "DMHUB STYLE SYSTEM",
            fontSize = 27,
            color = "#F9EDD8FF",
            uppercase = true,
            bold = true,
            textAlignment = "left",
        },
        gui.Label{
            width = "40%",
            height = 58,
            text = "Hover and press the examples  |  F7 inspect  |  F6 copy for AI",
            fontSize = 14,
            color = "#8295B2FF",
            textAlignment = "right",
        },
    },

    gui.Panel{
        id = "top-row",
        width = "100%",
        height = "29%",
        flow = "horizontal",

        gui.Panel{
            id = "gradient-card",
            classes = {"card"},
            width = "32%",
            height = "100%-4",
            title("GRADIENTS + COLOR PIPELINE"),
            captionLabel("Linear and radial gui.Gradient values are rendered inside ordinary square backgrounds.", 38),
            gui.Panel{
                width = "100%",
                height = 86,
                flow = "horizontal",
                gui.Panel{
                    id = "linear-gradient",
                    classes = {"demo-tile"},
                    width = "47%",
                    height = 76,
                    gradient = linearSky,
                    bgcolor = "#FFFFFFFF",
                    gui.Label{text = "LINEAR", width = "100%", height = "100%", fontSize = 14, bold = true, textAlignment = "center"},
                },
                gui.Panel{
                    id = "radial-gradient",
                    classes = {"demo-tile"},
                    width = "47%",
                    height = 76,
                    gradient = radialGlow,
                    bgcolor = "#FFFFFFFF",
                    gui.Label{text = "RADIAL", width = "100%", height = "100%", fontSize = 14, bold = true, textAlignment = "center"},
                },
            },
            gui.Panel{
                classes = {"demo-tile"},
                width = "100%-10",
                height = 48,
                bgcolor = "#B47456FF",
                saturation = 0.25,
                contrast = 1.35,
                gui.Label{text = "saturation .25  |  contrast 1.35", width = "100%", height = "100%", fontSize = 13, textAlignment = "center"},
            },
        },

        gui.Panel{
            id = "cascade-card",
            classes = {"card"},
            width = "32%",
            height = "100%-4",
            title("CASCADE + SPECIFICITY"),
            captionLabel("Later ties, ID specificity, then explicit priority. Each chip starts with the same base class.", 38),
            gui.Label{
                classes = {"demo-tile", "tie"},
                width = "100%-10", height = 34,
                text = "later equal rule wins  ->  blue", fontSize = 13, textAlignment = "center",
            },
            gui.Label{
                id = "id-winner", classes = {"demo-tile", "tie"},
                width = "100%-10", height = 34,
                text = "#id specificity wins  ->  violet", fontSize = 13, textAlignment = "center",
            },
            gui.Label{
                classes = {"demo-tile", "tie", "priority-winner"},
                width = "100%-10", height = 34,
                text = "priority = 1 wins  ->  green", fontSize = 13, textAlignment = "center",
            },
        },

        gui.Panel{
            id = "state-card",
            classes = {"card"},
            width = "32%",
            height = "100%-4",
            title("RUNTIME CLASSES"),
            captionLabel("Pointer events call Lua handlers. This label mutates its own text, data, and classes.", 38),
            gui.Label{
                id = "hover-target",
                classes = {"interactive"},
                width = "100%-10", height = 70, margin = 5,
                text = "CLICK ME", fontSize = 17, bold = true, textAlignment = "center",
                data = {clicks = 0},
                events = {
                    create = "reset",
                    reset = function(element)
                        element.data.clicks = 0
                        element.text = "CLICK ME"
                    end,
                    click = function(element)
                        element.data.clicks = element.data.clicks + 1
                        element.text = "CLICK EVENT x" .. element.data.clicks
                        element:AddClass("event-active")
                        element:ScheduleEvent("settle", 0.18)
                    end,
                    settle = function(element)
                        element:RemoveClass("event-active")
                    end,
                },
            },
            gui.Label{
                classes = {"interactive"},
                width = "100%-10", height = 56, margin = 5,
                text = "EVENT-ONLY DRAG", fontSize = 13, textAlignment = "center",
                draggable = true,
                dragMove = false,
                beginDrag = function(element)
                    element.text = "BEGIN DRAG"
                end,
                dragging = function(element)
                    local delta = element.dragDelta
                    element.text = string.format("DELTA %.0f, %.0f", delta.x, delta.y)
                end,
                drag = function(element)
                    element.text = "EVENT-ONLY DRAG"
                end,
            },
        },
    },

    gui.Panel{
        id = "bottom-row",
        width = "100%",
        height = "29%",
        flow = "horizontal",

        gui.Panel{
            id = "parent-card",
            classes = {"card"},
            width = "32%", height = "100%-4",
            title("DRAG + DROP TARGETS"),
            captionLabel("Drag the token onto a zone. Eligible targets and the winning priority target receive state classes.", 48),
            gui.Panel{
                id = "drag-stage",
                width = "100%-10", height = 118,
                gui.Label{
                    id = "drop-zone-a",
                    classes = {"drop-zone"},
                    dragTarget = true,
                    dragTargetPriority = 1,
                    x = 12, y = 62,
                    width = 128, height = 48,
                    text = "ZONE A | P1", fontSize = 12, textAlignment = "center",
                },
                gui.Label{
                    id = "drop-zone-b",
                    classes = {"drop-zone"},
                    dragTarget = true,
                    dragTargetPriority = 5,
                    x = 220, y = 62,
                    width = 128, height = 48,
                    text = "ZONE B | P5", fontSize = 12, textAlignment = "center",
                },
                gui.Label{
                    id = "drag-token",
                    classes = {"drag-token"},
                    draggable = true,
                    dragThreshold = 4,
                    dragBounds = {x1 = -138, y1 = -105, x2 = 98, y2 = 0},
                    x = 144, y = 5,
                    width = 108, height = 44,
                    text = "DRAG ME", bold = true, fontSize = 13, textAlignment = "center",
                    canDragOnto = function(element, target)
                        return target:HasClass("drop-zone")
                    end,
                    beginDrag = function(element)
                        element.text = "DRAGGING..."
                    end,
                    dragging = function(element, target)
                        if target ~= nil then
                            element.text = "OVER " .. target.id
                        else
                            element.text = "DRAGGING..."
                        end
                    end,
                    drag = function(element, target)
                        if target ~= nil then
                            element.text = "DROPPED: " .. target.id
                            target:PulseClass("drop-success")
                        else
                            element.text = "NO DROP TARGET"
                        end
                        element:ScheduleEvent("reset", 1.2)
                    end,
                    reset = function(element)
                        element.text = "DRAG ME"
                    end,
                },
            },
        },

        gui.Panel{
            id = "inherit-card",
            classes = {"card", "ocean-theme"},
            width = "32%", height = "100%-4",
            title("INHERITED SELECTORS"),
            captionLabel("inherit_selectors finds ocean-theme on an ancestor while still requiring inherited-label here.", 48),
            gui.Panel{
                width = "100%-10", height = 75, flow = "vertical",
                gui.Label{
                    classes = {"demo-tile", "inherited-label"},
                    width = "100%", height = 61,
                    text = "theme inherited through a container", fontSize = 14, bold = true, textAlignment = "center",
                },
            },
        },

        gui.Panel{
            id = "layout-card",
            classes = {"card"},
            width = "32%", height = "100%-4",
            title("FIRE EVENT TREE"),
            captionLabel("The button broadcasts a custom event through its parent. Descendants update themselves independently.", 48),
            gui.Label{
                id = "broadcast-button",
                classes = {"interactive"},
                width = "100%-10", height = 48, margin = 5,
                text = "BROADCAST CUSTOM EVENT", bold = true,
                fontSize = 13, textAlignment = "center",
                click = function(element)
                    local bus = element:Get("event-bus")
                    bus.data.serial = bus.data.serial + 1
                    bus:FireEventTree("broadcast", bus.data.serial)
                end,
            },
            gui.Panel{
                id = "event-bus",
                data = {serial = 0},
                width = "100%-10", height = 48, flow = "horizontal",
                gui.Label{
                    classes = {"demo-tile"}, width = "47%", height = 40,
                    text = "LISTENER A", fontSize = 12, textAlignment = "center",
                    broadcast = function(element, serial)
                        element.text = "A RECEIVED #" .. serial
                        element:PulseClass("event-received")
                    end,
                },
                gui.Label{
                    classes = {"demo-tile"}, width = "47%", height = 40,
                    text = "LISTENER B", fontSize = 12, textAlignment = "center",
                    events = {
                        broadcast = function(element, serial)
                            element.text = "B RECEIVED #" .. serial
                            element:PulseClass("event-received")
                        end,
                    },
                },
            },
        },
    },

    gui.Panel{
        id = "input-row",
        classes = {"card"},
        width = "100%-14",
        height = "32%",
        title("GUI.INPUT EDITOR + FOCUS + EVENTS"),
        gui.Panel{
            width = "100%",
            height = "100%-34",
            flow = "horizontal",

            gui.Panel{
                width = "33%", height = "100%", flow = "vertical",
                gui.Input{
                    id = "input-single",
                    classes = {"input-field"},
                    width = "100%-10", height = 34,
                    placeholderText = "Type and press Enter...",
                    characterLimit = 80,
                    editlag = 0.2,
                    edit = function(element)
                        element.parent:Get("input-single-status").text = "edit: " .. element.text
                    end,
                    change = function(element)
                        element.parent:Get("input-single-status").text = "change: " .. element.text
                    end,
                    submit = function(element)
                        element.parent:Get("input-single-status").text = "submit: " .. element.text
                    end,
                },
                gui.Label{id = "input-single-status", classes = {"input-status"}, text = "single: waiting for edit"},
                gui.Panel{
                    width = "100%-10", height = 38, flow = "horizontal",
                    gui.Input{
                        id = "input-password", classes = {"input-field"},
                        width = "48%", height = 32, rmargin = 6,
                        placeholderText = "Password", password = true,
                    },
                    gui.Input{
                        id = "input-numeric", classes = {"input-field"},
                        width = "48%", height = 32, text = "10", numeric = true,
                        placeholderText = "Ctrl+wheel",
                    },
                },
                captionLabel("Password masking | numeric Ctrl+wheel", 22),
                gui.Label{
                    id = "editable-label",
                    classes = {"caption"},
                    width = "100%-10", height = 34,
                    text = "Click to edit this gui.Label",
                    placeholderText = "Editable label",
                    characterLimit = 60,
                    editable = true,
                    change = function(element)
                        element.parent:Get("input-single-status").text = "label change: " .. element.text
                    end,
                },
            },

            gui.Panel{
                width = "34%", height = "100%", flow = "vertical",
                gui.Input{
                    id = "input-multiline",
                    classes = {"input-field"},
                    width = "100%-10", height = 82,
                    lineType = "MultiLineSubmit",
                    verticalScrollbar = true,
                    placeholderText = "Enter submits; Shift+Enter adds a line",
                    edit = function(element)
                        element.parent:Get("input-multiline-status").text = string.format(
                            "caret %d anchor %d", element.caretPosition, element.selectionAnchorPosition)
                    end,
                    submit = function(element)
                        element.parent:Get("input-multiline-status").text = "multiline submit"
                    end,
                },
                gui.Label{id = "input-multiline-status", classes = {"input-status"}, text = "caret 0 anchor 0"},
                captionLabel("Drag-select, arrows, Home/End, clipboard, wheel scrollbar", 34),
            },

            gui.Panel{
                width = "33%", height = "100%", flow = "vertical",
                gui.Input{
                    id = "input-consume-tab",
                    classes = {"input-field"},
                    width = "100%-10", height = 34,
                    placeholderText = "Tab and arrow event input",
                    consumeTab = true,
                    tab = function(element)
                        element.parent:Get("input-key-status").text = "event: tab (focus kept)"
                    end,
                    uparrow = function(element)
                        element.parent:Get("input-key-status").text = "event: up arrow"
                    end,
                    downarrow = function(element)
                        element.parent:Get("input-key-status").text = "event: down arrow"
                    end,
                    caretReady = function(element)
                        element.parent:Get("input-key-status").text = "event: caretReady at " .. element.caretPosition
                    end,
                },
                gui.Label{id = "input-key-status", classes = {"input-status"}, text = "key events: waiting"},
                gui.Label{
                    classes = {"interactive"},
                    width = "100%-10", height = 38,
                    text = "SET TEXT + CARET", fontSize = 12, bold = true, textAlignment = "center",
                    click = function(element)
                        element.parent:Get("input-consume-tab"):SetTextAndCaret(5, "ready: edit me")
                    end,
                },
                captionLabel("Programmatic focus and delayed caretReady", 28),
            },
        },
    },
}
end

LaunchablePanel.Register{
    name = "EXAMPLE2",
    folder = "Development Tools",

    icon = "panels/initiative/initiative-icon.png",
    halign = "center",
    valign = "center",
    draggable = true,

    content = function(args)
        return gui.Panel{
            width = 1600,
            height = 960,
            children = {CreateExample()},
        }
    end,
}