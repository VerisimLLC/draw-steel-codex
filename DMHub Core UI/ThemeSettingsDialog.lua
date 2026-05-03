local mod = dmhub.GetModLoading()

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

local function buildPreviewBody()
    return {
        gui.Label{
            classes = {"sizeL", "bold"},
            text = "Sample Heading",
        },
        gui.Panel{
            classes = {"formInlineRow"},
            gui.Label{
                classes = {"formInlineLabel"},
                text = "Sample Field:",
            },
            gui.Input{
                classes = {"formInlineControl"},
                text = "type here...",
            },
        },
        gui.Panel{
            classes = {"formInlineRow"},
            gui.Check{
                classes = {"formInlineControl"},
                text = "Enabled",
                value = true,
            },
        },
        gui.Panel{
            classes = {"formInlineRow"},
            gui.Label{
                classes = {"formInlineLabel"},
                text = "Sample Dropdown:",
            },
            gui.Dropdown{
                classes = {"formInlineControl"},
                idChosen = "a",
                options = {
                    { id = "a", text = "Option A" },
                    { id = "b", text = "Option B" },
                    { id = "c", text = "Option C" },
                },
            },
        },
        gui.Panel{
            classes = {"formInlineRow"},
            gui.Label{
                classes = {"formInlineLabel"},
                text = "Sample Tags:",
                valign = "top",
            },
            gui.Multiselect{
                classes = {"formInlineControl"},
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
        gui.Button{
            classes = {"sizeL"},
            halign = "center",
            valign = "bottom",
            text = "Sample Button",
        },
    }
end

CreateThemeSettingsDialog = function()
    -- Pending picker values; start at the user's currently-active selection.
    local selectedThemeId  = ThemeEngine.GetActiveTheme()
    local selectedSchemeId = ThemeEngine.GetActiveColorScheme()

    local previewPanel
    local function refreshPreview()
        previewPanel.styles   = ThemeEngine.GetStyles(selectedThemeId, selectedSchemeId)
        previewPanel.children = buildPreviewBody()
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
                classes = {"formStackedLabel"},
                text = "Theme:",
            },
            gui.Dropdown{
                classes = {"formStackedControl"},
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
                classes = {"formStackedLabel"},
                text = "Color Scheme:",
            },
            gui.Dropdown{
                classes = {"formStackedControl"},
                idChosen = selectedSchemeId,
                options = buildSchemeOptions(),
                change = function(element)
                    selectedSchemeId = element.idChosen
                    refreshPreview()
                end,
            },
        },

        gui.Button{
            classes = {"sizeM"},
            text = "Apply",
            valign = "bottom",
            click = function()
                ThemeEngine.SetActiveTheme(selectedThemeId)
                ThemeEngine.SetActiveColorScheme(selectedSchemeId)
            end,
        },
    }

    return gui.Panel{
        classes = {"launchablePanel"},
        styles = ThemeEngine.GetStyles("default", "default"),
        width = 640,
        height = 480,
        flow = "vertical",
        pad = 16,

        gui.Label{
            classes = {"sizeXl", "bold"},
            halign = "center",
            valign = "top",
            width = "auto",
            height = "auto",
            text = "Theme & Color Scheme",
        },

        pickerRow,
        previewPanel,
    }
end
