local mod = dmhub.GetModLoading()

--- Small pieces shared by the negotiation surfaces. No styles table here: one
--- would shadow the inherited ThemeEngine cascade for the whole subtree.
NEGWidgets = RegisterGameType("NEGWidgets")

--- A label-over-control form row.
--- @param labelText string
--- @param width string
--- @param control Panel
--- @param hint nil|string
--- @return Panel
function NEGWidgets.FormRow(labelText, width, control, hint)
    local children = {
        gui.Label{
            classes = { "formStacked", "sizeS" },
            text = labelText,
        },
        control,
    }

    if hint ~= nil then
        children[#children + 1] = gui.Label{
            classes = { "sizeXxs", "fgMuted" },
            italics = true,
            width = "auto",
            height = "auto",
            halign = "left",
            text = hint,
        }
    end

    return gui.Panel{
        classes = { "formStackedRow" },
        width = width,
        children = children,
    }
end

--- What the table sees. Director only.
--- @param args {shown: boolean, change: fun(shown: boolean)}
--- @return Panel
function NEGWidgets.EyeToggle(args)
    local shown = args.shown == true

    return gui.Panel{
        classes = { cond(shown, "bgFg", "bgFgMuted") },
        width = 18,
        height = 18,
        halign = "left",
        valign = "center",
        lmargin = 6,
        bgimage = cond(shown, NEGConstants.iconEyeShown, NEGConstants.iconEyeHidden),
        hover = gui.Tooltip(cond(shown,
            "The table can see this. Click to hide it.",
            "Hidden from the table. Click to show it.")),
        press = function()
            args.change(not shown)
        end,
    }
end

--- A section header with a hairline under it, drawn as a real bottom border
--- rather than a divider panel.
--- @param args {text: string, trailing: nil|Panel}
--- @return Panel
function NEGWidgets.SectionHeader(args)
    local children = {
        gui.Label{
            classes = { "tableLabel", "sizeXs" },
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            text = args.text or "",
        },
    }

    if args.trailing ~= nil then
        children[#children + 1] = args.trailing
    end

    return gui.Panel{
        classes = { "border" },
        width = NEGConstants.sectionWidth,
        height = 26,
        flow = "horizontal",
        halign = "left",
        valign = "top",
        tmargin = 10,
        border = { x1 = 0, y1 = 1, x2 = 0, y2 = 0 },
        children = children,
    }
end

--- One scale: its name, the Director's eye, numbered bubbles, and a caption.
--- Bubbles run 0..5 and light from 0 up to the value. 0 is on the scale
--- because it is a real place to be: interest 0 is "No, and...".
---
--- @param args {which: string, label: string, value: number, minValue: nil|number, maxValue: nil|number, interactive: boolean, change: nil|fun(value: number), caption: nil|string, captionClass: nil|string, eye: nil|table, width: nil|string}
--- @return Panel
function NEGWidgets.Scale(args)
    local value = NEGConstants.Clamp(args.value,
        NEGConstants.scaleMin, NEGConstants.scaleMax)
    local minValue = args.minValue or NEGConstants.scaleMin
    local maxValue = args.maxValue or NEGConstants.scaleMax
    local label = args.label or ""

    local tones = NEGConstants.patienceTone
    if args.which == NEGConstants.scaleInterest then
        tones = NEGConstants.interestTone
    end
    local litClass = tones[value] or NEGConstants.toneUnlit

    local headerChildren = {
        gui.Label{
            classes = { "sizeS" },
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            text = label,
        },
    }

    if args.eye ~= nil then
        headerChildren[#headerChildren + 1] = NEGWidgets.EyeToggle(args.eye)
    end

    local pips = {}
    for i = NEGConstants.scaleMin, NEGConstants.scaleMax do
        local lit = i <= value and not args.unknown

        --Built in one go rather than assigned onto afterwards: hover is fixed
        --at construction and will not take a later write.
        local pipArgs = {
            classes = { cond(lit, litClass, NEGConstants.toneUnlit) },
            width = NEGConstants.pipSize,
            height = NEGConstants.pipSize,
            halign = "left",
            valign = "center",
            rmargin = 2,
            bgimage = cond(args.unknown,
                NEGConstants.iconUnknown, NEGConstants.scalePips[i]),
        }

        if args.unknown then
            pipArgs.hover = gui.Tooltip("The Director has not shared this.")
        elseif args.interactive and args.change ~= nil then
            --Every bubble carries its own number, so clicking one sets it.
            if i >= minValue and i <= maxValue then
                pipArgs.hover = gui.Tooltip(string.format("Set %s to %d", label, i))
                pipArgs.press = function()
                    args.change(i)
                end
            else
                pipArgs.hover = gui.Tooltip(
                    string.format("A negotiation cannot open at %s %d.", label, i))
            end
        end

        pips[#pips + 1] = gui.Panel(pipArgs)
    end

    local children = {
        gui.Panel{
            width = "100%",
            height = 20,
            flow = "horizontal",
            halign = "left",
            valign = "top",
            children = headerChildren,
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",
            tmargin = 2,
            children = pips,
        },
    }

    if args.caption ~= nil and args.caption ~= "" then
        children[#children + 1] = gui.Label{
            classes = { "sizeXs", "noBold", args.captionClass or "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            tmargin = 2,
            textWrap = true,
            text = args.caption,
        }
    end

    return gui.Panel{
        width = args.width or NEGConstants.scaleColumnWidth,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        rmargin = 12,
        children = children,
    }
end

--- What an interest score is worth, as a caption.
--- @param interest number
--- @return string caption
--- @return string captionClass
function NEGWidgets.InterestCaption(interest)
    local value = NEGConstants.Clamp(interest,
        NEGConstants.scaleMin, NEGConstants.scaleMax)
    local tone = NEGConstants.interestTone[value] or NEGConstants.toneUnlit

    --Pips paint a fill; the caption needs the matching text colour.
    local textClass = "fgMuted"
    if tone == "bgDanger" then
        textClass = "danger"
    elseif tone == "bgWarning" then
        textClass = "warning"
    elseif tone == "bgSuccess" then
        textClass = "success"
    end

    return string.format("%d  %s", value, NEGRules.OfferName(value)), textClass
end

--- What the heroes' languages add to patience. The pips show the base; this
--- says where it opens. Silent when nothing was added.
--- @param base number the Director's starting patience
--- @param langid nil|string
--- @return string
function NEGWidgets.PatienceCaption(base, langid)
    local opening, bonus, speakers = NEGRules.OpeningPatience(base, langid)
    if bonus <= 0 then
        return ""
    end

    local who = string.format("%d heroes speak", #speakers)
    if #speakers == 1 then
        who = string.format("%s speaks", speakers[1])
    elseif #speakers == 2 then
        who = string.format("%s and %s speak", speakers[1], speakers[2])
    end

    return string.format("+%d  %s %s. Opens at %d.",
        bonus, who, NEGRules.LanguageName(langid), opening)
end

--- A hero token draggable onto a slot. gui.CreateTokenImage makes its own
--- panel and does not forward drag props, so the image goes inside as a child.
--- @param charid string
--- @param name string
--- @param draggable boolean
--- @param rightClick nil|fun(element: Panel)
--- @param dimmed nil|boolean the theme's disabled idiom, which is desaturation
--- @return Panel|nil
function NEGWidgets.HeroToken(charid, name, draggable, rightClick, dimmed)
    local token = dmhub.GetCharacterById(charid)
    if token == nil then
        return nil
    end

    local image = gui.CreateTokenImage(token, {
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
    })

        --Portrait and frame are separate child panels.
    if dimmed == true then
        image.selfStyle.saturation = 0
        for _, child in ipairs(image.children or {}) do
            child.selfStyle.saturation = 0
        end
    end

    local mine = NEGRun.CanManage(charid)

    return gui.Panel{
        classes = { NEGConstants.tokenClass },
        width = NEGConstants.tokenSize,
        height = NEGConstants.tokenSize,
        halign = "left",
        valign = "center",
        hmargin = 2,
        bgimage = true,
        bgcolor = "clear",
        draggable = draggable and mine,

        rightClick = cond(mine, rightClick),

        canDragOnto = function(element, target)
            return target:HasClass(NEGConstants.slotClass)
                or target:HasClass(NEGConstants.trayClass)
        end,

        drag = function(element, target)
            if target == nil then
                return
            end
            if target:HasClass(NEGConstants.trayClass) then
                target:FireEvent("dropToTray", charid)
            else
                target:FireEvent("dropOnSlot", charid)
            end
        end,

        hover = gui.Tooltip(name or ""),

        data = { charid = charid },

        image,
    }
end

--- The heroes not standing in a slot. Drop one back here to clear its slot.
--- A hero who has already taken a test sits greyed.
--- @param entries {charid: string, name: string, acted: boolean}[]
--- @param onReturn fun(charid: string)
--- @return Panel
function NEGWidgets.Tray(entries, onReturn)
    local children = {}
    for _, entry in ipairs(entries) do
        local token = NEGWidgets.HeroToken(entry.charid, entry.name, true, nil,
            entry.acted == true)
        if token ~= nil then
            children[#children + 1] = token
        end
    end

    if #children == 0 then
        children[#children + 1] = gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "center",
            valign = "center",
            textAlignment = "center",
            text = "Everyone is placed",
        }
    end

    return gui.Panel{
        classes = { "bordered", NEGConstants.trayClass },
        width = "100%",
        height = NEGConstants.trayHeight,
        flow = "horizontal",
        halign = "left",
        valign = "top",
        pad = 4,
        vmargin = 4,
        dragTarget = true,

        dropToTray = function(element, charid)
            onReturn(charid)
        end,

        children = children,
    }
end

--- A place to stand one hero: click for a menu, or drag one in.
--- @param args {label: string, charid: nil|string, name: nil|string, inert: boolean, options: {charid: string, name: string}[], place: fun(charid: string), clear: fun()}
--- @return Panel
function NEGWidgets.Slot(args)
    local charid = args.charid
    local inert = args.inert == true

    local classes = { "bordered", NEGConstants.slotClass }
    if inert then
        classes[#classes + 1] = "disabled"
    end

    local removeMenu = nil
    if charid ~= nil and not inert then
        removeMenu = function(element)
            element.popup = gui.ContextMenu{
                entries = {
                    {
                        text = "Remove",
                        click = function()
                            element.popup = nil
                            args.clear()
                        end,
                    },
                },
            }
        end
    end

    local children = {}
    if charid ~= nil then
        local token = NEGWidgets.HeroToken(charid, args.name, not inert, removeMenu, inert)
        if token ~= nil then
            children[#children + 1] = token
        end
    end

    local box = gui.Panel{
        classes = classes,
        width = NEGConstants.slotSize,
        height = NEGConstants.slotSize,
        flow = "none",
        halign = "center",
        valign = "top",
        dragTarget = not inert,
        hover = gui.Tooltip(args.label or ""),

        dropOnSlot = function(element, dropped)
            args.place(dropped)
        end,

        rightClick = removeMenu,

        --Empty offers who is free; filled also offers Remove.
        press = function(element)
            if inert then
                return
            end

            local entries = {}

            if charid ~= nil then
                if not NEGRun.CanManage(charid) then
                    return
                end

                entries[#entries + 1] = {
                    text = "Remove",
                    click = function()
                        element.popup = nil
                        args.clear()
                    end,
                }
            end

            for _, option in ipairs(args.options or {}) do
                if NEGRun.CanManage(option.charid) then
                    entries[#entries + 1] = {
                        text = option.name or "",
                        click = function()
                            element.popup = nil
                            args.place(option.charid)
                        end,
                    }
                end
            end

            if #entries == 0 then
                entries[#entries + 1] = {
                    text = "No one available",
                    click = function()
                        element.popup = nil
                    end,
                }
            end

            element.popup = gui.ContextMenu{ entries = entries }
        end,

        children = children,
    }

    return gui.Panel{
        width = NEGConstants.slotSize,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        rmargin = 8,

        box,

        gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "center",
            valign = "top",
            textAlignment = "center",
            text = args.label or "",
        },
    }
end

--- A curtain over whatever hosts it: dims it, swallows clicks, says why.
---
--- `interactable` on a panel with nothing to click is what stops the raycast
--- reaching the controls underneath. The size is measured rather than declared:
--- a host sized to its own content gives a percentage nothing to resolve
--- against, and rendered sizes read 0 until the first layout pass. Append it
--- LAST to the host's children - that is what puts it on top.
--- Collapsed until the caller shows it.
--- @param text string
--- @param sizeClass string
--- @param hostLevels nil|number how far up to measure; 1 (the parent) by default
--- @param inset nil|number the host's padding, which it does not expose
--- @return Panel
function NEGWidgets.Overlay(text, sizeClass, hostLevels, inset)
    hostLevels = hostLevels or 1
    inset = inset or 0

    return gui.Panel{
        classes = { "bordered", "collapsed" },
        floating = true,
        width = "100%",
        height = "100%",
        halign = "left",
        valign = "top",
        flow = "none",
        bgimage = true,

        bgcolor = "#000000c0",

        --Stops the raycast reaching the controls underneath.
        interactable = true,

        --A host sized to its own content gives a percentage nothing to resolve
        --against, and renderedHeight reads 0 until the first layout pass.
        thinkTime = 0.2,
        think = function(element)
            if element:HasClass("collapsed") then
                return
            end

            --A rebuild can leave a stale link up the chain, and reading
            --anything off a panel whose object has gone raises.
            local host = element
            for _ = 1, hostLevels do
                if host == nil or not host.valid then
                    return
                end
                host = host.parent
            end
            if host == nil or not host.valid then
                return
            end

            local w = host.renderedWidth
            local h = host.renderedHeight
            if w ~= nil and w > 0 and h ~= nil and h > 0 then
                --Padding counts as part of the host, so its rendered size
                --includes it while children start inside it. Step back out.
                element.selfStyle.width = w
                element.selfStyle.height = h
                element.x = -inset
                element.y = -inset
            end
        end,

        gui.Label{
            classes = { sizeClass, "bold" },
            width = "90%",
            height = "auto",
            halign = "center",
            valign = "center",
            textAlignment = "center",
            textWrap = true,
            text = text,
        },
    }
end

--- A line of text where a surface would otherwise be empty. Collapsed until
--- the caller shows it.
--- @param message string
--- @return Panel
function NEGWidgets.Notice(message)
    return gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "100% available",
        flow = "vertical",
        halign = "center",
        valign = "center",

        gui.Label{
            classes = { "sizeL", "noBold", "fgMuted" },
            width = "80%",
            height = "auto",
            halign = "center",
            valign = "center",
            textAlignment = "center",
            textWrap = true,
            text = message,
        },
    }
end
