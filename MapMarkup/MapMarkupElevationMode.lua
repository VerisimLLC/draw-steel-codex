local mod = dmhub.GetModLoading()

--Map Markup panel: the Elevation tab builder.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--========================================================================
--Elevation mode UI: for now a straight clone of the Elevation Editor dock
--panel (DMHub Core Panels/ElevationPanel.lua). It drives the very same
--"heightmap:*" settings, so the two panels stay in sync automatically;
--what makes painting actually happen from here is the focus-gated
--GetHeightEditingInfo chain in MapMarkupHooks.lua.
--========================================================================

--Every form-style setting in this mode uses the stacked (label-above-
--control) layout, matching the Elevation Editor.
--Builds the tab's content panel. Returns {panel, toolPanel, prime}:
--toolPanel is what TakeMarkupFocus re-fires 'think' on, prime is run once
--by CreateMarkupEditor after the whole panel is assembled.
function MM.BuildElevationMode()
    local elevationStackedOpts = {stacked = true}

    local function SlopeHintVisible()
        local tool = dmhub.GetSettingValue("heightmaptool")
        local toolUsesGradient = tool == "rectangle" or tool == "oval" or tool == "shape"
        return toolUsesGradient and dmhub.GetSettingValue("heightmap:gradient") == "slope"
    end

    --The brush strip is owned by DMHub Core Panels/Brush.lua; that module
    --exports it as a global for us (mod.shared is per-module). rawget: reading
    --an undeclared global errors in the DMHub Lua runtime.
    local elevationBrushPanel = nil
    local brushEditorPanel = rawget(_G, "BrushEditorPanel")
    if brushEditorPanel ~= nil then
        elevationBrushPanel = gui.Panel{
            classes = {cond(dmhub.GetSettingValue("heightmaptool") ~= "brush", "collapsed")},
            width = "auto",
            height = "auto",
            halign = "center",
            monitor = "heightmaptool",
            events = {
                monitor = function(element)
                    element:SetClass("collapsed", dmhub.GetSettingValue("heightmaptool") ~= "brush")
                end,
            },
            brushEditorPanel("heightmapbrush"),
        }
    end

    --The heightmaptool selector as the same icon-over-caption chips the other
    --tabs use, driving the shared setting - the real Elevation Editor stays
    --in sync through its own monitor. Options come from the setting's enum so
    --a new engine tool appears here automatically (with its value as the
    --label until one is curated).
    local ELEVATION_TOOL_LABELS = {
        rectangle = "Rect",
        oval = "Oval",
        shape = "Poly",
        brush = "Brush",
        picker = "Picker",
    }

    local elevationToolsPanel = gui.Panel{
        width = "96%",
        height = 48,
        halign = "center",
        flow = "horizontal",

        monitor = "heightmaptool",

        events = {
            monitor = function(element)
                local current = dmhub.GetSettingValue("heightmaptool")
                for _,child in ipairs(element.children) do
                    child:SetClass("selected", child.data.toolvalue == current)
                end
            end,
        },

        children = (function()
            local result = {}
            local settingInfo = Settings["heightmaptool"]
            local enum = {}
            if settingInfo ~= nil and settingInfo.enum ~= nil then
                enum = settingInfo.enum
            end
            local current = dmhub.GetSettingValue("heightmaptool")
            for _,option in ipairs(enum) do
                local chipClasses = {"markupToolChip"}
                if option.value == current then
                    chipClasses[#chipClasses+1] = "selected"
                end
                result[#result+1] = gui.Panel{
                    classes = chipClasses,
                    width = 44,
                    height = 42,
                    flow = "vertical",
                    bgimage = true,
                    borderBox = true,
                    valign = "center",
                    hmargin = 1,
                    hover = MM.SideTooltip(option.help),
                    data = {
                        toolvalue = option.value,
                    },
                    press = function(element)
                        dmhub.SetSettingValue("heightmaptool", element.data.toolvalue)
                        --focus arms the height-editing poll (the
                        --GetHeightEditingInfo chain is focus-gated).
                        MM.TakeMarkupFocus()
                    end,

                    gui.Panel{
                        classes = {"markupToolIcon"},
                        bgimage = option.icon,
                        width = 18,
                        height = 18,
                        halign = "center",
                        vmargin = 3,
                    },

                    gui.Label{
                        classes = {"markupToolLabel"},
                        text = ELEVATION_TOOL_LABELS[option.value] or option.value,
                        width = "100%",
                        height = "auto",
                        textAlignment = "center",
                    },
                }
            end
            return result
        end)(),
    }

    --The editors themselves, hidden wholesale for non-patrons.
    --Built into an explicit list rather than a table literal: the brush strip
    --is nil when the Brush.lua export is missing, and a nil in the array part
    --of a literal would silently truncate every child after it.
    local elevationChildren = {}
    local AddElevationChild = function(child)
        if child ~= nil then
            elevationChildren[#elevationChildren+1] = child
        end
    end

    AddElevationChild(MM.SectionHeader("Tool"))

    AddElevationChild(elevationToolsPanel)
    AddElevationChild(elevationBrushPanel)
    AddElevationChild(CreateSettingsEditor("heightmap:height", elevationStackedOpts))
    AddElevationChild(CreateSettingsEditor("heightmap:blend", elevationStackedOpts))
    AddElevationChild(CreateSettingsEditor("heightmap:opacity", elevationStackedOpts))
    AddElevationChild(CreateSettingsEditor("heightmap:gradient", elevationStackedOpts))

    AddElevationChild(gui.Label{
        classes = {"fgMuted", cond(not SlopeHintVisible(), "collapsed")},
        text = "Right-click while drawing to change direction",
        width = "90%",
        height = "auto",
        halign = "left",
        textAlignment = "center",
        fontSize = 12,
        italics = true,
        vmargin = 0,
        multimonitor = {"heightmap:gradient", "heightmaptool"},
        monitor = function(element)
            element:SetClass("collapsed", not SlopeHintVisible())
        end,
    })

    --The overlay controls are about READING heights, not painting them, so
    --they get their own section.
    AddElevationChild(MM.SectionHeader("Overlay"))
    AddElevationChild(CreateSettingsEditor("heightmap:overlaytype", elevationStackedOpts))
    AddElevationChild(CreateSettingsEditor("heightmap:opacitysetting", elevationStackedOpts))

    local elevationEditorsPanel = gui.Panel{
        classes = {cond(not MM.ElevationSupported(), "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        children = elevationChildren,
    }

    local elevationPanel = gui.Panel{
        classes = {cond(m.mode ~= "elevation", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        markupmode = function(element)
            element:SetClass("collapsed", m.mode ~= "elevation")
        end,

        gui.Label{
            classes = {"fgMuted", cond(MM.ElevationSupported(), "collapsed")},
            text = "Elevation editing is a patron feature.",
            width = "90%",
            height = "auto",
            halign = "center",
            vmargin = 8,
            textAlignment = "center",
        },

        elevationEditorsPanel,
    }


    return {
        panel = elevationPanel,
    }
end
