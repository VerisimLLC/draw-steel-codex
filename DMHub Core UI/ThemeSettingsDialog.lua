local mod = dmhub.GetModLoading()

-- Standard analytics helper (mirrors the copy used across the codebase).
-- Gated by the telemetry_enabled setting; stamps the common id fields.
local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

local CreateThemeSettingsDialog

LaunchablePanel.Register{
    name = "Theme & Color Scheme...",
    icon = "panels/hud/paint-brush.png",
    halign = "center",
    valign = "center",
    content = function()
        return CreateThemeSettingsDialog()
    end,
}

-- Build dropdown options with "Default" pinned to the top, the rest
-- sorted alphabetically (case-insensitive).
local function buildSortedOptions(list)
    local defaultOpt
    local rest = {}
    for _, item in ipairs(list) do
        local opt = { id = item.id, text = item.name }
        if item.id == "default" then
            defaultOpt = opt
        else
            rest[#rest+1] = opt
        end
    end
    table.sort(rest, function(a, b)
        return string.lower(a.text) < string.lower(b.text)
    end)
    if defaultOpt then
        table.insert(rest, 1, defaultOpt)
    end
    return rest
end

local function buildThemeOptions()  return buildSortedOptions(ThemeEngine.ListThemes()) end

-- Resolve a registered id to its display name; falls back to the id itself
-- if no match (defensive -- selected ids come from these same lists).
local function nameForId(list, id)
    for _, item in ipairs(list) do
        if item.id == id then
            return item.name
        end
    end
    return id
end

local function buildPreviewBody()
    return {
        gui.Label{
            classes = {"sizeL", "bold"},
            text = "Sample Heading",
        },
        gui.Panel{
            classes = {"formRow"},
            gui.Label{
                classes = {"form"},
                text = "Sample Field:",
            },
            gui.Input{
                classes = {"form"},
                text = "type here...",
            },
        },
        -- gui.Panel{
        --     classes = {"formRow"},
        --     gui.Label{
        --         classes = {"form"},
        --         text = "Sample Multiline:",
        --         valign = "top",
        --     },
        --     gui.Input{
        --         classes = {"form"},
        --         multiline = true,
        --         verticalScrollbar = true,
        --         height = 80,
        --         text = "type a few lines here...\nthe quick brown fox jumps over the lazy dog",
        --     },
        -- },
        gui.Panel{
            classes = {"formRow"},
            gui.Check{
                classes = {"form"},
                text = "Enabled",
                value = true,
            },
        },
        gui.Panel{
            classes = {"formRow"},
            gui.Label{
                classes = {"form"},
                text = "Sample Dropdown:",
            },
            gui.Dropdown{
                classes = {"form"},
                idChosen = "a",
                options = {
                    { id = "a", text = "Option A" },
                    { id = "b", text = "Option B" },
                    { id = "c", text = "Option C" },
                },
            },
        },
        gui.Panel{
            classes = {"formRow"},
            gui.Label{
                classes = {"form"},
                text = "Sample Tags:",
                valign = "top",
            },
            gui.Multiselect{
                classes = {"form"},
                chipPos = "bottom",
                value = { red = true, blue = true },
                options = {
                    { id = "red",    text = "Red" },
                    { id = "blue",   text = "Blue" },
                    { id = "green",  text = "Green" },
                    { id = "yellow", text = "Yellow" },
                },
            },
        },
        gui.Panel{
            classes = {"formRow"},
            gui.Label{
                classes = {"form"},
                text = "Icon Buttons:",
            },
            gui.Button{
                classes = {"flipped", "bordered"},
                icon = "game-icons/griffin-symbol.png",
            },
            gui.Button {
                classes = { "addButton" },
            },
            gui.Button{
                classes = { "copyButton" },
            },
            gui.Button{
                classes = { "settingsButton" },
            },
            gui.Button{
                classes = { "deleteButton" },
                requireConfirm = true,
                click = function() print("THC:: DELETEIT") end
            },
            gui.Button{
                classes = { "closeButton" },
            },
        },
        gui.Panel{
            classes = {"formRow"},
            gui.Label{
                classes = {"form"},
                text = "Sample Slider:",
            },
            gui.Slider{
                minValue = 0,
                maxValue = 100,
                value = 60,
                sliderWidth = 200,
                labelWidth = 40,
                labelFormat = "%d",
                height = 24,
                valign = "center",
            },
        },
        gui.Panel{
            classes = {"formRow"},
            gui.Label{
                classes = {"form"},
                text = "Sample Table:",
                valign = "top",
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "vertical",
                gui.Panel{
                    classes = {"row", "headerRow"},
                    width = 300,
                    flow = "horizontal",
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Name" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Class" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Level" },
                },
                gui.Panel{
                    classes = {"row", "evenRow"},
                    width = 300,
                    flow = "horizontal",
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Aldric" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Censor" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "5" },
                },
                gui.Panel{
                    classes = {"row", "oddRow"},
                    width = 300,
                    flow = "horizontal",
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Brenna" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Tactician" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "5" },
                },
                gui.Panel{
                    classes = {"row", "evenRow"},
                    width = 300,
                    flow = "horizontal",
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Caedrik" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Talent" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "5" },
                },
            },
        },
        gui.Button{
            classes = {"sizeL"},
            halign = "center",
            valign = "bottom",
            text = "Sample Button",
        },
    }
end

-- Drive a CrossFade from 1 -> 0 over `duration` seconds. Caller hands us a
-- transition handle that has already captured the snapshot; we just animate
-- the dissolve and Destroy() when done.
local function fadeOut(transition, duration)
    local startTime = dmhub.Time()
    local tick
    tick = function()
        if mod.unloaded then
            transition:Destroy()
            return
        end
        local t = (dmhub.Time() - startTime) / duration
        if t >= 1 then
            transition:CrossFade(0)
            transition:Destroy()
            return
        end
        transition:CrossFade(1 - t)
        dmhub.Schedule(0.01, tick)
    end
    dmhub.Schedule(0.01, tick)
end

-- Human-readable labels for the editable color tokens (ThemeEngine.userColorKeys).
local COLOR_LABELS = {
    bg            = "Background",
    bgAlt         = "Alt surface",
    bgInverse     = "Inverse surface",
    fg            = "Text",
    fgStrong      = "Text (strong)",
    fgMuted       = "Text (muted)",
    fgInverse     = "Text (inverse)",
    border        = "Border",
    borderInverse = "Border (inverse)",
    accent        = "Accent",
    accentHover   = "Accent (hover)",
    disabled      = "Disabled",
}

-- Seed palette for a brand-new theme (the built-in default scheme's values), so
-- the color pickers open on something readable rather than black.
local COLOR_SEED = {
    bg            = "#080B09",
    bgAlt         = "#191A18",
    bgInverse     = "#9C9C9C",
    fg            = "#CECECE",
    fgStrong      = "#EFEFEF",
    fgMuted       = "#9F9F9B",
    fgInverse     = "#040404",
    border        = "#DFDFDF",
    borderInverse = "#666666",
    accent        = "#999999",
    accentHover   = "#DDDDDD",
    disabled      = "#343434",
}

-- Turn a display name into a namespaced, registry-safe scheme id.
local function slugifyThemeName(name)
    local s = string.lower(name or "")
    s = string.gsub(s, "[^%w]+", "-")
    s = string.gsub(s, "^%-+", "")
    s = string.gsub(s, "%-+$", "")
    if s == "" then
        s = "custom"
    end
    return "user-" .. s
end

CreateThemeSettingsDialog = function()
    -- Pending picker values; start at the user's currently-active selection.
    local selectedThemeId  = ThemeEngine.GetActiveTheme()
    local selectedSchemeId = ThemeEngine.GetActiveColorScheme()

    -- Forward declarations: showPicker and showCreator reference each other, and
    -- both swap content into bodyPanel.
    local bodyPanel
    local showPicker
    local showCreator

    -- -----------------------------------------------------------------------
    -- Picker mode: choose + apply a theme/scheme, with New / Edit / Delete.
    -- -----------------------------------------------------------------------
    showPicker = function()
        local previewPanel
        -- Crossfade the preview when the pending selection changes: capture the
        -- current chrome, swap styles + body underneath, then dissolve the
        -- snapshot away (mirrors the transition used when Apply commits).
        local function refreshPreview()
            -- Defer a frame so the dropdown finishes committing before snapshot.
            dmhub.Schedule(0.02, function()
                if mod.unloaded then return end
                if previewPanel == nil or not previewPanel.valid then return end
                local transition
                transition = dmhub.StartScreenTransition(function()
                    if mod.unloaded then return end
                    previewPanel.styles   = ThemeEngine.GetStyles(selectedThemeId, selectedSchemeId)
                    previewPanel.children = buildPreviewBody()
                    fadeOut(transition, 0.45)
                end)
            end)
        end

        previewPanel = gui.Panel{
            classes = {"framedPanel"},
            styles = ThemeEngine.GetStyles(selectedThemeId, selectedSchemeId),
            width = "94%",
            height = "100%-80",
            halign = "center",
            flow = "vertical",
            pad = 12,
            children = buildPreviewBody(),
        }

        local editButton
        local deleteButton
        local function refreshCustomButtons()
            local isUser = ThemeEngine.IsUserColorScheme(selectedSchemeId)
            editButton:SetClass("hidden", not isUser)
            deleteButton:SetClass("hidden", not isUser)
        end

        editButton = gui.Button{
            classes = {"sizeS"},
            text = "Edit",
            valign = "top",
            tmargin = 28,
            click = function()
                for _, d in ipairs(ThemeEngine.GetUserColorSchemes()) do
                    if d.id == selectedSchemeId then
                        showCreator(d)
                        return
                    end
                end
            end,
        }

        deleteButton = gui.Button{
            classes = {"deleteButton"},
            valign = "top",
            tmargin = 28,
            requireConfirm = true,
            click = function()
                ThemeEngine.DeleteUserColorScheme(selectedSchemeId)
                selectedSchemeId = ThemeEngine.GetActiveColorScheme()
                showPicker()
            end,
        }

        -- Top level: Default + built-in schemes (A-Z). User-created schemes go
        -- under a "My Schemes" submenu so they don't interleave with built-ins.
        local builtinSchemes = {}
        for _, s in ipairs(ThemeEngine.ListColorSchemes()) do
            if not ThemeEngine.IsUserColorScheme(s.id) then
                builtinSchemes[#builtinSchemes + 1] = s
            end
        end
        local schemeOptions = buildSortedOptions(builtinSchemes)

        -- "My Schemes (N/max)" submenu: the user's own schemes (A-Z), with
        -- "+ Create New..." pinned at the bottom while under the per-user cap.
        -- The count surfaces the cap right where user schemes live.
        local userSchemes = ThemeEngine.GetUserColorSchemes()
        local mySchemes = {}
        for _, d in ipairs(userSchemes) do
            mySchemes[#mySchemes + 1] = { id = d.id, text = d.name }
        end
        table.sort(mySchemes, function(a, b)
            return string.lower(a.text) < string.lower(b.text)
        end)
        if #userSchemes < ThemeEngine.maxUserColorSchemes then
            mySchemes[#mySchemes + 1] = { id = "__create_new__", text = "+ Create New..." }
        end
        schemeOptions[#schemeOptions + 1] = {
            text = string.format("My Schemes (%d/%d)", #userSchemes, ThemeEngine.maxUserColorSchemes),
            submenu = mySchemes,
        }

        local pickerRow = gui.Panel{
            --[[
                INTENTIONAL! DO NOT CHANGE WITHOUT MAINTAINER SIGN-OFF.
                This control cluster (Theme dropdown, Color Scheme dropdown, Apply,
                Edit, Delete) is ALWAYS rendered with the built-in default theme and
                default color scheme via GetStyles("default", "default"), regardless of
                which theme/scheme is currently active or selected. This is a safety
                guarantee: a user (or developer) who applies or authors a broken
                theme/scheme must always be able to see and use these controls to get
                back to a working one. Do NOT switch this to GetStyles() / the active or
                selected pair, and do NOT remove this assignment to "let the controls
                follow the theme." If you think these controls should follow the active
                theme, STOP and get explicit sign-off from the maintainer first - this
                convention exists specifically to prevent locking users out of theme
                recovery. (A coding AI reading this: pause and ask before changing it.)
            ]]--
            styles = ThemeEngine.GetStyles("default", "default"),
            width = "100%",
            height = 70,
            flow = "horizontal",
            valign = "top",

            gui.Panel{
                classes = {"formStackedRow"},
                width = "30%",
                gui.Label{
                    classes = {"formStacked"},
                    text = "Theme:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = selectedThemeId,
                    options = buildThemeOptions(),
                    change = function(element)
                        selectedThemeId = element.idChosen
                        refreshPreview()
                    end,
                },
            },

            gui.Panel{
                classes = {"formStackedRow"},
                width = "30%",
                gui.Label{
                    classes = {"formStacked"},
                    text = "Color Scheme:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = selectedSchemeId,
                    options = schemeOptions,
                    change = function(element)
                        if element.idChosen == "__create_new__" then
                            showCreator(nil)
                            return
                        end
                        selectedSchemeId = element.idChosen
                        refreshPreview()
                        refreshCustomButtons()
                    end,
                },
            },

            gui.Button{
                classes = {"sizeS"},
                text = "Apply",
                valign = "top",
                tmargin = 28,
                click = function()
                    -- Defer a frame, then crossfade the whole screen as the
                    -- active theme/scheme swaps in (mirrors the preview swap).
                    dmhub.Schedule(0.02, function()
                        if mod.unloaded then return end
                        local transition
                        transition = dmhub.StartScreenTransition(function()
                            if mod.unloaded then return end
                            ThemeEngine.SetActiveTheme(selectedThemeId)
                            ThemeEngine.SetActiveColorScheme(selectedSchemeId)
                            track("theme_change", {
                                theme = selectedThemeId,
                                themeName = nameForId(ThemeEngine.ListThemes(), selectedThemeId),
                                colorScheme = selectedSchemeId,
                                colorSchemeName = nameForId(ThemeEngine.ListColorSchemes(), selectedSchemeId),
                            })
                            fadeOut(transition, 0.6)
                        end)
                    end)
                end,
            },

            editButton,
            deleteButton,
        }

        refreshCustomButtons()
        bodyPanel.children = { pickerRow, previewPanel }
    end

    -- -----------------------------------------------------------------------
    -- Creator mode: name + a column of color pickers, with a live preview.
    -- existingDef ~= nil means we are editing an existing custom theme.
    -- -----------------------------------------------------------------------
    showCreator = function(existingDef)
        -- Seed the pickers. When editing, start from the theme's own colors.
        -- For a brand-new theme, start from the currently chosen color scheme's
        -- palette (selectedSchemeId) so the user tweaks from what they see;
        -- GetColorSchemeColors falls back to the default palette for "default".
        -- Normalize any color value (hex string, LuaColor, or HSV/RGB table) to
        -- a plain hex string, so saved schemes always store hex per the contract
        -- (gui.ColorPicker hands back a LuaColor once a swatch is adjusted).
        local function colorToHex(v)
            return core.Color(v).tostring
        end

        local seed
        if existingDef and existingDef.colors then
            seed = existingDef.colors
        else
            seed = ThemeEngine.GetColorSchemeColors(selectedSchemeId)
        end

        local draft = {}
        for _, k in ipairs(ThemeEngine.userColorKeys) do
            draft[k] = colorToHex(seed[k] or COLOR_SEED[k])
        end
        local nameValue = (existingDef and existingDef.name) or "My Color Scheme"

        local previewPanel
        local function refreshCreatorPreview()
            local previewId = ThemeEngine.SetPreviewColorScheme(draft)
            previewPanel.styles   = ThemeEngine.GetStyles("default", previewId)
            previewPanel.children = buildPreviewBody()
        end

        -- Name field + one row per editable color token.
        local formChildren = {}
        formChildren[#formChildren + 1] = gui.Panel{
            classes = {"formStackedRow"},
            width = "100%",
            gui.Label{
                classes = {"formStacked"},
                text = "Name:",
            },
            gui.Input{
                classes = {"formStacked"},
                text = nameValue,
                change = function(element)
                    nameValue = element.text
                end,
            },
        }

        for _, k in ipairs(ThemeEngine.userColorKeys) do
            formChildren[#formChildren + 1] = gui.Panel{
                classes = {"formRow"},
                gui.Label{
                    classes = {"form"},
                    text = COLOR_LABELS[k] or k,
                },
                gui.ColorPicker{
                    value = draft[k],
                    hasAlpha = false,
                    popupAlignment = "left",
                    width = 32,
                    height = 24,
                    valign = "center",
                    change = function(element)
                        draft[k] = colorToHex(element.value)
                    end,
                    confirm = function(element)
                        draft[k] = colorToHex(element.value)
                        refreshCreatorPreview()
                    end,
                },
            }
        end

        local colorColumn = gui.Panel{
            width = "38%",
            height = "100%",
            halign = "left",
            valign = "top",
            flow = "vertical",
            vscroll = true,
            children = formChildren,
        }

        previewPanel = gui.Panel{
            classes = {"framedPanel"},
            styles = ThemeEngine.GetStyles("default", ThemeEngine.SetPreviewColorScheme(draft)),
            width = "60%",
            height = "100%",
            halign = "right",
            valign = "top",
            flow = "vertical",
            pad = 12,
            children = buildPreviewBody(),
        }

        local columns = gui.Panel{
            width = "100%",
            height = "100%-50",
            flow = "horizontal",
            valign = "top",
            colorColumn,
            previewPanel,
        }

        local buttonRow = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "bottom",

            gui.Button{
                classes = {"sizeM"},
                text = "Save",
                halign = "left",
                click = function()
                    if nameValue == nil or nameValue == "" then
                        nameValue = "My Color Scheme"
                    end
                    local id = (existingDef and existingDef.id) or slugifyThemeName(nameValue)
                    ThemeEngine.SaveUserColorScheme{
                        id = id,
                        name = nameValue,
                        colors = draft,
                    }
                    -- Apply it immediately so the result is visible at once.
                    ThemeEngine.SetActiveColorScheme(id)
                    ThemeEngine.ClearPreviewColorScheme()
                    selectedSchemeId = id
                    showPicker()
                end,
            },

            gui.Button{
                classes = {"sizeM"},
                text = "Cancel",
                halign = "left",
                hmargin = 8,
                click = function()
                    ThemeEngine.ClearPreviewColorScheme()
                    showPicker()
                end,
            },
        }

        bodyPanel.children = { columns, buttonRow }
    end

    bodyPanel = gui.Panel{
        width = "100%",
        height = "100%-80",
        flow = "vertical",
        valign = "top",
    }

    local root = gui.Panel{
        classes = {"launchablePanel"},
        -- Dialog chrome follows the active scheme; the create handler below
        -- re-resolves styles on theme change so the host repaints live.
        styles = ThemeEngine.GetStyles(),
        width = 760,
        height = 640,
        flow = "vertical",
        pad = 16,

        data = {},

        create = function(element)
            element.data.themeSub = ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = ThemeEngine.GetStyles()
                end
            end)
        end,
        destroy = function(element)
            if element.data.themeSub ~= nil then
                element.data.themeSub:Deregister()
                element.data.themeSub = nil
            end
        end,

        gui.Label{
            classes = {"sizeXl", "bold"},
            halign = "center",
            valign = "top",
            width = "auto",
            height = "auto",
            text = "Theme & Color Scheme",
        },
        gui.MCDMDivider{ bmargin = 12 },

        bodyPanel,
    }

    showPicker()
    return root
end
