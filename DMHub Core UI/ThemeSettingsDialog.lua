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

local function buildThemeOptions()  return buildSortedOptions(ThemeEngine.ListThemes())       end
local function buildSchemeOptions() return buildSortedOptions(ThemeEngine.ListColorSchemes()) end

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
                    width = 360,
                    flow = "horizontal",
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Name" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Class" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Level" },
                },
                gui.Panel{
                    classes = {"row", "evenRow"},
                    width = 360,
                    flow = "horizontal",
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Aldric" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Censor" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "5" },
                },
                gui.Panel{
                    classes = {"row", "oddRow"},
                    width = 360,
                    flow = "horizontal",
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Brenna" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "Tactician" },
                    gui.Label{ classes = {"tableLabel"}, width = "33%", text = "5" },
                },
                gui.Panel{
                    classes = {"row", "evenRow"},
                    width = 360,
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

CreateThemeSettingsDialog = function()
    -- Pending picker values; start at the user's currently-active selection.
    local selectedThemeId  = ThemeEngine.GetActiveTheme()
    local selectedSchemeId = ThemeEngine.GetActiveColorScheme()

    local resultPanel
    local previewPanel

    -- Capture the current preview chrome, swap styles + body underneath, then
    -- crossfade the snapshot away so the change reads as a transition.
    local function refreshPreview()
        -- Defer a frame so the dropdown finishes committing before snapshot.
        dmhub.Schedule(0.02, function()
            if mod.unloaded then return end
            resultPanel:FireEventTree("refreshPreview")
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
        height = "100%-130",
        halign = "center",
        flow = "vertical",
        pad = 12,
        children = buildPreviewBody(),
    }

    local pickerRow = gui.Panel{
        width = "100%",
        height = 70,
        flow = "horizontal",
        valign = "top",

        gui.Panel{
            classes = {"formStackedRow"},
            width = "40%",
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
            width = "40%",
            gui.Label{
                classes = {"formStacked"},
                text = "Color Scheme:",
            },
            gui.Dropdown{
                classes = {"formStacked"},
                idChosen = selectedSchemeId,
                options = buildSchemeOptions(),
                change = function(element)
                    selectedSchemeId = element.idChosen
                    refreshPreview()
                end,
            },
        },

        gui.Button{
            -- Hidden whenever the pending picker selection already equals the
            -- live active selection; refreshPreview event toggles that.
            classes = {"sizeS", "hidden"},
            text = "Apply",
            valign = "top",
            tmargin = 28,

            refreshPreview = function(element)
                element:SetClass("hidden",
                    selectedThemeId  == ThemeEngine.GetActiveTheme() and
                    selectedSchemeId == ThemeEngine.GetActiveColorScheme())
            end,

            press = function(element)
                element:SetClass("hidden", true)
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
    }

    resultPanel = gui.Panel{
        classes = {"launchablePanel"},
        -- Dialog chrome follows the active scheme; the create handler below
        -- re-resolves styles after Apply so the host repaints live.
        styles = ThemeEngine.GetStyles(),
        width = 700,
        height = 600,
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

        pickerRow,
        previewPanel,
    }

    return resultPanel
end
