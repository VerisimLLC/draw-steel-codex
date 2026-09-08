local mod = dmhub.GetModLoading()

--Map Markup panel: the Walls tab builder.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--Walls mode UI: the wall type palette, the shared building-tool strip,
--the thin/solid draw-mode toggle and the wall height stepper.
--Builds the tab's content panel. Returns {panel, toolPanel, prime}:
--toolPanel is what TakeMarkupFocus re-fires 'think' on, prime is run once
--by CreateMarkupEditor after the whole panel is assembled.
function MM.BuildWallsMode()
    local palettePanel
    --forward-declared: the draw-mode toggle rebuilds the tool strip and
    --relabels the height stepper, so it must close over both. SetDrawMode is
    --forward-declared because SelectChip forces thin mode for openable types.
    local toolsPanel
    local drawModePanel
    local heightPanel
    local SelectChip
    local AddPaletteEntry
    local RemovePaletteEntry
    local SetDrawMode

    m.paletteEntries = MM.ParsePalette()
    if m.selectedIndex ~= nil and m.selectedIndex > #m.paletteEntries then
        m.selectedIndex = nil
    end
    if m.selectedIndex == nil and #m.paletteEntries > 0 then
        m.selectedIndex = 1
    end

    --Each mode's default drawing tool is its first: the rectangle, in both.
    --Solid mode's tools are custom map tools, so it leaves the shared
    --building-tool settings alone. Openable (door) types are thin-only.
    if m.solidMode and MM.EntryIsOpenable(m.paletteEntries[m.selectedIndex or 0]) then
        m.solidMode = false
    end
    if m.solidMode then
        m.toolId = "solidrect"
    else
        m.toolId = "rectangle"
        dmhub.SetSettingValue("buildingtool", "rectangle")
        dmhub.SetSettingValue("building:erase", false)
    end

    --Materializes the wall asset behind a preset entry if needed, returning
    --the asset guid or nil.

    local MaterializeEntry = function(entry)
        if entry.guid ~= nil and assets.walls[entry.guid] ~= nil then
            return entry.guid
        end

        local preset = MM.PresetForEntry(entry)
        if preset == nil then
            return nil
        end

        local guid = MM.CreateMarkupWallAsset(preset.name, preset.fields, preset.color)
        if guid == nil then
            return nil
        end

        entry.guid = guid
        MM.SavePalette(m.paletteEntries)
        return guid
    end

    --Arming the panel makes the SELECTED entry real, so the very first stroke
    --on a fresh map's palette draws instead of silently doing nothing - see
    --m.arm.Set for the full story. Assigns no local: this function is close
    --to the 200-locals ceiling.
    m.MaterializeSelectedWall = function()
        local entry = m.paletteEntries[m.selectedIndex or 0]
        if entry == nil or (entry.guid ~= nil and assets.walls[entry.guid] ~= nil) then
            return
        end

        if MaterializeEntry(entry) == nil then
            return
        end

        --the chip draws the asset's line style and color swatches, so it has
        --to repaint now that there is an asset behind it to read them from.
        if palettePanel ~= nil and palettePanel.valid then
            palettePanel:FireEvent("refreshchips")
        end
        if m.markupHud ~= nil and m.markupHud.valid then
            m.markupHud:FireEventTree("refreshwallcolors")
        end
    end

    --Wall colors: 8 distinct colors, drawn as a tiny 4x2 swatch grid ON each
    --palette chip (left of the line preview - see CreateWallChip). The color
    --lives on the wall ASSET (WallAsset.markupColor, engine build required),
    --so every wall of that type on the map - thin skeleton lines and
    --solid-block striping alike - draws in it, on every client. One table
    --rather than several locals: this function is already large and locals
    --are capped at 200 per function.
    local m_wallColor
    m_wallColor = {
        --The first swatch is the engine's stock skeleton grey and CLEARS the
        --stored color instead of writing one, so "no color" stays the
        --engine-default styling rather than pinning a lookalike grey.
        COLORS = {
            { name = "Default", color = "#d9d9d9", default = true },
            { name = "Red", color = "#e5484d" },
            { name = "Orange", color = "#f76b15" },
            { name = "Yellow", color = "#ffc53d" },
            { name = "Green", color = "#46a758" },
            { name = "Cyan", color = "#00a2c7" },
            { name = "Blue", color = "#3e63dd" },
            { name = "Purple", color = "#ab4aba" },
        },

        --Engine gate, same probe recipe as OpenableWallsSupported: reading an
        --unknown property on engine userdata silently returns nil, so check
        --the VALUE. A supporting build returns a string - deliberately ""
        --rather than nil when unset, exactly so this probe works.
        supportCache = nil,
        Supported = function()
            if m_wallColor.supportCache ~= nil then
                return m_wallColor.supportCache
            end
            local probe = assets.walls[K.BASE_INVISIBLE_WALL_ID]
            if probe == nil then
                for _,wall in pairs(assets.walls) do
                    probe = wall
                    break
                end
            end
            if probe == nil then
                --no wall assets at all; leave undecided so we re-probe later.
                return false
            end
            local value = nil
            pcall(function()
                value = probe.markupColor
            end)
            m_wallColor.supportCache = (value ~= nil)
            return m_wallColor.supportCache
        end,

        --the type's stored color ("#rrggbb"), or nil for unset/unmaterialized
        --entries and pre-color engine builds.
        EntryColor = function(entry)
            local asset = MM.EntryWallAsset(entry)
            if asset == nil then
                --a preset chip nobody has drawn with yet has no asset to read
                --from; show the color it WILL materialize with, so a fresh
                --palette is not a column of identical grey lines.
                local preset = MM.PresetForEntry(entry)
                if preset ~= nil then
                    return preset.color
                end
                return nil
            end
            local result = nil
            pcall(function()
                local c = asset.markupColor
                if type(c) == "string" and c ~= "" then
                    result = c
                end
            end)
            return result
        end,

        --writes the chosen swatch onto the entry's wall asset, materializing
        --a preset chip first exactly like selecting it does. Upload syncs the
        --asset, which recolors the type's walls on every client.
        SetEntryColor = function(entry, colorInfo)
            local guid = MaterializeEntry(entry)
            if guid == nil then
                return
            end
            local wall = assets.walls[guid]
            if wall == nil then
                return
            end
            local ok = pcall(function()
                if colorInfo.default then
                    wall.markupColor = ""
                else
                    wall.markupColor = colorInfo.color
                end
            end)
            if ok then
                wall:Upload()
            end
        end,
    }

    SelectChip = function(index)
        local entry = m.paletteEntries[index]
        if entry == nil then
            return
        end

        --The tool strip depends on the SELECTION, not just the draw mode:
        --an openable (door) type gets K.DOOR_TOOLS (the thin strip plus
        --Secret Door). RebuildPalette re-evaluates the strip for palette
        --CONTENT changes, but a plain chip click only refreshes the chips,
        --so the strip kept whatever set it was built with - Secret showed
        --or vanished depending on which chip happened to be selected when
        --the palette last rebuilt. Compare the strip before and after the
        --selection change and rebuild when it differs (SetDrawMode below
        --covers the solid -> thin case on its own).
        local previousTools = MM.ActiveToolInfos()

        m.selectedIndex = index

        local preset = MM.PresetForEntry(entry)
        if preset ~= nil then
            MaterializeEntry(entry)
            MM.SetWallHeightSetting(preset.height)
        end

        --Picking a wall type means "I want to draw this", so the destructive
        --tools don't stay armed on the new type: Eraser / Delete Wall fall
        --back to the active strip's default drawing tool (the rectangle).
        --Secret Door falls back too: it acts on existing doors rather than
        --drawing, and is only offered while a door type is selected.
        --Deliberately only for those - a drawing tool the user chose is
        --their choice and survives changing type.
        local rearmedTool = nil
        if m.toolId == "erase" or m.toolId == "delete" or m.toolId == "secret" then
            local defaultTool = MM.ActiveToolInfos()[1]
            m.toolId = defaultTool.id
            rearmedTool = defaultTool
            --settings first: refreshtools reads buildingtool back to decide
            --which engine drawing tool shows selected.
            if defaultTool.tool ~= nil then
                dmhub.SetSettingValue("building:erase", false)
                dmhub.SetSettingValue("buildingtool", defaultTool.tool)
            end
            if toolsPanel ~= nil and toolsPanel.valid then
                toolsPanel:FireEvent("refreshtools")
            end
        end

        --after the destructive-tool fallback above, so the tool it picked is
        --already valid in the new strip and rebuildtools keeps it.
        if toolsPanel ~= nil and toolsPanel.valid and MM.ActiveToolInfos() ~= previousTools then
            toolsPanel:FireEvent("rebuildtools")
        end

        if palettePanel ~= nil and palettePanel.valid then
            palettePanel:FireEvent("refreshchips")
            --focus + immediate tool registration: in solid mode the tools are
            --custom map tools that only exist while we have focus.
            MM.TakeMarkupFocus()
        end

        --Openable (door) types draw thin walls only: force thin mode so the
        --strokes are real wall operations the engine can attach door state
        --to. SetDrawMode also rebuilds the tool strip and pushes the shared
        --building-tool setting.
        if m.solidMode and MM.EntryIsOpenable(entry) then
            SetDrawMode(false)
        end

        --(A focus steal used to matter here: rearming a thin drawing tool
        --writes the shared building-tool setting, the Building editor's
        --palette re-presses its own chip on the next monitor poll, and the
        --focus TakeMarkupFocus had just taken went with it -- disarming the
        --panel. Arming is explicit now and survives that entirely, so the
        --re-grab is gone.)

        --the selection can flip between openable and plain types, which
        --hides/shows the Draw As toggle. The Wall Color swatches follow the
        --selected type too.
        if m.markupHud ~= nil and m.markupHud.valid then
            m.markupHud:FireEventTree("refreshdoorchip")
            m.markupHud:FireEventTree("refreshwallcolors")
        end
    end

    AddPaletteEntry = function(entry)
        m.paletteEntries[#m.paletteEntries+1] = entry
        m.selectedIndex = #m.paletteEntries
        MM.SavePalette(m.paletteEntries)
        SelectChip(m.selectedIndex)
    end

    RemovePaletteEntry = function(index)
        local removed = m.paletteEntries[index]
        if removed == nil then
            return
        end

        table.remove(m.paletteEntries, index)
        if m.selectedIndex ~= nil then
            if m.selectedIndex == index then
                m.selectedIndex = nil
            elseif m.selectedIndex > index then
                m.selectedIndex = m.selectedIndex - 1
            end
        end
        MM.SavePalette(m.paletteEntries)

        --a map-private type with no walls drawn is orphaned once its chip is
        --gone: delete the asset rather than stranding it in the library.
        if removed.guid ~= nil then
            m.mapScope.DeleteWallIfOrphaned(removed.guid, m.paletteEntries)
        end
    end

    local CreateChipContextMenuItems = function(element, index)
        local entry = m.paletteEntries[index]
        local result = {}

        --library ("wall") chips were deliberately not editable while editing
        --meant mutating the shared asset under other maps; with the scoping
        --engine build, editing a shared wall forks it instead (see
        --ShowMarkupWallDialog), so they become safely editable too.
        local editableKind = entry ~= nil and (entry.kind == "preset" or entry.kind == "solid" or entry.kind == "custom"
            or (entry.kind == "wall" and m.mapScope.WallSupported()))

        if editableKind and entry.guid ~= nil and assets.walls[entry.guid] ~= nil then
            result[#result+1] = {
                text = "Edit Wall...",
                click = function()
                    element.popup = nil
                    MM.ShowMarkupWallDialog(entry.guid, element)
                end,
            }
        end

        result[#result+1] = {
            text = "Remove from Palette",
            click = function()
                element.popup = nil
                RemovePaletteEntry(index)
            end,
        }

        return result
    end

    --A palette row: the name over a one-line summary, then a fixed-width
    --preview of the line the wall draws on the map at the right; one row per
    --type. Text leads because the name is what the user scans for; the
    --preview shows the wall's own behavior (blocks / one-way), which is the
    --same whether it is drawn thin or solid, so it does not vary with the
    --draw mode.
    local CreateWallChip = function(index, entry)
        --the preview line draws in the type's markup color, matching the
        --skeleton the engine draws on the map. nil = the stock grey.
        local wallColor = m_wallColor.EntryColor(entry)

        --the color control rides ON the chip: one larger square showing the
        --type's current color, to the left of the line preview (which
        --narrows to make room). Clicking it pops out the full 4x2 palette
        --to choose from. Engine-gated: on builds without
        --WallAsset.markupColor no square is built and the chip keeps its
        --original full-width layout.
        local colorSwatch = nil
        if m_wallColor.Supported() then
            --the popout: the 4x2 swatch grid the chip used to carry inline.
            --Rebuilt on every open so the ring always marks the type's
            --current color. anchor is the square the popup hangs off.
            local CreatePalettePopout = function(anchor)
                local current = m_wallColor.EntryColor(m.paletteEntries[index])
                local gridRows = {}
                for rowIndex = 0,1 do
                    local swatches = {}
                    for col = 1,4 do
                        local colorInfo = m_wallColor.COLORS[rowIndex*4 + col]
                        --ring the type's current color; Default is lit when
                        --the type has none stored.
                        local selected
                        if current == nil then
                            selected = colorInfo.default == true
                        else
                            selected = (not colorInfo.default) and string.lower(current) == colorInfo.color
                        end
                        swatches[#swatches+1] = gui.Panel{
                            classes = {"markupColorSwatch", cond(selected, "selected")},
                            bgimage = true,
                            bgcolor = colorInfo.color,
                            width = 20,
                            height = 20,
                            borderBox = true,
                            hmargin = 2,
                            vmargin = 2,

                            data = {
                                colorInfo = colorInfo,
                            },

                            press = function(element)
                                anchor.popup = nil
                                local chipEntry = m.paletteEntries[index]
                                if chipEntry == nil then
                                    return
                                end
                                m_wallColor.SetEntryColor(chipEntry, element.data.colorInfo)
                                --picking a color is also picking the type:
                                --select the chip like any press on the row
                                --(this also takes markup focus and fires
                                --refreshwallcolors tree-wide, updating the
                                --squares before the asset-driven rebuild).
                                SelectChip(index)
                            end,
                        }
                    end
                    gridRows[#gridRows+1] = gui.Panel{
                        width = "auto",
                        height = "auto",
                        flow = "horizontal",
                        halign = "center",
                        children = swatches,
                    }
                end
                --popups render in the overlay layer with no style cascade of
                --their own, so re-attach the panel styles explicitly.
                return gui.Panel{
                    styles = MM.GetPanelStyles(),
                    classes = {"framedPanel"},
                    --2 rows / 4 cols of 24px cells (20px swatch + 2px
                    --margins) plus 8px padding each side.
                    width = 112,
                    height = 64,
                    flow = "vertical",
                    pad = 8,
                    borderBox = true,
                    children = gridRows,
                }
            end

            colorSwatch = gui.Panel{
                classes = {"markupColorSwatch"},
                bgimage = true,
                --a single 24px square exactly fills the chip's content
                --height (36 minus 6px borderBox padding each side).
                width = 24,
                height = 24,
                borderBox = true,
                hmargin = 2,
                valign = "center",
                popupPositioning = "panel",

                --presses bubble to ancestors by default, so without this the
                --chip's own press ran too and SELECTED the type - and
                --selecting an unmaterialized preset creates + uploads its wall
                --asset and rewrites the palette setting. Those writes come
                --back as a monitor, the palette rebuilds, and the popout we
                --just opened dies with the square that owns it. Opening the
                --color picker is not "I want to draw this" anyway; picking a
                --color from it selects the type explicitly (see below).
                swallowPress = true,

                events = {
                    create = function(element)
                        element:FireEvent("refreshwallcolors")
                    end,

                    --show the type's current color; Default shows the stock
                    --grey when the type has none stored.
                    refreshwallcolors = function(element)
                        local current = m_wallColor.EntryColor(m.paletteEntries[index])
                        element.selfStyle.bgcolor = current or m_wallColor.COLORS[1].color
                    end,

                    press = function(element)
                        if element.popup ~= nil then
                            element.popup = nil
                            return
                        end
                        element.popup = CreatePalettePopout(element)
                    end,
                },
            }
        end

        local previewWidth = cond(colorSwatch ~= nil, 70, 100)
        local preview
        if MM.EntryIsOpenable(entry) then
            preview = MM.CreateDoorLinePreview(wallColor)
        else
            preview = MM.CreateWallLinePreview(MM.EntryFields(entry), wallColor, colorSwatch ~= nil)
        end

        --Summaries follow a "<behavior> - <cover/extra>" grammar. Rendered as
        --one string the separator lands wherever the first clause ends, which
        --looks ragged stacked in a list - so split at the first " - " and lay
        --the clauses out as two fixed columns; the second clause then starts
        --at the same x on every row and needs no separator at all.
        local summaryA, summaryB = string.match(MM.SummarizeEntry(entry), "^(.-) %- (.*)$")
        if summaryA == nil then
            summaryA = MM.SummarizeEntry(entry)
        end
        local summaryPanel
        if summaryB == nil then
            summaryPanel = gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = summaryA,
                width = "100%",
                height = "auto",
            }
        else
            summaryPanel = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",

                gui.Label{
                    classes = {"fgMuted", "sizeXs"},
                    text = summaryA,
                    width = 76,
                    height = "auto",
                },

                gui.Label{
                    classes = {"fgMuted", "sizeXs"},
                    text = summaryB,
                    width = "100%-76",
                    height = "auto",
                },
            }
        end
        return gui.Panel{
            classes = {"markupChip", cond(index == m.selectedIndex, "selected")},
            --palettePanel is already the panel's 96% content column, so rows
            --fill it entirely; the Add Wall Type row below is a sibling OF
            --that column at 96% itself, and the two must end up equally wide.
            width = "100%",
            height = 36,
            halign = "center",
            flow = "horizontal",
            bgimage = true,
            pad = 6,
            borderBox = true,
            vmargin = 1,

            data = {
                index = index,
            },

            press = function(element)
                SelectChip(element.data.index)
            end,

            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = CreateChipContextMenuItems(element, element.data.index),
                }
            end,

            gui.Panel{
                --the color square + narrowed preview together take the same
                --room the full-width preview did, less the 2px saved by the
                --square being narrower than the old inline grid.
                width = cond(colorSwatch ~= nil, "100%-108", "100%-110"),
                height = "auto",
                valign = "center",
                flow = "vertical",
                hmargin = 4,

                gui.Label{
                    classes = {"bold"},
                    text = MM.EntryDisplayName(entry),
                    width = "100%",
                    height = "auto",
                },

                summaryPanel,
            },

            --square + preview assembled via a children list: colorSwatch is
            --nil on non-supporting engines, and a nil POSITIONAL child would
            --leave a constructor hole that ends ipairs and drops the preview.
            gui.Panel{
                width = cond(colorSwatch ~= nil, 98, 100),
                height = "auto",
                valign = "center",
                flow = "horizontal",
                children = (function()
                    local kids = {}
                    kids[#kids+1] = colorSwatch
                    kids[#kids+1] = gui.Panel{
                        width = previewWidth,
                        height = "auto",
                        valign = "center",
                        flow = "horizontal",
                        preview,
                    }
                    return kids
                end)(),
            },
        }
    end

    --the rebuild proper, split out so refreshpalette can hand it to
    --RebuildDeferringPopups and have it replayed later if a popup is open.
    local RebuildPalette = function(element)
        m.paletteEntries = MM.ParsePalette()
        if m.selectedIndex ~= nil and m.selectedIndex > #m.paletteEntries then
            m.selectedIndex = nil
        end

        local children = {}
        for i,entry in ipairs(m.paletteEntries) do
            children[#children+1] = CreateWallChip(i, entry)
        end
        element.children = children

        --the selected chip can have become openable (Edit Wall on it,
        --or a remote change); openable types are thin-only.
        if m.solidMode and MM.EntryIsOpenable(m.paletteEntries[m.selectedIndex or 0]) and SetDrawMode ~= nil then
            SetDrawMode(false)
        end

        --the selection (and with it the thin-vs-solid tool strip) can
        --change with the palette contents.
        if toolsPanel ~= nil and toolsPanel.valid then
            toolsPanel:FireEvent("rebuildtools")
        end
        if m.markupHud ~= nil and m.markupHud.valid then
            m.markupHud:FireEventTree("refreshdoorchip")
            --a palette change can change which type is selected (and a
            --remote edit can change its color) - resync the swatches.
            m.markupHud:FireEventTree("refreshwallcolors")
        end
    end

    palettePanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        monitorAssets = "Tilesheet",
        multimonitor = {"markup:wallpalette"},

        --gui.RebuildDeferringPopups parks a stood-down rebuild in here.
        data = {},

        events = {
            think = gui.ThinkDeferredRebuild,

            --the palette setting changed: our own write, another DM's, or a
            --map switch changing the effective value.
            monitor = function(element)
                element:FireEvent("refreshpalette")
            end,

            refreshAssets = function(element)
                element:FireEvent("refreshpalette")
            end,

            --replaces every chip, taking any open color popout or chip
            --context menu down with it - so it waits its turn.
            refreshpalette = function(element)
                gui.RebuildDeferringPopups(element, RebuildPalette)
            end,

            refreshchips = function(element)
                for _,chip in ipairs(element.children) do
                    chip:SetClass("selected", chip.data.index == m.selectedIndex)
                end
            end,
        },
    }

    --Styled as one more palette row (full width, chip border) so the list
    --reads as a single column ending in its add action, not a separate button.
    local addButton
    addButton = gui.Panel{
        classes = {"markupChip"},
        width = "96%",
        height = 28,
        halign = "center",
        bgimage = true,
        borderBox = true,
        vmargin = 2,

        gui.Label{
            classes = {"fgMuted"},
            text = "+ Add Wall Type",
            fontSize = 14,
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
        },

        events = {
            press = function(element)
                local entries = {}

                for _,preset in ipairs(K.WALL_PRESETS) do
                    local inPalette = false
                    for _,entry in ipairs(m.paletteEntries) do
                        if entry.kind == "preset" and entry.key == preset.key then
                            inPalette = true
                            break
                        end
                    end

                    if not inPalette then
                        entries[#entries+1] = {
                            text = preset.name,
                            click = function()
                                element.popup = nil
                                AddPaletteEntry{
                                    kind = "preset",
                                    key = preset.key,
                                }
                            end,
                        }
                    end
                end

                entries[#entries+1] = {
                    text = "Door (Openable)",
                    click = function()
                        element.popup = nil
                        --openable lives on the wall asset, which needs the
                        --engine build; refuse with a message rather than
                        --quietly adding a plain wall.
                        if not MM.OpenableWallsSupported() then
                            gui.ModalMessage{
                                owner = element,
                                title = "Door (Openable)",
                                message = "Openable walls need an engine build with door support.",
                            }
                            return
                        end
                        local guid = MM.CreateMarkupWallAsset("Door", K.DOOR_TYPE_FIELDS)
                        if guid ~= nil then
                            AddPaletteEntry{
                                kind = "custom",
                                guid = guid,
                            }
                        end
                    end,
                }

                entries[#entries+1] = {
                    text = "Other Invisible Walls...",
                    click = function()
                        element.popup = nil
                        element:FireEvent("showlibrary")
                    end,
                }

                entries[#entries+1] = {
                    text = "Custom...",
                    click = function()
                        element.popup = nil
                        local guid = MM.CreateMarkupWallAsset("Custom Markup Wall", K.WALL_PRESETS_BY_KEY["stone"].fields)
                        if guid ~= nil then
                            AddPaletteEntry{
                                kind = "custom",
                                guid = guid,
                            }
                            MM.ShowMarkupWallDialog(guid, element)
                        end
                    end,
                }

                element.popup = gui.ContextMenu{
                    entries = entries,
                }
            end,

            showlibrary = function(element)
                --closes via the captured layer; shown owner-routed so a
                --popped-out Map Markup gets the dialog in its own window.
                local modalLayer = nil
                --Markup is invisible-walls-only: visible art walls belong to
                --the Building editor. Also skip walls already in the palette.
                local paletteGuids = {}
                for _,entry in ipairs(m.paletteEntries) do
                    if entry.guid ~= nil then
                        paletteGuids[entry.guid] = true
                    end
                end

                local sortedWalls = {}
                for id,wall in pairs(assets.walls) do
                    --wall types private to other maps never appear here.
                    if (not wall.hidden) and wall.invisible == true and (not paletteGuids[id]) and m.mapScope.WallAvailableOnThisMap(wall) then
                        sortedWalls[#sortedWalls+1] = {
                            id = id,
                            wall = wall,
                        }
                    end
                end
                table.sort(sortedWalls, function(a, b)
                    local aname = a.wall.description or a.id
                    local bname = b.wall.description or b.id
                    return aname < bname or (aname == bname and a.id < b.id)
                end)

                local rows = {}
                for _,info in ipairs(sortedWalls) do
                    rows[#rows+1] = gui.Panel{
                        classes = {"markupChip"},
                        width = "96%",
                        height = 32,
                        halign = "center",
                        flow = "horizontal",
                        bgimage = true,
                        pad = 4,
                        borderBox = true,
                        vmargin = 1,

                        data = {
                            wallid = info.id,
                        },

                        press = function(rowElement)
                            AddPaletteEntry{
                                kind = "wall",
                                guid = rowElement.data.wallid,
                            }
                            gui.CloseModalInLayer(modalLayer)
                        end,

                        gui.Panel{
                            width = 110,
                            height = "100%",
                            valign = "center",
                            flow = "horizontal",
                            MM.CreateWallLinePreview(MM.AssetFields(info.wall)),
                        },

                        gui.Label{
                            text = info.wall.description or info.id,
                            width = "auto",
                            height = "auto",
                            hmargin = 8,
                            valign = "center",
                        },
                    }
                end

                if #rows == 0 then
                    rows[#rows+1] = gui.Label{
                        classes = {"fgMuted"},
                        text = "No other invisible wall types in this game.",
                        width = "90%",
                        height = "auto",
                        halign = "center",
                        vmargin = 12,
                        textAlignment = "center",
                    }
                end

                local dialogPanel = gui.Panel{
                    id = "MarkupWallLibraryDialog",
                    classes = {"framedPanel"},
                    --clamped to the modal layer: full design size in the
                    --main window, shrink-to-fit inside a small popout.
                    width = "94%",
                    maxWidth = 440,
                    height = "92%",
                    maxHeight = 620,
                    pad = 16,
                    borderBox = true,
                    flow = "vertical",
                    styles = ThemeEngine.MergeStyles{
                        Styles.Panel,
                        MM.MarkupChipStyles(),
                    },

                    gui.Label{
                        classes = {"dialogTitle"},
                        text = "Add Invisible Wall",
                    },

                    gui.Panel{
                        width = "100%",
                        height = "100%-100",
                        vscroll = true,
                        flow = "vertical",
                        children = rows,
                    },

                    gui.Button{
                        classes = {"sizeM"},
                        text = "Cancel",
                        halign = "center",
                        valign = "bottom",
                        vmargin = 8,
                        captureEscape = true,
                        escapePriority = EscapePriority.EXIT_DIALOG,
                        events = {
                            click = function(buttonElement)
                                buttonElement:FireEvent("escape")
                            end,
                            escape = function()
                                gui.CloseModalInLayer(modalLayer)
                            end,
                        },
                    },
                }

                modalLayer = gui.ShowModal(dialogPanel, {owner = element})
            end,
        },
    }

    --Tool selection strip: icon buttons in the same style the settings
    --system's iconbuttons editor uses (SettingsGui.lua). Thin-wall drawing
    --tools write the shared engine building-tool settings; solid drawing
    --tools, erase and delete run as custom map tools kept alive by this
    --panel's think loop, with their strokes coming back as 'tool' events.
    --The strip's buttons are rebuilt when the selected chip flips between
    --thin and solid (rebuildtools).
    --Each tool is an icon-over-caption chip; the destructive pair (erase /
    --delete) sits behind a divider and is tinted @danger, so a misclick
    --cannot silently turn a drawing gesture into a removal.
    local BuildToolButtons = function()
        local result = {}
        local dividerAdded = false
        for _,toolInfo in ipairs(MM.ActiveToolInfos()) do
            local destructive = toolInfo.id == "erase" or toolInfo.id == "delete"
            if destructive and not dividerAdded then
                dividerAdded = true
                result[#result+1] = gui.Panel{
                    classes = {"markupToolDivider"},
                    bgimage = true,
                    width = 1,
                    height = "70%",
                    valign = "center",
                    hmargin = 4,
                    --refreshtools iterates children by data.toolid; give the
                    --divider an empty data table so it reads as "no tool".
                    data = {},
                }
            end

            local chipClasses = {"markupToolChip"}
            if toolInfo.id == m.toolId then
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
                    tool = toolInfo.tool,
                },
                press = function(element)
                    --Pressing a tool ALWAYS arms it, including the one
                    --already live. Deliberately not a toggle: a button that
                    --disarms on its second press makes pressing your current
                    --tool a coin flip between "keep drawing" and "stop", and
                    --a mis-aimed re-press silently puts the panel down.
                    --Escape is the way out.
                    m.toolId = element.data.toolid
                    if element.data.tool ~= nil then
                        dmhub.SetSettingValue("building:erase", false)
                        dmhub.SetSettingValue("buildingtool", element.data.tool)
                    end
                    toolsPanel:FireEvent("refreshtools")
                    --ARM. This is the whole state now: it survives whatever
                    --happens to focus afterwards, so the Building editor's
                    --palette stealing focus a frame later (the reason
                    --ReassertMarkupFocus existed) no longer stops drawing.
                    m.arm.Set(true)
                    --Focus is still taken, but only so the panel keeps its
                    --keyboard routing -- it no longer decides anything. Still
                    --on contentPanel rather than this button: the strip is
                    --rebuilt wholesale by rebuildtools and focus parked on a
                    --destroyed button goes nil.
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

    toolsPanel = gui.Panel{
        width = "96%",
        height = 48,
        halign = "center",
        flow = "horizontal",

        multimonitor = {"buildingtool", "building:erase"},

        --keep the custom map tool alive while erase/delete is active. The
        --engine expires custom tools after ~1s, so this must re-register
        --faster than that; each registration returns a fresh event source
        --that has to be listened to again.
        thinkTime = 0.3,

        events = {
            monitor = function(element)
                element:FireEvent("refreshtools")
            end,

            refreshtools = function(element)
                --custom map tools (erase, delete, the solid shape tools) are
                --owned by this panel outright; engine drawing tools reflect
                --the shared building-tool settings, so if the Building editor
                --switched the shape (or turned its erase checkbox on) no
                --markup chip shows selected.
                local tools = MM.ActiveToolInfos()
                local activeInfo = nil
                for _,toolInfo in ipairs(tools) do
                    if toolInfo.id == m.toolId then
                        activeInfo = toolInfo
                    end
                end

                local activeid = m.toolId
                if activeInfo == nil or activeInfo.mapTool == nil then
                    activeid = nil
                    if not dmhub.GetSettingValue("building:erase") then
                        local tool = dmhub.GetSettingValue("buildingtool")
                        for _,toolInfo in ipairs(tools) do
                            if toolInfo.tool == tool then
                                activeid = toolInfo.id
                            end
                        end
                    end
                end

                --A tool lights ONLY while the panel is armed. Disarmed, the
                --whole strip goes dark: "nothing here is live right now" is
                --the thing the user could not tell before, and showing a lit
                --tool that does nothing when you click the map is precisely
                --the lie this rework is removing. Pressing any tool (the same
                --one included) arms it again.
                local armed = m.arm.Armed()
                for _,child in ipairs(element.children) do
                    child:SetClass("selected", armed and child.data.toolid == activeid)
                end
            end,

            --the selected chip flipped between thin and solid (or the palette
            --changed under us): swap the button set for the matching tool
            --strip. If the active tool doesn't exist in the new strip, fall
            --back to its default drawing tool - without touching the shared
            --building-tool settings, since this can fire from a remote
            --palette change while the Building editor is in use.
            rebuildtools = function(element)
                local tools = MM.ActiveToolInfos()

                local validTool = false
                for _,toolInfo in ipairs(tools) do
                    if toolInfo.id == m.toolId then
                        validTool = true
                    end
                end

                if not validTool then
                    --carry the equivalent shape across the mode switch (rect stays
                    --rect, polygon stays polygon) so only the strip changes, not the
                    --user's choice; otherwise fall back to the first tool.
                    local outgoing = MM.FindToolInfo(m.toolId)
                    local wantShape = nil
                    if outgoing ~= nil then
                        wantShape = outgoing.shape
                    end

                    m.toolId = nil
                    if wantShape ~= nil then
                        for _,toolInfo in ipairs(tools) do
                            if toolInfo.shape == wantShape then
                                m.toolId = toolInfo.id
                            end
                        end
                    end
                    if m.toolId == nil then
                        m.toolId = tools[1].id
                    end
                end

                element.children = BuildToolButtons()
                element:FireEvent("refreshtools")
            end,

            think = function(element)
                --The Delete, Apply Type (retype) and Secret Door tools take
                --map focus so they get maphover/mappress (hover-highlight +
                --click-on-one-segment / one-door). Own map focus only while
                --one of them is the active markup tool and this panel is
                --focused; release it and drop any highlight otherwise. Gating
                --on focus keeps us from stealing map focus from ability
                --targeting etc. This runs before the m.mode guard so
                --switching mode/tool tears the overlay down promptly.
                local wantDelete = m.mode == "walls"
                    and (m.toolId == "delete" or m.toolId == "retype" or m.toolId == "secret")
                    and m.arm.Armed()

                if wantDelete then
                    if not element.mapfocus then
                        element.mapfocus = true
                    end
                else
                    if element.mapfocus then
                        element.mapfocus = false
                    end
                    MM.ClearDeleteHighlight()
                    m.mapScope.retypeAnchor = nil
                end

                if m.mode ~= "walls" then
                    return
                end

                local toolInfo = nil
                for _,t in ipairs(MM.ActiveToolInfos()) do
                    if t.id == m.toolId and t.mapTool ~= nil then
                        toolInfo = t
                    end
                end
                if toolInfo == nil then
                    return
                end

                if not m.arm.Armed() then
                    return
                end

                --Both erase (rectangle) and delete (the inert "markupdelete"
                --sentinel) keep a custom map tool alive purely so the engine
                --leaves the wall skeleton overlay up (wallSkeletons) - the user
                --needs to see the walls they are removing. The sentinel captures
                --no drawing; delete's real input arrives via map focus.
                local eventSource = editor:SetMapTool{
                    tool = toolInfo.mapTool,
                    closed = toolInfo.mapToolClosed,
                    expires = 1,
                    stabilization = 0,
                    wallSkeletons = true,
                    --These tools draw/erase MAP GEOMETRY, so they snap like the
                    --building tools (and honor ctrl to invert). Without it a
                    --custom tool falls through to the separate OBJECT snap
                    --setting, since it publishes no wall selection -- which is
                    --why solid blocks did not snap while thin walls did.
                    --Needs an engine build; older engines ignore the field.
                    --NOT for Apply Type: its rectangle is an edge-SELECTION
                    --gesture, and a snapped border landing exactly on a tile
                    --boundary would catch every wall lying on that boundary -
                    --a free rect lets the user offset slightly to include or
                    --exclude a boundary wall unambiguously.
                    snapToGrid = toolInfo.id ~= "retype",
                    --Show the engine's editor cursor dot (where a stroke would
                    --start), like the Building editor's tools do. Not for the
                    --Delete / Secret Door sentinels: they highlight the hovered
                    --wall segment / door instead, and a dot would suggest
                    --drawing. Older engines ignore the field.
                    editorCursor = toolInfo.id ~= "delete" and toolInfo.id ~= "secret",
                    --Draw the stroke preview in the erase colour (red) rather
                    --than white. A custom map tool's stroke comes back to us
                    --as a 'tool' event instead of going through the engine's
                    --building-operation path, so it never sets building:erase
                    --and the engine cannot tell on its own that we are about
                    --to erase. Display only; older engines ignore the field.
                    erase = toolInfo.erase == true,
                }
                if eventSource ~= nil then
                    eventSource:Listen(element)
                end
            end,

            tool = function(element, path)
                if m.mode ~= "walls" or path == nil then
                    return
                end
                --Erase (rectangle) and the solid shape tools deliver strokes.
                --Delete's sentinel map tool captures nothing; its input
                --arrives via maphover/mappress.
                if m.toolId == "erase" then
                    element:FireEvent("markuperase", path)
                elseif m.toolId == "retype" then
                    element:FireEvent("markupretype", path)
                elseif m.toolId == "solidrect" or m.toolId == "solidpoly" or m.toolId == "solidfree" then
                    element:FireEvent("markupsolid", path)
                end
            end,

            --Apply Type rectangle stroke: convert every markup wall edge the
            --rectangle touches to the selected type, at edge granularity. A
            --degenerate (click-sized) stroke routes to the single-edge click
            --path instead - whether a plain click arrives here, via mappress,
            --or both depends on how the engine arbitrates the live rectangle
            --tool against map focus, and all three are safe (see K.TOOL_RETYPE).
            markupretype = function(element, path)
                --the marquee (or click) is over: drop the drag anchor and the
                --live preview before applying.
                m.mapScope.retypeAnchor = nil
                MM.ClearDeleteHighlight()

                local floor = game.currentFloor
                if floor == nil then
                    return
                end
                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 4 then
                    if not ok then
                        dmhub.Debug("MARKUP:: Apply Type needs an engine build with MapPath points support")
                    end
                    return
                end

                local minx, miny = points[1], points[2]
                local maxx, maxy = points[1], points[2]
                for i = 1, #points - 1, 2 do
                    local x, y = points[i], points[i+1]
                    if x < minx then minx = x end
                    if x > maxx then maxx = x end
                    if y < miny then miny = y end
                    if y > maxy then maxy = y end
                end

                if (maxx - minx) < 0.12 and (maxy - miny) < 0.12 then
                    --a click, not a marquee. FindNearestDeleteSegment matches
                    --atMouse (the cursor is still at the release point), so
                    --the passed point only feeds older-engine fallbacks.
                    element:FireEvent("markupretypeclick", { x = (minx + maxx)*0.5, y = (miny + maxy)*0.5 })
                    return
                end

                local entry = m.paletteEntries[m.selectedIndex or 0]
                if entry == nil then
                    return
                end
                local guid = MaterializeEntry(entry)
                if guid == nil then
                    return
                end

                local okCall = pcall(function()
                    floor:RetypeWallEdges{
                        wallid = guid,
                        rect = { minx, miny, maxx, maxy },
                    }
                end)
                if not okCall then
                    dmhub.Debug("MARKUP:: Apply Type needs an engine build with RetypeWallEdges support")
                end
            end,

            --Apply Type click: convert the WHOLE drawn operation under the
            --cursor to the selected palette type (segment mode retypes every
            --op with an edge coincident with the touched one). Reached from
            --mappress AND from a degenerate rectangle stroke; double delivery
            --is harmless because RetypeWallEdges skips ops already of the
            --target type.
            markupretypeclick = function(element, point)
                local floor = game.currentFloor
                if floor == nil then
                    return
                end
                local seg = MM.FindNearestDeleteSegment(point)
                if seg == nil then
                    return
                end
                local entry = m.paletteEntries[m.selectedIndex or 0]
                if entry == nil then
                    return
                end
                local guid = MaterializeEntry(entry)
                if guid == nil then
                    return
                end
                local okCall = pcall(function()
                    floor:RetypeWallEdges{
                        wallid = guid,
                        segment = { seg.a.x, seg.a.y, seg.b.x, seg.b.y },
                    }
                end)
                if not okCall then
                    dmhub.Debug("MARKUP:: Apply Type needs an engine build with RetypeWallEdges support")
                    return
                end
                --the highlighted edge just changed type; recompute on the
                --next hover so the tint follows the new state.
                MM.ClearDeleteHighlight()
            end,

            --rectangle stroke: erase every invisible wall - and, on engine
            --builds that support it, every invisible solid block - in the
            --region.
            markuperase = function(element, path)
                local floor = game.currentFloor
                if floor == nil then
                    return
                end

                --path.points needs the engine half of this feature; guard so
                --a stale engine build logs instead of erroring.
                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 4 then
                    if not ok then
                        dmhub.Debug("MARKUP:: eraser needs an engine build with MapPath points support")
                    end
                    return
                end

                --floor=true routes the op through the floor-erase path, which
                --carves markup solid blocks; the engine only honors
                --eraseInvisibleOnly there on builds with the solid support, so
                --older engines keep the walls-only op (a type-blind floor
                --erase would destroy art). One op = one undo step.
                local okSupport, supportsSolids = pcall(function()
                    return floor.supportsSolidOperations
                end)
                local carveSolids = okSupport and supportsSolids == true

                floor:ExecutePolygonOperation{
                    points = {points},
                    erase = true,
                    eraseInvisibleOnly = true,
                    walls = true,
                    floor = carveSolids,
                    closed = path.closed,
                }
            end,

            --closed solid stroke: fill the region with an invisible solid
            --block of the selected solid wall type, at the height stepper's
            --height (blank/To Roof = 0 = floor-to-ceiling, no standable top).
            markupsolid = function(element, path)
                local floor = game.currentFloor
                if floor == nil then
                    return
                end

                local entry = m.paletteEntries[m.selectedIndex or 0]
                if entry == nil or not m.solidMode then
                    return
                end

                --Engine gate: a stale engine ignores solid=true and would
                --draw a plain (invisible) floor over the map's ground tiles
                --instead - visually silent but destructive. The probe
                --property only exists on builds with the passthrough.
                local okSupport, supportsSolids = pcall(function()
                    return floor.supportsSolidOperations
                end)
                if not okSupport or supportsSolids ~= true then
                    dmhub.Debug("MARKUP:: solid walls need an engine build with ExecutePolygonOperation solid support")
                    return
                end

                if assets.tilesheets[K.INVISIBLE_TILESHEET_ID] == nil then
                    dmhub.Debug("MARKUP:: the Core invisible tilesheet is not available in this game")
                    return
                end

                local guid = MaterializeEntry(entry)
                if guid == nil then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    return
                end

                local height = MM.GetWallHeightSetting()

                floor:ExecutePolygonOperation{
                    points = {points},
                    wallid = guid,
                    tileid = K.INVISIBLE_TILESHEET_ID,
                    wallheight = math.floor((height or 0) + 0.5),
                    solid = true,
                    walls = true,
                    floor = true,
                    closed = true,
                }
            end,

            --Delete / Apply Type hover previews, tinted delete red for Delete
            --and the TARGET type's color for Apply Type (the hover literally
            --shows what will change):
            --  Delete            - the single segment a click clears.
            --  Apply Type hover  - the WHOLE wall under the cursor (a click
            --                      retypes the entire drawn operation).
            --  Apply Type drag   - the edges the current marquee rect would
            --                      convert, live as the rect grows.
            maphover = function(element, loc, point)
                if m.mode ~= "walls" or (m.toolId ~= "delete" and m.toolId ~= "retype" and m.toolId ~= "secret") then
                    MM.ClearDeleteHighlight()
                    return
                end

                --Secret Door hover: the WHOLE door under the cursor - violet
                --when a click will make it secret, plain when it will reveal
                --it (the tint shows the state the click produces, the same
                --honesty rule as the Delete / Apply Type previews).
                if m.toolId == "secret" then
                    local hit = MM.FindDoorAtPoint(point)
                    if hit == nil then
                        MM.ClearDeleteHighlight()
                        return
                    end
                    m.mapScope.ShowSegmentsHighlight(hit.segments, cond(hit.door.secret, "#e0e0e0", K.SECRET_DOOR_COLOR))
                    return
                end

                if m.toolId == "retype" then
                    local entry = m.paletteEntries[m.selectedIndex or 0]
                    local color = m_wallColor.EntryColor(entry) or "#4da6ff"

                    --marquee-in-progress: while the left button is held, the
                    --press point (or, when the press was swallowed by the
                    --live rectangle tool, the first held-button hover)
                    --anchors the rect and the captured edges highlight live.
                    if element:GetMouseButton(0) then
                        local anchor = m.mapScope.retypeAnchor
                        if anchor == nil and point ~= nil then
                            anchor = { x = point.x, y = point.y }
                            m.mapScope.retypeAnchor = anchor
                        end
                        if anchor ~= nil and point ~= nil
                            and (math.abs(point.x - anchor.x) >= 0.12 or math.abs(point.y - anchor.y) >= 0.12) then
                            local floor = game.currentFloor
                            local segments = nil
                            if floor ~= nil then
                                pcall(function()
                                    segments = floor:GetWallEdgesInRect{
                                        rect = { anchor.x, anchor.y, point.x, point.y },
                                        --edges already of the target type are
                                        --omitted, matching what the retype
                                        --will skip. nil for unmaterialized
                                        --presets (no exclusion).
                                        wallid = entry ~= nil and entry.guid or nil,
                                    }
                                end)
                            end
                            m.mapScope.ShowSegmentsHighlight(segments or {}, color)
                            return
                        end
                    else
                        m.mapScope.retypeAnchor = nil
                    end

                    local seg = MM.FindNearestDeleteSegment(point)
                    if seg == nil then
                        MM.ClearDeleteHighlight()
                        return
                    end
                    --a click converts the whole drawn operation, so preview
                    --the whole wall path under the cursor. The derived wall
                    --is the visual unit the user is pointing at; a merged or
                    --multi-path operation can differ slightly, but this is
                    --the honest approximation available without op access.
                    local pts = seg.points
                    if pts ~= nil and #pts >= 4 then
                        local segments = {}
                        for i = 1, #pts - 3, 2 do
                            segments[#segments+1] = pts[i]
                            segments[#segments+1] = pts[i+1]
                            segments[#segments+1] = pts[i+2]
                            segments[#segments+1] = pts[i+3]
                        end
                        m.mapScope.ShowSegmentsHighlight(segments, color)
                    else
                        MM.ShowDeleteHighlight(seg, color)
                    end
                    return
                end

                local seg = MM.FindNearestDeleteSegment(point)
                if seg == nil then
                    MM.ClearDeleteHighlight()
                    return
                end
                --highlight the span that will actually be cleared (>= the
                --touched edge on short segments) so the preview is honest.
                MM.ShowDeleteHighlight(MM.DeleteSegmentGeometry(seg))
            end,

            --Delete tool click: clear just the segment under the cursor (or the
            --minimum stable span around it - see DeleteSegmentGeometry), leaving
            --the rest of the wall intact, instead of wiping the whole wall.
            --Apply Type routes its click to the shared single-edge handler.
            mappress = function(element, loc, point)
                if m.mode ~= "walls" then
                    return
                end
                if m.toolId == "retype" then
                    --the press anchors a potential marquee (maphover shows
                    --the live rect's captured edges while the button stays
                    --down) and, when it lands on a wall, converts that whole
                    --drawn operation immediately.
                    if point ~= nil then
                        m.mapScope.retypeAnchor = { x = point.x, y = point.y }
                    end
                    element:FireEvent("markupretypeclick", point)
                    return
                end
                if m.toolId == "secret" then
                    --Secret Door click: toggle doorSecret on the door under
                    --the cursor. SetDoorState swaps the op in under a new id
                    --(the door icon's own pattern), so undo and every
                    --client's wall rebuild come for free.
                    local floor = game.currentFloor
                    local hit = MM.FindDoorAtPoint(point)
                    if floor == nil or hit == nil then
                        return
                    end
                    floor:SetDoorState{
                        layer = hit.door.layer,
                        opid = hit.door.opid,
                        secret = not hit.door.secret,
                    }
                    --the op id just changed; drop the highlight so the next
                    --hover recomputes against the new state.
                    MM.ClearDeleteHighlight()
                    return
                end
                if m.toolId ~= "delete" then
                    return
                end
                local floor = game.currentFloor
                if floor == nil then
                    return
                end
                local seg = MM.FindNearestDeleteSegment(point)
                if seg == nil then
                    return
                end

                --Erase a closed box straddling the segment (see
                --DeleteSegmentGeometry): stable on short segments where a
                --hair-thin centerline erase either did nothing or got healed
                --straight back by the wall auto-merge.
                local geom = MM.DeleteSegmentGeometry(seg)
                floor:ExecutePolygonOperation{
                    points = { geom.box },
                    erase = true,
                    eraseInvisibleOnly = true,
                    walls = true,
                    floor = false,
                    closed = true,
                }

                --the highlighted segment is gone now; drop the marker so the
                --next hover recomputes against the updated walls.
                MM.ClearDeleteHighlight()
            end,

            --Release map focus and clear any highlight if the panel goes away
            --while the Delete tool is active.
            destroy = function(element)
                if element.mapfocus then
                    element.mapfocus = false
                end
                MM.ClearDeleteHighlight()
            end,
        },

        children = BuildToolButtons(),
    }

    --Draw-mode toggle: the SAME selected wall type can be drawn either as a
    --thin barrier on a tile boundary or as an area-filling solid block. Sits
    --directly under the tool strip because it changes which tools are shown.
    --(Forward-declared at the top of CreateMarkupEditor.)
    SetDrawMode = function(solid)
        if m.solidMode == solid then
            return
        end
        m.solidMode = solid

        --swaps the tool strip and, if the active tool has no counterpart in
        --the new mode, falls back to that mode's default drawing tool.
        if toolsPanel ~= nil and toolsPanel.valid then
            toolsPanel:FireEvent("rebuildtools")
        end

        --Thin mode's drawing tools ARE the engine building tools, so the
        --shared setting has to be pushed when we land on one. (rebuildtools
        --deliberately never writes settings - it also fires on remote palette
        --changes, where stealing the Building editor's tool would be rude.)
        if not m.solidMode then
            for _,toolInfo in ipairs(MM.ActiveToolInfos()) do
                if toolInfo.id == m.toolId and toolInfo.tool ~= nil then
                    dmhub.SetSettingValue("building:erase", false)
                    dmhub.SetSettingValue("buildingtool", toolInfo.tool)
                end
            end
        end

        if drawModePanel ~= nil and drawModePanel.valid then
            drawModePanel:FireEventTree("refreshdrawmode")
        end
        --the stepper is labelled Wall Height / Block Height by mode.
        if heightPanel ~= nil and heightPanel.valid then
            heightPanel:FireEventTree("refreshheight")
        end

        --Solid mode draws with custom map tools that expire after ~1s;
        --register immediately instead of waiting for the think tick.
        if toolsPanel ~= nil and toolsPanel.valid then
            toolsPanel:FireEvent("think")
        end
        --(No focus re-grab here any more. Landing on thin mode writes
        --buildingtool, which used to make the Building editor's palette
        --refocus its own chip and disarm this panel; explicit arming is
        --immune to that.)
    end

    local CreateDrawModeChip = function(solid)
        --NOT cond(): it evaluates both arguments, which would build an orphan
        --gui.Panel every time this chip is created.
        local preview
        if solid then
            preview = MM.CreateSolidBlockPreview()
        else
            preview = MM.CreateWallLinePreview(nil)
        end

        return gui.Panel{
            classes = {"markupChip", cond(m.solidMode == solid, "selected")},
            --the pair plus the 4px spacer between them spans the full 96%
            --content column, so the toggle's outer edges line up with the
            --palette rows and the Add Wall Type row above.
            width = "50%-2",
            height = "100%",
            flow = "vertical",
            bgimage = true,
            pad = 4,
            borderBox = true,

            data = {
                solid = solid,
            },

            press = function(element)
                --focus first: SetDrawMode registers the custom map tool, and
                --the think handler that does it is focus-gated. On
                --contentPanel rather than this chip, per TakeMarkupFocus.
                MM.TakeMarkupFocus()
                SetDrawMode(element.data.solid)
            end,

            refreshdrawmode = function(element)
                element:SetClass("selected", m.solidMode == element.data.solid)
            end,

            gui.Label{
                classes = {"sizeXs"},
                text = cond(solid, "Solid Block", "Thin Wall"),
                width = "100%",
                height = "auto",
                textAlignment = "center",
                vmargin = 2,
            },

            --the same miniatures the palette uses, so the difference between
            --a line and a filled region is visible rather than just named.
            --Below the name, mirroring the palette rows' text-then-visual.
            preview,
        }
    end

    drawModePanel = gui.Panel{
        width = "96%",
        height = 40,
        halign = "center",
        flow = "horizontal",
        vmargin = 2,

        hover = MM.SideTooltip("Thin Wall draws a barrier along the line you trace. Solid Block fills the area you draw with volume: it has a height, can be stood on and climbed, and blocks sight up to its height. Both use the wall type selected above."),

        --openable (door) types are thin-only (their strokes must be wall
        --operations the engine attaches door state to), so the toggle hides.
        create = function(element)
            element:FireEvent("refreshdoorchip")
        end,
        refreshdoorchip = function(element)
            element:SetClass("collapsed", MM.EntryIsOpenable(m.paletteEntries[m.selectedIndex or 0]))
        end,

        children = {
            CreateDrawModeChip(false),
            gui.Panel{
                width = 4,
                height = 1,
            },
            CreateDrawModeChip(true),
        },
    }

    --Wall height stepper: blank ("To Roof") means walls run floor to ceiling;
    --a number is the height in tiles stamped on each placement, letting
    --creatures fly, see, and climb over per the wall height rules. In solid
    --mode the same value is the block's height (To Roof = no standable top).
    heightPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        multimonitor = {"building:specifywallheight", "building:wallheightvalue"},

        events = {
            monitor = function(element)
                element:FireEventTree("refreshheight")
            end,
        },

        hover = MM.SideTooltip("Walls with a height can be flown over, seen over, and climbed over by creatures high enough. Walls set To Roof always block. For solid blocks the height is the block's height: a block with a height has a standable top, while To Roof fills floor to ceiling."),

        --Section header like Shape / Wall Types; on its own line so the
        --stepper beneath cannot read as "Wall Height: -" / "To Roof: +".
        gui.Label{
            classes = {"markupSectionHeader"},
            text = "Wall Height",
            uppercase = true,
            width = "100%",
            height = "auto",
            vmargin = 4,
            refreshheight = function(element)
                element.text = cond(m.solidMode, "Block Height", "Wall Height")
            end,
        },

        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            flow = "horizontal",

            gui.Button{
                classes = {"sizeS"},
                text = "-",
                width = 30,
                valign = "center",
                hmargin = 6,
                events = {
                    click = function()
                        local height = MM.GetWallHeightSetting()
                        if height == nil then
                            return
                        end
                        if height <= 1 then
                            MM.SetWallHeightSetting(nil)
                        else
                            MM.SetWallHeightSetting(height - 1)
                        end
                    end,
                },
            },

            gui.Label{
                text = "",
                fontSize = 18,
                --wide enough for "To Roof" (the no-height label) without wrapping.
                width = 90,
                height = "auto",
                valign = "center",
                textAlignment = "center",
                create = function(element)
                    element:FireEvent("refreshheight")
                end,
                refreshheight = function(element)
                    local height = MM.GetWallHeightSetting()
                    if height == nil then
                        element.text = "To Roof"
                    else
                        element.text = string.format("%d", math.floor(height + 0.5))
                    end
                end,
            },

            gui.Button{
                classes = {"sizeS"},
                text = "+",
                width = 30,
                valign = "center",
                hmargin = 6,
                events = {
                    click = function()
                        local height = MM.GetWallHeightSetting()
                        if height == nil then
                            MM.SetWallHeightSetting(1)
                        elseif height < 10 then
                            MM.SetWallHeightSetting(height + 1)
                        end
                    end,
                },
            },
        },
    }

    local wallsPanel = gui.Panel{
        classes = {cond(m.mode ~= "walls", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        markupmode = function(element)
            element:SetClass("collapsed", m.mode ~= "walls")
        end,

        --Fixed "how you draw" controls lead; the wall type list comes last
        --because it is the only section that grows (custom types), and
        --putting it below keeps the tool strip at a stable position.
        MM.SectionHeader("Tool"),

        toolsPanel,

        --"Shape" groups the stroke's geometry: thin vs solid, and the height
        --stamped on each placement. It sits directly under the tool strip
        --because the toggle swaps which tool strip is shown. The header
        --stays up even for openable (door) types, where the thin/solid
        --toggle collapses but the height stepper still applies.
        MM.SectionHeader("Shape"),

        drawModePanel,

        heightPanel,

        MM.SectionHeader("Wall Types"),

        palettePanel,

        addButton,
    }


    return {
        panel = wallsPanel,
        toolPanel = toolsPanel,
        prime = function()
            palettePanel:FireEvent("refreshpalette")
        end,
    }
end
