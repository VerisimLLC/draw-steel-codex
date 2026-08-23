local mod = dmhub.GetModLoading()

--Per-control dev notes, written IN-APP: the info glyph on each zoo
--entry opens a note editor; the note saves on every keystroke
--(preference storage -- local to this machine), keyed by the entry's
--name. Hovering the glyph shows the note; a dim glyph means no note
--yet.
setting{
    id = "controlzoo:notes",
    storage = "preference",
    default = {},
}

local function GetZooNote(name)
    local t = dmhub.GetSettingValue("controlzoo:notes") or {}
    local note = t[name]
    if note == nil or note == "" then
        return nil
    end
    return note
end

local function SetZooNote(name, text)
    local t = dmhub.GetSettingValue("controlzoo:notes") or {}
    if text == nil or text == "" then
        t[name] = nil
    else
        t[name] = text
    end
    dmhub.SetSettingValue("controlzoo:notes", t)
end

local g_formStyles = {
    --each control entry is a framed CARD (owner request 2026-08-20):
    --title, control, and its knobs visibly grouped, so it is clear
    --which pieces belong to which sample.
    gui.Style{
        classes = {"formPanel"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        vmargin = 6,
        bgimage = "panels/square.png",
        bgcolor = "#ffffff05",
        border = 1,
        borderColor = "#ffffff1a",
        cornerRadius = 8,
        pad = 12,
        borderBox = true,
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
                labelChildren[#labelChildren + 1] = gui.Label {
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
            --dev notes: the info glyph opens an in-app note editor for
            --this control. Saves on every keystroke, so closing the
            --popup any way (click away, escape) never loses text.
            local noteIcon
            noteIcon = gui.Panel {
                bgimage = "phosphor/info.png",
                width = 14,
                height = 14,
                bgcolor = cond(GetZooNote(args.name) ~= nil, "#88bbee", "#55606a"),
                valign = "center",
                hmargin = 4,
                --anchor the editor popup to the glyph rather than the
                --default placement, which clipped off the window's edge.
                popupPositioning = "panel",
                styles = {
                    {
                        selectors = {"hover"},
                        bgcolor = "#aaccee",
                        transitionTime = 0.1,
                    },
                },
                linger = function(element)
                    local note = GetZooNote(args.name)
                    gui.Tooltip(note or "Click to write dev notes for this control")(element)
                end,
                press = function(element)
                    local function SyncIcon(text)
                        SetZooNote(args.name, text)
                        if noteIcon ~= nil and noteIcon.valid then
                            noteIcon.selfStyle.bgcolor = cond(GetZooNote(args.name) ~= nil, "#88bbee", "#55606a")
                        end
                    end
                    element.popup = gui.Panel{
                        styles = Styles.Default,
                        --popup halign/valign place it relative to the
                        --anchor (see popupPositioning docs): open to the
                        --right of and below the glyph.
                        halign = "right",
                        valign = "bottom",
                        width = 380,
                        height = "auto",
                        flow = "vertical",
                        bgimage = "panels/square.png",
                        bgcolor = "#14161b",
                        border = 1,
                        borderColor = "#ffffff30",
                        cornerRadius = 8,
                        pad = 10,
                        borderBox = true,
                        gui.Label{
                            text = "Dev notes: " .. args.name,
                            fontSize = 14,
                            bold = true,
                            width = "100%",
                            height = "auto",
                            bmargin = 6,
                        },
                        gui.Input{
                            width = "100%",
                            height = "auto",
                            minHeight = 120,
                            multiline = true,
                            textAlignment = "topleft",
                            fontSize = 13,
                            characterLimit = 4000,
                            text = GetZooNote(args.name) or "",
                            placeholderText = "Best practices, gotchas, guidance...",
                            hasFocus = true,
                            editlag = 0.3,
                            edit = function(input)
                                SyncIcon(input.text)
                            end,
                            change = function(input)
                                SyncIcon(input.text)
                            end,
                        },
                        gui.Label{
                            text = "Saves as you type. Click away to close.",
                            fontSize = 10,
                            color = "#888888",
                            width = "100%",
                            height = "auto",
                            tmargin = 4,
                        },
                    }
                end,
            }
            labelChildren[#labelChildren + 1] = noteIcon
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

                --First in the zoo while the canonical search look is under
                --active work (2026-08-20): the one true search field, as
                --every surface receives it from gui.SearchInput +
                --DefaultStyles' searchInput rules.
                ControlEntry{
                    name = "Search Input",
                    snippet = [[gui.SearchInput{
    width = 260,
    height = 26,
    placeholderText = "Search...",
    -- fires with the lowercased, trimmed query ("" for cleared or
    -- single-character input):
    search = function(element, text)
        -- filter your list on `text`
    end,
}]],
                    control = gui.Panel{
                        height = "auto",
                        vpad = 10,
                        halign = "center",
                        flow = "vertical",
                        --the backdrop the sample sits on: toggleable to the
                        --app's light fill (@bgInverse parchment) so the
                        --field can be judged over a light surface during
                        --visual development.
                        gui.Panel{
                            id = "search-input-backdrop",
                            width = "auto",
                            height = "auto",
                            pad = 14,
                            halign = "center",
                            bgimage = true,
                            bgcolor = "clear",
                            cornerRadius = 8,
                            setLightBackdrop = function(element, on)
                                element.selfStyle.bgcolor = cond(on, "#E4DDD0", "clear")
                            end,
                            gui.SearchInput{
                                halign = "center",
                                valign = "center",
                                width = 260,
                                height = 26,
                                search = function(element, text)
                                    outputLabel.text = "Search: \"" .. text .. "\""
                                end,
                            },
                        },
                        gui.Check{
                            tmargin = 8,
                            halign = "center",
                            text = "Light backdrop",
                            value = false,
                            change = function(element)
                                local backdrop = element.parent:Get("search-input-backdrop")
                                if backdrop ~= nil then
                                    backdrop:FireEvent("setLightBackdrop", element.value)
                                end
                            end,
                        },

                        --REAL example data, on demand: pick a data set and
                        --a connected search mounts below the sample.
                        --"Global search (live)" is the actual title-bar bar
                        --(TopBar factory) with its genuine results popup;
                        --the compendium sets render their rows with the
                        --SAME searchResult* classes, so styling either
                        --styles the real search everywhere.
                        gui.Panel{
                            id = "live-search-host",
                            width = "100%",
                            height = "auto",
                            flow = "vertical",
                            halign = "center",
                            mountDataset = function(element, choice)
                                if choice == nil or choice == "none" then
                                    element.children = {}
                                    return
                                end
                                if rawget(_G, "TopBar") == nil or TopBar.CreateSearchBar == nil then
                                    element.children = {
                                        gui.Label{
                                            text = "Unavailable (TopBar search factory not exposed in this build).",
                                            fontSize = 11,
                                            color = "#aa8888",
                                            width = "100%",
                                            height = "auto",
                                            textAlignment = "center",
                                        },
                                    }
                                    return
                                end

                                if choice == "global" then
                                    local host = gui.Panel{
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        tmargin = 10,
                                        flow = "vertical",
                                        --the popup inherits the host
                                        --cascade; these are the title
                                        --bar's own rules, so the popup
                                        --renders exactly as the real one.
                                        styles = ThemeEngine.MergeStyles(TopBar.SearchBarStyles()),
                                        TopBar.CreateSearchBar(),
                                    }
                                    element.children = { host }
                                    --the sheet hides the bar outside the
                                    --game ("~ingame"); mirror the title
                                    --bar's class.
                                    host:SetClassTree("ingame", true)
                                    return
                                end

                                local datasets = {
                                    conditions = { table = "charConditions", label = "Condition" },
                                    classes = { table = "classes", label = "Class" },
                                    careers = { table = "careers", label = "Career" },
                                    effects = { table = "characterOngoingEffects", label = "Ongoing Effect" },
                                }
                                local info = datasets[choice]
                                if info == nil then
                                    element.children = {}
                                    return
                                end

                                local resultsPanel
                                local function BuildRows(needle)
                                    local names = {}
                                    local t = dmhub.GetTable(info.table) or {}
                                    for _, obj in unhidden_pairs(t) do
                                        local name = nil
                                        pcall(function() name = obj.name end)
                                        if name ~= nil and (needle == "" or string.find(string.lower(name), needle, 1, true)) then
                                            names[#names + 1] = name
                                        end
                                    end
                                    table.sort(names)
                                    local rows = {}
                                    for i, name in ipairs(names) do
                                        if i > 12 then
                                            rows[#rows + 1] = gui.Label{
                                                classes = {"searchSeeAll"},
                                                text = string.format("... and %d more", #names - 12),
                                                width = "100%-12",
                                                height = "auto",
                                            }
                                            break
                                        end
                                        rows[#rows + 1] = gui.Panel{
                                            classes = {"searchResultRow"},
                                            flow = "horizontal",
                                            gui.Panel{
                                                classes = {"searchResultIcon"},
                                                bgimage = "phosphor/sparkle.png",
                                                interactable = false,
                                            },
                                            gui.Label{
                                                classes = {"searchResultName"},
                                                text = name,
                                                --fixed remainder, not "available":
                                                --available width re-resolved
                                                --unstably on hover restyles and the
                                                --row ballooned in a flicker loop
                                                --(live-debugged 2026-08-20).
                                                width = "100%-110",
                                                height = "auto",
                                                textAlignment = "left",
                                                textWrap = false,
                                                interactable = false,
                                            },
                                            gui.Label{
                                                classes = {"searchResultType"},
                                                text = info.label,
                                                interactable = false,
                                            },
                                        }
                                    end
                                    if #rows == 0 then
                                        rows[1] = gui.Label{
                                            classes = {"searchSeeAll"},
                                            text = "No matches.",
                                            width = "100%-12",
                                            height = "auto",
                                        }
                                    end
                                    return rows
                                end

                                resultsPanel = gui.Panel{
                                    --just searchResultsPanel, matching the real
                                    --popup's seamless look (fill, no frame).
                                    classes = {"searchResultsPanel"},
                                    flow = "vertical",
                                    width = 368,
                                    height = "auto",
                                    halign = "center",
                                    tmargin = 6,
                                    vscroll = true,
                                    children = BuildRows(""),
                                }

                                local host = gui.Panel{
                                    width = "auto",
                                    height = "auto",
                                    halign = "center",
                                    tmargin = 10,
                                    flow = "vertical",
                                    --same sheet as the real popup, so
                                    --the searchResult* classes style
                                    --these rows identically.
                                    styles = ThemeEngine.MergeStyles(TopBar.SearchBarStyles()),
                                    gui.SearchInput{
                                        halign = "center",
                                        width = 368,
                                        height = 26,
                                        placeholderText = "Search " .. string.lower(info.label) .. "s...",
                                        search = function(input, text)
                                            if resultsPanel ~= nil and resultsPanel.valid then
                                                resultsPanel.children = BuildRows(text)
                                            end
                                        end,
                                    },
                                    resultsPanel,
                                }
                                element.children = { host }
                                --the merged sheet hides search inputs
                                --outside the game ("~ingame"); mirror the
                                --title bar's class here too.
                                host:SetClassTree("ingame", true)
                            end,
                        },
                        gui.Panel{
                            flow = "horizontal",
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            tmargin = 6,
                            gui.Label{
                                text = "Data set:",
                                fontSize = 13,
                                width = "auto",
                                height = "auto",
                                valign = "center",
                                rmargin = 8,
                            },
                            gui.Dropdown{
                                width = 220,
                                height = 24,
                                valign = "center",
                                options = {
                                    { id = "none", text = "Disconnected" },
                                    { id = "global", text = "Global search (live)" },
                                    { id = "conditions", text = "Conditions" },
                                    { id = "classes", text = "Classes" },
                                    { id = "careers", text = "Careers" },
                                    { id = "effects", text = "Ongoing effects" },
                                },
                                idChosen = "none",
                                change = function(element)
                                    local hostPanel = element.parent.parent:Get("live-search-host")
                                    if hostPanel ~= nil then
                                        hostPanel:FireEvent("mountDataset", element.idChosen)
                                    end
                                end,
                            },
                        },
                    },
                },

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
                    snippet = [[gui.Button{
    classes = {"deleteButton"},
    click = function() end,
}]],
                    control = gui.Button {
                        classes = {"deleteButton"},
                        halign = "center",
                        valign = "center",
                        click = function()
                            outputLabel.text = "DELETE clicked!"
                        end,
                    },
                },

                ControlEntry {
                    name = "Close Button",
                    snippet = [[gui.Button{
    -- the canonical close X (phosphor glyph). Escape activation
    -- and the close sound come from the closeButton kind config.
    -- Typically pinned: halign = "right", valign = "top", floating = true
    classes = {"closeButton"},
    click = function(element)
        -- close the dialog
    end,
}]],
                    control = gui.Button {
                        classes = {"closeButton"},
                        halign = "center",
                        valign = "center",
                        escapeActivates = false,
                        click = function()
                            outputLabel.text = "CLOSE clicked!"
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
                    name = "Text Input (framed)",
                    snippet = [[gui.Input{
    -- opt-in resting frame for inputs sitting on surfaces at or
    -- below @bg, where the default frameless well would vanish
    classes = {"bordered"},
    width = 180,
    height = 20,
    fontSize = 16,
    placeholderText = "Enter text...",
}]],
                    control = gui.Input {
                        classes = {"bordered"},
                        halign = "center",
                        valign = "center",

                        width = 180,
                        height = 20,
                        fontSize = 16,

                        placeholderText = "For dark surfaces...",
                        edit = function(element)
                            outputLabel.text = "Framed input changed to " .. element.text
                        end,

                        change = function(element)
                            outputLabel.text = "Framed input submitted: " .. element.text
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
                    name = "Progress Bar",
                    snippet = [[gui.ProgressBar{
    width = 320,
    height = 48,
    value = 0.4,  -- 0.0 to 1.0
}

-- Update later:
--   progressBar:SetValue(0.75)
-- or:
--   progressBar.value = 0.75]],
                    control = gui.Panel{
                        height = "auto",
                        vpad = 10,
                        halign = "center",
                        flow = "vertical",
                        gui.ProgressBar{
                            id = "test-progress-bar",
                            halign = "center",
                            width = 320,
                            height = 48,
                            value = 0.4,
                            thinkTime = 0.01,
                            think = function(element)
                                element.value = math.sin(dmhub.Time() * 0.5) * 0.5 + 0.5
                            end,
                        },
                        gui.Slider{
                            tmargin = 8,
                            halign = "center",
                            minValue = 0,
                            maxValue = 100,
                            value = 40,
                            height = 20,
                            width = 180,
                            change = function(element)
                                local bar = element.parent:Get("test-progress-bar")
                                if bar then
                                    bar.value = element.value / 100
                                end
                                outputLabel.text = string.format("Progress: %d%%", math.floor(element.value))
                            end,
                        },
                    },
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
