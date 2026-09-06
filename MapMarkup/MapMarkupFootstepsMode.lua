local mod = dmhub.GetModLoading()

--Map Markup panel: the Footsteps tab builder.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--========================================================================
--Footsteps mode UI: map default dropdown, the fixed surface-family
--palette (with sound previews), paint tools, and the per-floor list.
--========================================================================
--Builds the tab's content panel. Returns {panel, toolPanel, prime}:
--toolPanel is what TakeMarkupFocus re-fires 'think' on, prime is run once
--by CreateMarkupEditor after the whole panel is assembled.
function MM.BuildFootstepsMode()
    local footstepPalettePanel
    local footstepToolsPanel
    local footstepListPanel
    local footstepsPanel
    local footstepDefaultDropdown

    local RefreshFootstepUI = function()
        if footstepsPanel ~= nil and footstepsPanel.valid then
            footstepsPanel:FireEventTree("refreshfootsteps")
        end
    end

    --Grid chip: name at the left, sound-preview play button, then a square
    --color swatch at the right edge - the walls/zones row treatment, kept
    --two per row since surfaces are a short fixed set with no summaries.
    --"50%-2" plus 1px side margins makes each pair span the full content
    --column, so the grid's outer edges line up with the sections above.
    local CreateFootstepChip = function(surfaceInfo)
        return gui.Panel{
            classes = {"markupChip", cond(surfaceInfo.id == m.footstepSelected, "selected")},
            width = "50%-2",
            height = 32,
            flow = "horizontal",
            bgimage = true,
            pad = 4,
            borderBox = true,
            hmargin = 1,
            vmargin = 1,

            data = {
                surfaceid = surfaceInfo.id,
            },

            press = function(element)
                m.footstepSelected = element.data.surfaceid
                footstepPalettePanel:FireEvent("refreshchips")
                --picking a surface must arm the paint tool by itself; see
                --TakeMarkupFocus.
                MM.TakeMarkupFocus()
                --hear what was just selected. The play button still has a
                --job: auditioning a surface WITHOUT changing the selection.
                MM.PlaySurfaceSample(surfaceInfo)
            end,

            --Swatch on the LEFT here, unlike the walls/zones rows: it is the
            --surface's identity mark, like the zone list rows' swatches.
            gui.Panel{
                width = 22,
                height = 22,
                valign = "center",
                bgimage = true,
                bgcolor = MM.SurfaceColor(surfaceInfo.id),
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Label{
                classes = {"bold", "sizeXs"},
                text = surfaceInfo.text,
                width = "100%-50",
                height = "auto",
                hmargin = 4,
                valign = "center",
            },

            gui.Panel{
                --markupToolIcon for the themed icon tint: inline "@token"
                --fields do not resolve (they ship the literal string and
                --render black), only style rules routed through the cascade.
                classes = {"markupToolIcon"},
                width = 16,
                height = 16,
                valign = "center",
                bgimage = "ui-icons/ph-play-fill.png",
                hover = MM.SideTooltip("Preview this footstep sound."),
                press = function()
                    MM.PlaySurfaceSample(surfaceInfo)
                end,
            },
        }
    end

    footstepPalettePanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        wrap = true,

        events = {
            refreshchips = function(element)
                for _,chip in ipairs(element.children) do
                    if chip.data ~= nil and chip.data.surfaceid ~= nil then
                        chip:SetClass("selected", chip.data.surfaceid == m.footstepSelected)
                    end
                end
            end,
        },

        children = (function()
            local chips = {}
            for _,info in ipairs(MM.SurfaceRegistry()) do
                chips[#chips+1] = CreateFootstepChip(info)
            end
            return chips
        end)(),
    }

    local BuildFootstepDefaultOptions = function()
        local options = {
            --0 = no default: tiles keep whatever surface their art carries
            --(Generic where none). Any other choice overrides tile-derived
            --surfaces map-wide; painted footstep regions and water still win.
            { id = "0", text = "None - Use Tile Surfaces" },
        }
        for _,info in ipairs(MM.SurfaceRegistry()) do
            options[#options+1] = { id = tostring(info.id), text = info.text }
        end
        return options
    end

    --Map variations (gs.footstepVariationSetting): when the current floor's
    --map has appearance alternates, the dropdown edits the SELECTED
    --appearance's own default, and the variation panel beneath it shows the
    --map-wide default that appearance falls back to. With a single
    --appearance the dropdown edits the map-wide default directly, as it
    --always has, and the variation panel stays collapsed.
    local FootstepVariationState = function()
        return m.GetFootstepVariationState(game.currentFloorId)
    end

    local MapWideFootstepDefault = function()
        return math.floor(tonumber(gs.footstepDefaultSetting:Get()) or 0)
    end

    --The surface the current variation plays (its override, else the
    --map-wide default) and whether it is an override.
    local EffectiveFootstepDefault = function(state)
        if state ~= nil then
            local override = m.ReadFootstepVariations()[state.key]
            if override ~= nil then
                return override, true
            end
        end
        return MapWideFootstepDefault(), false
    end

    local FootstepSurfaceName = function(surfaceId)
        if surfaceId == 0 then
            return "None - Use Tile Surfaces"
        end
        local info = MM.SurfaceInfoById(surfaceId)
        if info ~= nil and info.text ~= nil then
            return info.text
        end
        return string.format("Surface %d", surfaceId)
    end

    footstepDefaultDropdown = gui.Dropdown{
        width = 200,
        height = 26,
        idChosen = tostring(EffectiveFootstepDefault(FootstepVariationState())),
        options = BuildFootstepDefaultOptions(),
        change = function(element)
            local value = tonumber(element.idChosen) or 0
            local state = FootstepVariationState()
            if state ~= nil then
                --several appearances: the choice is this one's alone.
                local overrides = m.ReadFootstepVariations()
                overrides[state.key] = value
                m.WriteFootstepVariations(overrides)
            else
                gs.footstepDefaultSetting:Set(value)
            end
        end,
    }

    local footstepVariationLabel = gui.Label{
        classes = {"fgMuted", "sizeXs"},
        text = "",
        width = "100%",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        vmargin = 2,
    }

    local footstepMapWideLabel = gui.Label{
        classes = {"sizeXs"},
        text = "",
        width = "100%",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        vmargin = 2,
    }

    local footstepVariationPanel = gui.Panel{
        classes = {"collapsed"},
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",
        vmargin = 2,

        footstepVariationLabel,
        footstepMapWideLabel,

        gui.Panel{
            width = "100%",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            wrap = true,

            gui.Button{
                classes = {"sizeS"},
                text = "Apply to All Variations",
                width = 170,
                halign = "center",
                hmargin = 4,
                vmargin = 2,
                hover = MM.SideTooltip("Make this variation's footstep sound the map-wide default and clear every variation's own setting, so all variations use it."),
                click = function()
                    local state = FootstepVariationState()
                    local value = EffectiveFootstepDefault(state)
                    --clear the overrides first: the map-wide write is what
                    --the monitor refreshes on, and by then both must agree.
                    m.WriteFootstepVariations({})
                    gs.footstepDefaultSetting:Set(value)
                end,
            },

            gui.Button{
                classes = {"sizeS"},
                text = "Use Map Default",
                width = 130,
                halign = "center",
                hmargin = 4,
                vmargin = 2,
                hover = MM.SideTooltip("Drop this variation's own footstep sound so it uses the map-wide default."),
                click = function()
                    local state = FootstepVariationState()
                    if state == nil then
                        return
                    end
                    local overrides = m.ReadFootstepVariations()
                    if overrides[state.key] == nil then
                        return
                    end
                    overrides[state.key] = nil
                    m.WriteFootstepVariations(overrides)
                end,
            },
        },
    }

    local footstepDefaultRow = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        --re-sync on remote changes and on map switches (the map's value is
        --the effective value; the monitor fires for both). The appearance
        --selection lives on the Map object, not in a setting, so the think
        --below polls for it - and for floor switches - the way the footstep
        --list does.
        multimonitor = {"markup:footstepdefault", "markup:footstepvariations"},
        thinkTime = 0.5,

        data = {
            signature = nil,
        },

        events = {
            monitor = function(element)
                element:FireEvent("refreshdefault")
            end,

            think = function(element)
                if m.mode ~= "surfaces" then
                    return
                end
                local state = FootstepVariationState()
                local signature = "none"
                if state ~= nil then
                    signature = string.format("%s|%s|%d", state.objid, state.key, #state.keys)
                end
                if signature ~= element.data.signature then
                    element:FireEvent("refreshdefault")
                end
            end,

            refreshdefault = function(element)
                local state = FootstepVariationState()
                local signature = "none"
                if state ~= nil then
                    signature = string.format("%s|%s|%d", state.objid, state.key, #state.keys)
                end
                element.data.signature = signature

                local effective, isOverride = EffectiveFootstepDefault(state)
                local current = tostring(effective)
                if footstepDefaultDropdown.idChosen ~= current then
                    footstepDefaultDropdown.idChosen = current
                end

                --the block only appears once this variation differs from
                --the map default; a variation that inherits it shows the
                --plain dropdown, as a single-appearance map does.
                local showVariation = state ~= nil and isOverride
                footstepVariationPanel:SetClass("collapsed", not showVariation)
                if showVariation then
                    footstepVariationLabel.text = string.format("The \"%s\" variation has its own footstep sound.", state.name)
                    footstepMapWideLabel.text = string.format("Map default: %s", FootstepSurfaceName(MapWideFootstepDefault()))
                end
            end,
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",

            footstepDefaultDropdown,

            gui.Panel{
                --markupToolIcon for the themed icon tint; see the chip play icon.
                classes = {"markupToolIcon"},
                width = 18,
                height = 18,
                valign = "center",
                hmargin = 8,
                bgimage = "ui-icons/ph-play-fill.png",
                hover = MM.SideTooltip("Preview the default footstep sound."),
                press = function()
                    local defaultSurface = EffectiveFootstepDefault(FootstepVariationState())
                    MM.PlaySurfaceSample(MM.SurfaceInfoById(defaultSurface))
                end,
            },
        },

        footstepVariationPanel,
    }

    --the first refresh: the signature poll fires the rest.
    footstepDefaultRow:FireEvent("refreshdefault")

    --Same icon-over-caption chips as the walls tool strip, with the eraser
    --behind a divider and tinted @danger.
    local BuildFootstepToolButtons = function()
        local result = {}
        local dividerAdded = false
        for _,toolInfo in ipairs(K.FOOTSTEP_TOOLS) do
            local destructive = toolInfo.erase == true
            if destructive and not dividerAdded then
                dividerAdded = true
                result[#result+1] = gui.Panel{
                    classes = {"markupToolDivider"},
                    bgimage = true,
                    width = 1,
                    height = "70%",
                    valign = "center",
                    hmargin = 4,
                    data = {},
                }
            end

            local chipClasses = {"markupToolChip"}
            if toolInfo.id == m.footstepToolId then
                chipClasses[#chipClasses+1] = "selected"
            end
            if destructive then
                chipClasses[#chipClasses+1] = "danger"
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
                hover = MM.SideTooltip(toolInfo.help),
                data = {
                    toolid = toolInfo.id,
                },
                press = function(element)
                    m.footstepToolId = element.data.toolid
                    footstepToolsPanel:FireEvent("refreshfoottools")
                    --focus + immediate tool registration; TakeMarkupFocus
                    --parks focus on contentPanel (chips are transient) and
                    --re-fires this strip's think.
                    MM.TakeMarkupFocus()
                end,

                gui.Panel{
                    classes = {"markupToolIcon", cond(destructive, "danger")},
                    bgimage = toolInfo.icon,
                    width = 18,
                    height = 18,
                    halign = "center",
                    vmargin = 3,
                },

                gui.Label{
                    classes = {"markupToolLabel", cond(destructive, "danger")},
                    text = toolInfo.text or "",
                    width = "100%",
                    height = "auto",
                    textAlignment = "center",
                },
            }
        end
        return result
    end

    footstepToolsPanel = gui.Panel{
        width = "96%",
        height = 48,
        halign = "center",
        flow = "horizontal",

        --keep the custom map tool alive: the engine expires custom tools
        --after ~1s, and every registration returns a fresh event source that
        --must be listened to again.
        thinkTime = 0.3,

        events = {
            refreshfoottools = function(element)
                for _,child in ipairs(element.children) do
                    child:SetClass("selected", child.data.toolid == m.footstepToolId)
                end
            end,

            think = function(element)
                if m.mode ~= "surfaces" or not MM.ZonesSupported() then
                    return
                end

                local toolInfo = MM.FootstepToolById(m.footstepToolId)
                if toolInfo == nil then
                    return
                end

                if not m.arm.Armed() then
                    return
                end

                local eventSource = editor:SetMapTool{
                    tool = toolInfo.mapTool,
                    closed = true,
                    expires = 1,
                    stabilization = 0,
                    snapToGrid = true,
                    --Show the engine's editor cursor dot (where a stroke would
                    --start), like the Building editor's tools do. Older
                    --engines ignore the field.
                    editorCursor = true,
                    --Draw the stroke preview in the erase colour (red) rather
                    --than white: a custom map tool never sets building:erase,
                    --so the engine cannot tell on its own. Display only; older
                    --engines ignore the field.
                    erase = toolInfo.erase == true,
                }
                if eventSource ~= nil then
                    eventSource:Listen(element)
                end
            end,

            tool = function(element, path)
                if m.mode ~= "surfaces" or path == nil then
                    return
                end
                local toolInfo = MM.FootstepToolById(m.footstepToolId)
                if toolInfo == nil then
                    return
                end
                if toolInfo.erase then
                    element:FireEvent("footerase", path)
                else
                    element:FireEvent("footpaint", path)
                end
            end,

            --closed stroke: rasterize to tiles, strip them from every other
            --surface family (exclusive per tile), and merge them into the
            --selected family's one record on this floor.
            footpaint = function(element, path)
                local floor = game.currentFloor
                if floor == nil or not MM.ZonesSupported() then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    if not ok then
                        dmhub.Debug("MARKUP:: surface painting needs an engine build with MapPath points support")
                    end
                    return
                end

                local locs = MM.PolygonToLocs(points)
                if #locs == 0 then
                    return
                end

                if MM.SurfaceInfoById(m.footstepSelected) == nil then
                    dmhub.Debug("MARKUP:: no valid footstep surface selected; stroke ignored")
                    return
                end

                local strokeSet = {}
                for _,l in ipairs(locs) do
                    strokeSet[MM.ZoneLocKey(l.x, l.y)] = true
                end

                local selectedLocs = nil
                local edits = {}
                for _,entry in ipairs(MM.SurfacesOnFloor(floor.floorid)) do
                    if entry.surface == m.footstepSelected then
                        selectedLocs = entry.locs
                    else
                        local kept = {}
                        local removedAny = false
                        for _,l in ipairs(entry.locs) do
                            if strokeSet[MM.ZoneLocKey(l.x, l.y)] then
                                removedAny = true
                            else
                                kept[#kept+1] = { x = l.x, y = l.y }
                            end
                        end
                        if removedAny then
                            edits[#edits+1] = { surface = entry.surface, locs = kept }
                        end
                    end
                end

                local seen = {}
                local newLocs = {}
                local AddLoc = function(x, y)
                    local key = MM.ZoneLocKey(x, y)
                    if not seen[key] then
                        seen[key] = true
                        newLocs[#newLocs+1] = { x = x, y = y }
                    end
                end
                for _,l in ipairs(selectedLocs or {}) do
                    AddLoc(l.x, l.y)
                end
                for _,l in ipairs(locs) do
                    AddLoc(l.x, l.y)
                end

                dmhub.BeginTransaction()
                for _,edit in ipairs(edits) do
                    MM.WriteSurfaceLocs(floor, edit.surface, edit.locs)
                end
                MM.WriteSurfaceLocs(floor, m.footstepSelected, newLocs)
                dmhub.EndTransaction()

                RefreshFootstepUI()
            end,

            --eraser stroke: clear the region's tiles from every surface
            --family on the floor. One undo step per stroke.
            footerase = function(element, path)
                local floor = game.currentFloor
                if floor == nil or not MM.ZonesSupported() then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    return
                end

                local locs = MM.PolygonToLocs(points)
                if #locs == 0 then
                    return
                end

                local remove = {}
                for _,l in ipairs(locs) do
                    remove[MM.ZoneLocKey(l.x, l.y)] = true
                end

                local edits = {}
                for _,entry in ipairs(MM.SurfacesOnFloor(floor.floorid)) do
                    local kept = {}
                    local removedAny = false
                    for _,l in ipairs(entry.locs) do
                        if remove[MM.ZoneLocKey(l.x, l.y)] then
                            removedAny = true
                        else
                            kept[#kept+1] = { x = l.x, y = l.y }
                        end
                    end
                    if removedAny then
                        edits[#edits+1] = { surface = entry.surface, locs = kept }
                    end
                end

                if #edits == 0 then
                    return
                end

                dmhub.BeginTransaction()
                for _,edit in ipairs(edits) do
                    MM.WriteSurfaceLocs(floor, edit.surface, edit.locs)
                end
                dmhub.EndTransaction()

                RefreshFootstepUI()
            end,
        },

        children = BuildFootstepToolButtons(),
    }

    local CreateFootstepRow = function(entry)
        --Same enlarged swatch treatment as the zone rows.
        local rowGradient = m.zoneStripes.Gradient(entry.patternColor, entry.patternAngle)
        local rowSwatchColor = entry.patternColor
        if rowGradient ~= nil then
            rowSwatchColor = "white"
        end

        return gui.Panel{
            classes = {"markupChip"},
            --footstepListPanel is already the 96% content column; fill it.
            width = "100%",
            height = 32,
            halign = "center",
            flow = "horizontal",
            bgimage = true,
            pad = 4,
            borderBox = true,
            vmargin = 1,

            hover = MM.SideTooltip("Click to select this surface and show it on the map. Right-click for options."),

            press = function(element)
                m.footstepSelected = entry.surface
                footstepPalettePanel:FireEvent("refreshchips")
                MM.JumpToZone(entry)
                MM.TakeMarkupFocus()
                --hear what was just selected: the row IS the surface, so the
                --click doubles as the sound preview.
                MM.PlaySurfaceSample(MM.SurfaceInfoById(entry.surface))
            end,

            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Clear From This Floor",
                            click = function()
                                element.popup = nil
                                local floor = game.currentFloor
                                if floor ~= nil then
                                    MM.WriteSurfaceLocs(floor, entry.surface, {})
                                    RefreshFootstepUI()
                                end
                            end,
                        },
                    },
                }
            end,

            gui.Panel{
                width = 24,
                height = 24,
                valign = "center",
                bgimage = true,
                bgcolor = rowSwatchColor,
                gradient = rowGradient,
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Label{
                classes = {"bold", "sizeXs"},
                text = entry.name,
                width = "50%",
                height = "auto",
                hmargin = 4,
                valign = "center",
            },

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = string.format("%d tiles", #entry.locs),
                width = "auto",
                height = "auto",
                valign = "center",
            },
        }
    end

    footstepListPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        --cheap change detection: the records (any client) or the current
        --floor changing rebuilds the list.
        thinkTime = 0.5,

        data = {
            seq = nil,
            floorid = nil,
            popupDeferred = false,
        },

        events = {
            think = function(element)
                if m.mode ~= "surfaces" or not MM.ZonesSupported() then
                    return
                end
                if element.data.popupDeferred or dmhub.markupZonesSeq ~= element.data.seq or game.currentFloorId ~= element.data.floorid then
                    element:FireEvent("refreshfootsteps")
                end
            end,

            refreshfootsteps = function(element)
                if not MM.ZonesSupported() then
                    return
                end

                --a rebuild would destroy the row a context menu hangs off, so
                --stand down and let the think poll above retry once the menu
                --is gone.
                if gui.SubtreeHasPopup(element) then
                    element.data.popupDeferred = true
                    return
                end
                element.data.popupDeferred = false

                element.data.seq = dmhub.markupZonesSeq
                element.data.floorid = game.currentFloorId

                local children = {}
                if element.data.floorid ~= nil then
                    for _,entry in ipairs(MM.SurfacesOnFloor(element.data.floorid)) do
                        children[#children+1] = CreateFootstepRow(entry)
                    end
                end

                if #children == 0 then
                    children[#children+1] = gui.Label{
                        classes = {"fgMuted", "sizeXs"},
                        text = "No footstep surfaces painted on this floor yet. Pick a surface and paint on the map.",
                        width = "90%",
                        height = "auto",
                        halign = "center",
                        vmargin = 4,
                        textAlignment = "center",
                    }
                end

                element.children = children
            end,
        },
    }

    footstepsPanel = gui.Panel{
        classes = {cond(m.mode ~= "surfaces", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        markupmode = function(element)
            element:SetClass("collapsed", m.mode ~= "surfaces")
            if m.mode == "surfaces" then
                footstepPalettePanel:FireEvent("refreshchips")
                footstepListPanel:FireEvent("refreshfootsteps")
            end
        end,

        gui.Label{
            classes = {"fgMuted", cond(MM.ZonesSupported(), "collapsed")},
            text = "Footsteps need an engine build with markup zone support.",
            width = "90%",
            height = "auto",
            halign = "center",
            vmargin = 8,
            textAlignment = "center",
        },

        --Tool first, matching the other tabs: fixed controls at a stable
        --position on top.
        MM.SectionHeader("Tool"),

        footstepToolsPanel,

        MM.SectionHeader("Map Default"),

        footstepDefaultRow,

        gui.Label{
            classes = {"fgMuted", "sizeXs"},
            text = "What this map's ground sounds like, overriding any surface the map's tiles carry. Painted regions override it; water always sounds like water, and flying creatures never make footsteps.",
            width = "94%",
            height = "auto",
            halign = "center",
            vmargin = 2,
        },

        MM.SectionHeader("Paint Surface"),

        footstepPalettePanel,

        MM.SectionHeader("Footsteps on This Floor"),

        footstepListPanel,
    }


    return {
        panel = footstepsPanel,
        toolPanel = footstepToolsPanel,
        prime = function()
            footstepListPanel:FireEvent("refreshfootsteps")
        end,
    }
end
