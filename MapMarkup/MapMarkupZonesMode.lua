local mod = dmhub.GetModLoading()

--Map Markup panel: the Zones tab builder.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--========================================================================
--Zones mode UI: zone-type palette (Environmental Keywords), paint tools,
--and the list of zones on the current floor.
--========================================================================
--Builds the tab's content panel. Returns {panel, toolPanel, prime}:
--toolPanel is what TakeMarkupFocus re-fires 'think' on, prime is run once
--by CreateMarkupEditor after the whole panel is assembled.
function MM.BuildZonesMode()
    local zonePalettePanel
    local zoneToolsPanel
    local zoneListPanel
    local zonesPanel

    local RefreshZoneUI = function()
        if zonesPanel ~= nil and zonesPanel.valid then
            zonesPanel:FireEventTree("refreshzones")
        end
    end

    --Resolves a zone-type chip to a keyword id, materializing preset chips
    --into real Environmental Keywords on first use (recording the new id back
    --into the palette, like wall presets record their materialized asset).
    local EnsureZoneTypeKeyword = function(index)
        local entry = m.zonePaletteEntries[index or 0]
        if entry == nil then
            return nil
        end

        if entry.keywordid ~= nil then
            if MM.GetKeyword(entry.keywordid) ~= nil then
                return entry.keywordid
            end
            if entry.kind ~= "preset" then
                --keyword chip whose keyword was deleted from the compendium.
                return nil
            end
        end

        if entry.kind == "preset" then
            local preset = K.ZONE_PRESETS_BY_KEY[entry.key]
            if preset == nil then
                return nil
            end
            local keywordid = MM.MaterializeZonePreset(preset)
            if keywordid == nil then
                return nil
            end
            entry.keywordid = keywordid
            MM.SaveZonePalette(m.zonePaletteEntries)
            return keywordid
        end

        return nil
    end

    --Opens the zone type's keyword editor dialog (the same editor the
    --compendium uses), materializing preset entries into real keywords first.
    local EditZoneTypeKeyword = function(index)
        local keywordid = EnsureZoneTypeKeyword(index)
        if keywordid == nil then
            return
        end
        local keywordType = rawget(_G, "EnvironmentalKeyword")
        if keywordType == nil or rawget(keywordType, "ShowEditDialog") == nil then
            dmhub.Debug("MARKUP:: EnvironmentalKeyword.ShowEditDialog not available")
            return
        end
        keywordType.ShowEditDialog(keywordid)
    end

    --"Set Amount..." prompt behind the chip's Default Height submenu. A typed
    --number rather than a stepper: unlike wall height there is no small fixed
    --range, and "Ground Only"/"Unlimited" (the two common answers) are already
    --one click away in the menu. apply(height) does the writing, so this is
    --shared by the per-type default and the per-zone override.
    local ShowZoneHeightDialog = function(currentHeight, apply, owner)
        local heightText = tostring(cond(currentHeight ~= nil and currentHeight >= 1, currentHeight, 2))

        local modalLayer = nil
        local dialogPanel
        dialogPanel = gui.Panel{
            id = "MarkupZoneHeightDialog",
            classes = {"framedPanel"},
            --94% of the modal layer, capped at the design width (see
            --MarkupWallDialog).
            width = "94%",
            maxWidth = 380,
            height = "auto",
            pad = 16,
            borderBox = true,
            flow = "vertical",
            styles = ThemeEngine.MergeStyles{
                Styles.Panel,
                MM.MarkupChipStyles(),
            },

            gui.Label{
                classes = {"dialogTitle"},
                text = "Zone Height",
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Affects up to height:",
                },
                gui.Input{
                    classes = {"formStacked"},
                    text = heightText,
                    width = 60,
                    characterLimit = 3,
                    numeric = true,
                    selectAllOnFocus = true,
                    change = function(element)
                        heightText = element.text
                    end,
                },
            },

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = "Tiles above the ground the zone reaches. The height follows the terrain, so a zone that runs up onto a ledge still reaches this far above the ledge.",
                width = "94%",
                height = "auto",
                halign = "center",
                vmargin = 2,
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                vmargin = 8,

                gui.Button{
                    classes = {"sizeM"},
                    text = "Cancel",
                    halign = "center",
                    captureEscape = true,
                    escapePriority = EscapePriority.EXIT_DIALOG,
                    events = {
                        click = function(element)
                            element:FireEvent("escape")
                        end,
                        escape = function()
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },

                gui.Button{
                    classes = {"sizeM"},
                    text = "Save",
                    halign = "center",
                    events = {
                        click = function()
                            --a blank or junk entry means "no limit"; 0 typed
                            --here is the same answer as the menu's Ground Only.
                            local n = tonumber(heightText)
                            if n == nil or n < 0 then
                                apply(nil)
                            else
                                apply(math.floor(n))
                            end
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },
            },
        }

        modalLayer = gui.ShowModal(dialogPanel, {owner = owner})
    end

    --The built-in "Hole" chip: always last in the palette, not keyword-backed
    --and not editable -- no right-click menu, no Entire Map pill, no dynamic
    --light row. Painting with it cuts real holes in the map (see m.holes).
    local CreateHoleZoneChip = function(index)
        local summary = "Cuts a hole through the floor"
        if not m.holes.Supported() then
            summary = "Needs an engine update"
        end

        local gradient = m.zoneStripes.Gradient(m.holes.color, K.ZONE_ANGLE_A)
        local swatchColor = m.holes.color
        if gradient ~= nil then
            swatchColor = "white"
        end

        return gui.Panel{
            classes = {"markupChip", cond(index == m.zoneSelectedType, "selected")},
            width = "100%",
            height = 36,
            halign = "center",
            flow = "vertical",
            bgimage = true,
            pad = 6,
            borderBox = true,
            vmargin = 1,

            data = {
                index = index,
            },

            press = function(element)
                m.zoneSelectedType = element.data.index
                --a fresh type selection paints new holes, not whatever zone
                --was last targeted.
                m.zoneTargetId = nil
                zonePalettePanel:FireEvent("refreshchips")
                RefreshZoneUI()
                --picking the type must arm the paint tool by itself, exactly
                --like the zone chips.
                MM.TakeMarkupFocus()
            end,

            gui.Panel{
                width = "100%",
                height = 24,
                flow = "horizontal",

                gui.Panel{
                    --no Entire Map pill on this chip, so only the swatch
                    --column comes off the width: this panel's own 4+4 hmargin
                    --plus the swatch's 28 + 4+4. Get this wrong and the swatch
                    --sits out of line with the keyword chips' swatches.
                    width = "100%-44",
                    height = "auto",
                    valign = "center",
                    flow = "vertical",
                    hmargin = 4,

                    gui.Label{
                        classes = {"bold"},
                        text = "Hole",
                        width = "100%",
                        height = "auto",
                    },

                    gui.Label{
                        classes = {"fgMuted", "sizeXs"},
                        text = summary,
                        width = "100%",
                        height = "auto",
                        textWrap = false,
                        textOverflow = "ellipsis",
                    },
                },

                gui.Panel{
                    width = 28,
                    height = 28,
                    hmargin = 4,
                    valign = "center",
                    bgimage = true,
                    bgcolor = swatchColor,
                    gradient = gradient,
                    borderWidth = 1,
                    borderColor = "@border",
                },
            },
        }
    end

    --Whether the keyword carries a USABLE visual representation (the same
    --test BuildZoneAuraInstance applies before stamping it on an aura): a
    --floor appearance with a fill or edge asset, or a sprites appearance
    --with at least one sprite. Gates the Visuals pill on palette chips and
    --the Visuals badge on zone rows - a type with no art gets neither.
    local ZoneTypeHasVisuals = function(kw)
        if kw == nil then
            return false
        end
        local has = false
        pcall(function()
            local appearance = kw:try_get("appearance")
            if appearance == nil then
                return
            end
            if appearance.mode == "floor" then
                has = appearance.tileid ~= nil or appearance.edgeWallId ~= nil
            elseif appearance.mode == "sprites" then
                has = appearance.sprites ~= nil and #appearance.sprites > 0
            end
        end)
        return has
    end

    local CreateZoneChip = function(index, entry)
        if entry.kind == "hole" then
            return CreateHoleZoneChip(index)
        end

        local kw = MM.GetKeyword(entry.keywordid)
        local preset = nil
        if entry.kind == "preset" then
            preset = K.ZONE_PRESETS_BY_KEY[entry.key]
        end

        local name, color, summary
        if kw ~= nil then
            name = kw.name or "Keyword"
            color = MM.KeywordColor(entry.keywordid, kw)
            summary = MM.KeywordSummary(kw)
        elseif preset ~= nil then
            name = preset.name
            color = preset.color
            summary = preset.summary
        else
            name = "Unknown Keyword"
            color = "#666666"
            summary = "Missing from the compendium"
        end

        --"Entire Map": this type blankets the whole map instead of only the
        --regions painted with it. Nothing is striped on the map for it -- the
        --lit pill is the indicator -- so keep the tooltip explicit about that.
        local entireMapButton
        entireMapButton = gui.Panel{
            classes = {"markupEntireMap", cond(m.entireMap.IsSet(entry.keywordid), "lit")},
            width = 60,
            height = 16,
            valign = "center",
            bgimage = "panels/square.png",
            hover = MM.SideTooltip("Apply this zone type to the whole map. Zones that dispel it (and zones painted with it) carve it out. Nothing is drawn on the map for it."),

            click = function(element)
                --a preset chip has no keyword until something uses it.
                local keywordid = EnsureZoneTypeKeyword(index)
                if keywordid == nil then
                    return
                end

                local lit = not m.entireMap.IsSet(keywordid)
                m.entireMap.Set(keywordid, lit)
                element:SetClass("lit", lit)

                --a blanket registers (or drops) real auras, so rebuild now
                --instead of waiting for an unrelated aura rebuild.
                pcall(function()
                    dmhub.RefreshMapAuras()
                end)
            end,

            gui.Label{
                classes = {"markupEntireMapLabel", "sizeXs"},
                text = "Entire Map",
                fontSize = 10,
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
            },
        }

        --"Visuals": only for types with a visual representation (Edit
        --Appearance art). Lit = zones drawn with this type display their
        --art; unlit = they get stripes only. Only a DEFAULT stamped at
        --paint time - each zone's art then toggles from the Visuals badge
        --on its list row, so flipping this never disturbs painted zones.
        --Always constructed and collapsed when ineligible: a nil positional
        --child would hole the topRow constructor's array and drop the
        --children after it.
        local hasVisuals = ZoneTypeHasVisuals(kw)
        local visualsOn = true
        if hasVisuals then
            pcall(function()
                visualsOn = kw:try_get("appearanceDefaultOff", false) ~= true
            end)
        end
        local visualsButton = gui.Panel{
            classes = {"markupEntireMap", cond(visualsOn, "lit"), cond(not hasVisuals, "collapsed")},
            width = 48,
            height = 16,
            hmargin = 2,
            valign = "center",
            bgimage = "panels/square.png",
            hover = MM.SideTooltip("This zone type has a visual representation. When lit, zones you draw display it on the map; when unlit, new zones show only their stripes. Each painted zone can still be toggled from its row in the zone list."),

            click = function(element)
                --the pill only shows for a resolved keyword (the
                --appearance lives on it), so this is just the dead-id
                --healing path, same as the Entire Map pill.
                local keywordid = EnsureZoneTypeKeyword(index)
                if keywordid == nil then
                    return
                end
                local keyword = MM.GetKeyword(keywordid)
                if keyword == nil then
                    return
                end
                local off = false
                pcall(function()
                    off = keyword:try_get("appearanceDefaultOff", false) == true
                end)
                if off then
                    --shown is the default; nil-assign clears the field
                    --(same idiom defaultHeight uses).
                    keyword.appearanceDefaultOff = nil
                else
                    keyword.appearanceDefaultOff = true
                end
                dmhub.SetAndUploadTableItem(K.ENVIRONMENTAL_KEYWORDS_TABLE, keyword)
                element:SetClass("lit", off)
            end,

            gui.Label{
                classes = {"markupEntireMapLabel", "sizeXs"},
                text = "Visuals",
                fontSize = 10,
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
            },
        }

        --"Dynamic Light": the zone type only applies where the map's light
        --level is below the slider's threshold, recomputed live as lights
        --move and the time of day changes. Double-gated: the engine must
        --support the sampling API (new), and the KEYWORD must have "Can Use
        --Dynamic Light" checked in its editor -- most zone types (Water,
        --Difficult Terrain) have no use for it, so only opted-in types
        --(Darkness) grow the second row. Preset chips have no keyword yet
        --and so never show it; materialize the keyword and check the flag.
        local dynEligible = false
        if kw ~= nil then
            pcall(function()
                dynEligible = kw:try_get("dynamicLight", false) == true
            end)
        end

        local dynRow = nil
        if dynEligible and m.dynamicLight.Supported() then
            local dynPct = m.dynamicLight.GetThreshold(entry.keywordid)

            local dynSlider
            dynSlider = gui.PercentSlider{
                --the args table REPLACES PercentSlider's own classes list, so
                --"percentSlider" must ride along or the control loses its look.
                classes = {"percentSlider", cond(dynPct == nil, "hidden")},
                width = 100,
                height = 14,
                halign = "left",
                valign = "center",
                hmargin = 8,
                value = (dynPct or 30) / 100,
                hover = MM.SideTooltip("Light threshold: tiles where the light level is below this count as dark, and this zone type applies only there."),
                confirm = function(element)
                    local keywordid = entry.keywordid
                    if keywordid == nil then
                        return
                    end
                    local pct = round(element.value * 100)
                    if pct < 1 then
                        pct = 1
                    end
                    m.dynamicLight.Set(keywordid, pct)
                    --sample the new threshold NOW: waiting for the ticker
                    --leaves a visible blink where the zone rebuilds unfiltered
                    --(new threshold = no sample yet) and then snaps back a
                    --poll later.
                    pcall(m.dynamicLight.Sample)
                end,
            }

            local dynButton
            dynButton = gui.Panel{
                classes = {"markupEntireMap", cond(dynPct ~= nil, "lit")},
                width = 78,
                height = 16,
                halign = "left",
                valign = "center",
                bgimage = "panels/square.png",
                hover = MM.SideTooltip("Calculate this zone type dynamically from the light on the map: it only applies where the light level is below the threshold. Updates as lights move, doors close and night falls. Painted zones and the Entire Map blanket are both filtered."),

                click = function(element)
                    --the row only shows for a resolved keyword (the
                    --dynamicLight flag lives on it), so this is just the
                    --dead-id healing path, same as the Entire Map pill.
                    local keywordid = EnsureZoneTypeKeyword(index)
                    if keywordid == nil then
                        return
                    end

                    local lit = m.dynamicLight.GetThreshold(keywordid) == nil
                    if lit then
                        local pct = round(dynSlider.value * 100)
                        if pct < 1 then
                            pct = 30
                        end
                        m.dynamicLight.Set(keywordid, pct)
                    else
                        m.dynamicLight.Set(keywordid, nil)
                    end
                    element:SetClass("lit", lit)
                    dynSlider:SetClass("hidden", not lit)
                    --sample immediately: enabling carves in the same tick
                    --(no unfiltered blink), disabling clears the stored dark
                    --sets and refreshes the auras without waiting a poll.
                    pcall(m.dynamicLight.Sample)
                end,

                gui.Label{
                    classes = {"markupEntireMapLabel", "sizeXs"},
                    text = "Dynamic Light",
                    fontSize = 10,
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                },
            }

            dynRow = gui.Panel{
                width = "100%",
                height = 24,
                flow = "horizontal",

                dynButton,
                dynSlider,
            }
        end

        --A wider version of m.zoneStripes.Swatch for the row's right-side
        --visual, mirroring the wall rows' line-preview column: the stripe
        --pattern at the angle the map will actually paint.
        local gradient = m.zoneStripes.Gradient(color, m.zoneStripes.AngleForKeyword(entry.keywordid))
        local swatchColor = color
        if gradient ~= nil then
            swatchColor = "white"
        end

        --the classic chip content; on engines with light sampling the chip
        --grows a second row holding the Dynamic Light controls.
        local topRow = gui.Panel{
            width = "100%",
            height = 24,
            flow = "horizontal",

            gui.Panel{
                --the Visuals pill (48 + 2+2 hmargin) comes off the text
                --column when present, on top of the standing 104 (label
                --margins + Entire Map pill + swatch).
                width = cond(hasVisuals, "100%-156", "100%-104"),
                height = "auto",
                valign = "center",
                flow = "vertical",
                hmargin = 4,

                gui.Label{
                    classes = {"bold"},
                    text = name,
                    width = "100%",
                    height = "auto",
                },

                --the summary can outgrow the chip (e.g. Lava: difficult
                --terrain + damaging + affects adjacent), so it ellipsizes on
                --one line rather than wrapping out of the fixed-height row;
                --hovering shows the untruncated string.
                gui.Label{
                    classes = {"fgMuted", "sizeXs"},
                    text = summary,
                    width = "100%",
                    height = "auto",
                    textWrap = false,
                    textOverflow = "ellipsis",
                    linger = function(element)
                        if summary ~= nil and summary ~= "" then
                            gui.Tooltip(summary)(element)
                        end
                    end,
                },
            },

            visualsButton,

            entireMapButton,

            --No settings cog: editing lives in the right-click menu ("Edit
            --Zone Type..."). A square swatch at the row's right edge, nearly
            --the row's full inner height: a filled region reads as an area,
            --unlike the walls' thin lines.
            gui.Panel{
                width = 28,
                height = 28,
                hmargin = 4,
                valign = "center",
                bgimage = true,
                bgcolor = swatchColor,
                gradient = gradient,
                borderWidth = 1,
                borderColor = "@border",
            },
        }

        return gui.Panel{
            classes = {"markupChip", cond(index == m.zoneSelectedType, "selected")},
            width = "100%",
            height = cond(dynRow ~= nil, 60, 36),
            halign = "center",
            flow = "vertical",
            bgimage = true,
            pad = 6,
            borderBox = true,
            vmargin = 1,

            data = {
                index = index,
            },

            press = function(element)
                m.zoneSelectedType = element.data.index
                --a fresh type selection paints into that type's existing zone
                --(or a new one), not whatever zone was last targeted.
                m.zoneTargetId = nil
                zonePalettePanel:FireEvent("refreshchips")
                RefreshZoneUI()
                --picking a zone type must arm the paint tool by itself: without
                --this the next click on the map lands with no custom map tool
                --registered and silently does nothing.
                MM.TakeMarkupFocus()
            end,

            rightClick = function(element)
                --"Default Height" writes to the KEYWORD, so a preset chip has
                --to materialize its keyword first (same lazy-materialize the
                --Entire Map pill does). Setting a default never touches zones
                --already painted - it is only what the next one is stamped with.
                local SetDefaultHeight = function(height)
                    local keywordid = EnsureZoneTypeKeyword(element.data.index)
                    if keywordid == nil then
                        return
                    end
                    m.zoneHeight.Set(keywordid, height)
                    zonePalettePanel:FireEvent("refreshzonepalette")
                end

                local currentHeight = m.zoneHeight.Get(MM.GetKeyword(entry.keywordid))

                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Edit Zone Type...",
                            click = function()
                                element.popup = nil
                                EditZoneTypeKeyword(element.data.index)
                            end,
                        },
                        {
                            text = "Default Height",
                            submenu = {
                                {
                                    text = cond(currentHeight == nil, "Unlimited (current)", "Unlimited"),
                                    click = function()
                                        element.popup = nil
                                        SetDefaultHeight(nil)
                                    end,
                                },
                                {
                                    text = cond(currentHeight == 0, "Ground Only (current)", "Ground Only"),
                                    click = function()
                                        element.popup = nil
                                        SetDefaultHeight(0)
                                    end,
                                },
                                {
                                    text = cond(currentHeight ~= nil and currentHeight > 0,
                                        string.format("Set Amount... (%d)", currentHeight or 0), "Set Amount..."),
                                    click = function()
                                        element.popup = nil
                                        ShowZoneHeightDialog(currentHeight, SetDefaultHeight, element)
                                    end,
                                },
                            },
                        },
                        {
                            text = "Remove from Palette",
                            click = function()
                                element.popup = nil
                                --drop the blanket (and the dynamic-light
                                --config) with the chip: otherwise they keep
                                --applying to the map with no UI left to turn
                                --them off.
                                local removed = m.zonePaletteEntries[element.data.index]
                                if removed ~= nil and removed.keywordid ~= nil then
                                    if m.entireMap.IsSet(removed.keywordid) then
                                        m.entireMap.Set(removed.keywordid, false)
                                        pcall(function()
                                            dmhub.RefreshMapAuras()
                                        end)
                                    end
                                    m.dynamicLight.Set(removed.keywordid, nil)
                                end
                                table.remove(m.zonePaletteEntries, element.data.index)
                                if m.zoneSelectedType > #m.zonePaletteEntries then
                                    m.zoneSelectedType = #m.zonePaletteEntries
                                end
                                if m.zoneSelectedType < 1 then
                                    m.zoneSelectedType = 1
                                end
                                MM.SaveZonePalette(m.zonePaletteEntries)

                                --a map-scoped zone type with no zones painted
                                --is orphaned once its chip is gone: delete the
                                --keyword rather than stranding it hidden in
                                --the table.
                                if removed ~= nil and removed.keywordid ~= nil then
                                    m.mapScope.DeleteKeywordIfOrphaned(removed.keywordid, m.zonePaletteEntries)
                                end
                            end,
                        },
                    },
                }
            end,

            topRow,
            dynRow,
        }
    end

    --split out so refreshzonepalette can hand it to RebuildDeferringPopups
    --and have it replayed later if a chip context menu is open.
    local RebuildZonePalette = function(element)
        m.zonePaletteEntries = MM.ParseZonePalette()
        --the built-in Hole type is always present, after the user's zone
        --types. SerializeZonePalette skips it (no kind "preset", no
        --keywordid), so it never reaches the stored palette setting.
        m.zonePaletteEntries[#m.zonePaletteEntries+1] = { kind = "hole" }
        if m.zoneSelectedType > #m.zonePaletteEntries then
            m.zoneSelectedType = #m.zonePaletteEntries
        end
        if m.zoneSelectedType < 1 then
            m.zoneSelectedType = 1
        end

        --the chips stripe at the angle the map will actually use, and
        --that assignment is computed by the zone cache rebuild. Cheap
        --when the cache is already warm.
        MM.EnsureZoneCache()

        local children = {}
        for i,entry in ipairs(m.zonePaletteEntries) do
            children[#children+1] = CreateZoneChip(i, entry)
        end
        element.children = children
    end

    zonePalettePanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        --monitorAssets: keyword table edits change chip names/colors/summaries.
        monitorAssets = true,
        --zoneentiremap and zonedynamiclight as well as the palette: the
        --"Entire Map" and "Dynamic Light" pills read them, and they can
        --change from another client (or from an undo).
        multimonitor = {"markup:zonepalette", "markup:zoneentiremap", "markup:zonedynamiclight"},

        --gui.RebuildDeferringPopups parks a stood-down rebuild in here.
        data = {},

        events = {
            think = gui.ThinkDeferredRebuild,

            monitor = function(element)
                element:FireEvent("refreshzonepalette")
            end,

            refreshAssets = function(element)
                element:FireEvent("refreshzonepalette")
            end,

            --replaces every chip, so it stands down while a chip context
            --menu is open rather than closing it under the cursor.
            refreshzonepalette = function(element)
                gui.RebuildDeferringPopups(element, RebuildZonePalette)
            end,

            refreshchips = function(element)
                for _,chip in ipairs(element.children) do
                    if chip.data ~= nil and chip.data.index ~= nil then
                        chip:SetClass("selected", chip.data.index == m.zoneSelectedType)
                    end
                end
            end,
        },
    }

    --Adding a zone type selects it, mirroring what pressing its chip does.
    --Without this the palette grows but m.zoneSelectedType stays put, so the
    --new chip renders unselected and the next click on the map paints the
    --PREVIOUS type. The rebuild triggered by SaveZonePalette restamps the
    --chips, and CreateZoneChip reads m.zoneSelectedType at construction, so
    --the new chip is born selected without an explicit refreshchips.
    --Callers that also want the paint tool armed call TakeMarkupFocus()
    --afterwards; the "New Zone Type..." path deliberately does not, because it
    --opens a modal editor for the new keyword immediately.
    local AppendZoneTypeAndSelect = function(entry)
        m.zonePaletteEntries[#m.zonePaletteEntries+1] = entry
        m.zoneSelectedType = #m.zonePaletteEntries
        --a fresh type selection paints into that type's existing zone (or a
        --new one), not whatever zone was last targeted.
        m.zoneTargetId = nil
        MM.SaveZonePalette(m.zonePaletteEntries)
        RefreshZoneUI()
    end

    --Styled as one more palette row, like the walls tab's Add Wall Type.
    local zoneAddButton
    zoneAddButton = gui.Panel{
        classes = {"markupChip"},
        width = "96%",
        height = 28,
        halign = "center",
        bgimage = true,
        borderBox = true,
        vmargin = 2,

        gui.Label{
            classes = {"fgMuted"},
            text = "+ Add Zone Type",
            fontSize = 14,
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
        },

        press = function(element)
            local entries = {}

            for _,preset in ipairs(K.ZONE_PRESETS) do
                local inPalette = false
                for _,entry in ipairs(m.zonePaletteEntries) do
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
                            AppendZoneTypeAndSelect{
                                kind = "preset",
                                key = preset.key,
                            }
                            MM.TakeMarkupFocus()
                        end,
                    }
                end
            end

            local paletteKeywords = {}
            for _,entry in ipairs(m.zonePaletteEntries) do
                if entry.keywordid ~= nil then
                    paletteKeywords[entry.keywordid] = true
                end
            end

            local sortedKeywords = {}
            for k,kw in unhidden_pairs(MM.GetKeywordTable()) do
                --zone types scoped to other maps never appear here.
                if (not paletteKeywords[k]) and MM.KeywordAvailableOnThisMap(kw) then
                    sortedKeywords[#sortedKeywords+1] = {
                        id = k,
                        name = kw.name or k,
                    }
                end
            end
            table.sort(sortedKeywords, function(a, b) return a.name < b.name end)

            for _,info in ipairs(sortedKeywords) do
                entries[#entries+1] = {
                    text = info.name,
                    click = function()
                        element.popup = nil
                        AppendZoneTypeAndSelect{
                            kind = "keyword",
                            keywordid = info.id,
                        }
                        MM.TakeMarkupFocus()
                    end,
                }
            end

            entries[#entries+1] = {
                text = "New Zone Type...",
                click = function()
                    element.popup = nil
                    local keywordType = rawget(_G, "EnvironmentalKeyword")
                    if keywordType == nil then
                        dmhub.Debug("MARKUP:: EnvironmentalKeyword type not loaded")
                        return
                    end
                    --Created scoped to THIS map (mapid): hidden from the
                    --compendium and other maps until promoted via the editor's
                    --"Make Available to All Maps" button. Opens the editor
                    --dialog immediately so it can be named and configured.
                    --The table id comes from SetAndUploadTableItem's return
                    --value; kw.guid is a DIFFERENT id and never the table key.
                    local kw = keywordType.CreateNew()
                    kw.name = "New Zone Type"
                    kw.mapid = game.currentMapId
                    local keywordid = dmhub.SetAndUploadTableItem(K.ENVIRONMENTAL_KEYWORDS_TABLE, kw)
                    AppendZoneTypeAndSelect{
                        kind = "keyword",
                        keywordid = keywordid,
                    }
                    --no TakeMarkupFocus here on purpose: ShowEditDialog opens a
                    --modal editor for the brand-new keyword, and arming the map
                    --paint tool underneath it fights the dialog for focus.

                    if rawget(keywordType, "ShowEditDialog") ~= nil then
                        keywordType.ShowEditDialog(keywordid)
                    end
                end,
            }

            element.popup = gui.ContextMenu{
                entries = entries,
            }
        end,
    }

    --Per-zone edit dialog: name, height limit, player visibility.
    local ShowZoneDialog = function(entry, owner)
        local modalLayer = nil
        local name = entry.name
        local playerVisible = entry.playerVisible == true

        --Height as a mode + amount, matching the zone type's Default Height.
        --The amount box keeps a usable number even while hidden, so switching
        --to Set Amount never lands on a value Save has to reject.
        local heightMode = "infinite"
        if entry.height ~= nil then
            heightMode = cond(entry.height <= 0, "ground", "amount")
        end
        local heightText = tostring(cond(entry.height ~= nil and entry.height >= 1, entry.height, 2))

        local heightAmountPanel
        heightAmountPanel = gui.Panel{
            classes = {"formStackedRow", cond(heightMode ~= "amount", "collapsed")},
            gui.Label{
                classes = {"formStacked"},
                text = "Tiles above ground:",
            },
            gui.Input{
                classes = {"formStacked"},
                text = heightText,
                width = 60,
                characterLimit = 3,
                numeric = true,
                selectAllOnFocus = true,
                change = function(element)
                    heightText = element.text
                end,
            },
        }

        local dialogPanel
        dialogPanel = gui.Panel{
            id = "MarkupZoneDialog",
            classes = {"framedPanel"},
            --94% of the modal layer, capped at the design width (see
            --MarkupWallDialog).
            width = "94%",
            maxWidth = 440,
            height = "auto",
            pad = 16,
            borderBox = true,
            flow = "vertical",
            styles = ThemeEngine.MergeStyles{
                Styles.Panel,
                MM.MarkupChipStyles(),
            },

            gui.Label{
                classes = {"dialogTitle"},
                text = "Edit Zone",
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Name:",
                },
                gui.Input{
                    classes = {"formStacked"},
                    text = name,
                    characterLimit = 60,
                    change = function(element)
                        if element.text ~= "" then
                            name = element.text
                        else
                            element.text = name
                        end
                    end,
                },
            },

            --Same three-way vocabulary as the zone type's Default Height, so
            --"Ground Only" is a named choice here rather than a 0 the user has
            --to know to type. The amount box only shows for Set Amount.
            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Height:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = heightMode,
                    options = {
                        {id = "infinite", text = "Unlimited"},
                        {id = "ground", text = "Ground Only"},
                        {id = "amount", text = "Set Amount"},
                    },
                    change = function(element)
                        heightMode = element.idChosen
                        heightAmountPanel:SetClass("collapsed", heightMode ~= "amount")
                    end,
                },
            },

            heightAmountPanel,

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = "How far up the zone reaches, measured from the ground under it - so it follows the terrain over ledges and pits. Ground Only affects creatures standing in the zone but not flyers above it; Unlimited affects everything over it as well.",
                width = "94%",
                height = "auto",
                halign = "center",
                vmargin = 2,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Visible to players",
                tooltip = "Players see this zone's stripes and name on their map when they turn on the tile overlay. Starts from the zone type's own default; turn it off for a zone the players are not meant to know about.",
                value = playerVisible,
                change = function(element)
                    playerVisible = element.value
                end,
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                vmargin = 8,

                gui.Button{
                    classes = {"sizeM"},
                    text = "Cancel",
                    halign = "center",
                    captureEscape = true,
                    escapePriority = EscapePriority.EXIT_DIALOG,
                    events = {
                        click = function(element)
                            element:FireEvent("escape")
                        end,
                        escape = function()
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },

                gui.Button{
                    classes = {"sizeM"},
                    text = "Save",
                    halign = "center",
                    events = {
                        click = function()
                            local floor = game.currentFloor
                            if floor ~= nil then
                                local overrides = {
                                    name = name,
                                    playerVisible = playerVisible,
                                }
                                if heightMode == "infinite" then
                                    overrides.clearHeight = true
                                elseif heightMode == "ground" then
                                    overrides.height = 0
                                else
                                    --junk in the amount box falls back to
                                    --unlimited rather than silently saving 0,
                                    --which would read as Ground Only.
                                    local n = tonumber(heightText)
                                    if n == nil or n < 0 then
                                        overrides.clearHeight = true
                                    else
                                        overrides.height = math.floor(n)
                                    end
                                end
                                floor:SetMarkupZone(entry.zoneid, MM.BuildZoneRecord(entry, overrides))
                                RefreshZoneUI()
                            end
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },
            },
        }

        modalLayer = gui.ShowModal(dialogPanel, {owner = owner})
    end

    local CreateZoneRow = function(entry)
        local meta = {}
        meta[#meta+1] = string.format("%d tiles", #entry.locs)
        --calculated zones (see m.calculatedZones) have no record at all:
        --nothing to edit, so the row says where they come from instead.
        if entry.calculated == true then
            meta[#meta+1] = entry.calculatedMeta or "calculated"
        end
        --holes have no height or player-visibility settings (the cut itself
        --is visible to everyone once the panel closes), so the tile count is
        --their whole story.
        if entry.hole ~= true and entry.calculated ~= true then
            --"height 0" would read as "no height"; describe the modes by name.
            --Unlimited is spelled out here rather than left blank (Describe returns
            --nil for it, which is right for chips and menus): on a row that already
            --reads "N tiles", a silent height is indistinguishable from a zone whose
            --height nobody has looked at.
            meta[#meta+1] = string.lower(m.zoneHeight.Describe(entry.height) or "Unlimited height")
            --player-visible is the default now, so the row calls out the exception:
            --a zone the DM has deliberately kept to themselves.
            if not entry.playerVisible then
                meta[#meta+1] = "hidden from players"
            end
        end

        --Rows read as "<type> -- <where>": the collapsed type/custom name
        --(same rule as the map labels) plus the zone's area of the map. The
        --raw numbered record name stays visible in the Edit Zone dialog.
        local displayName = MM.ZoneOverlayLabel(entry)
        local area = MM.ZoneAreaDescription(entry)
        if area ~= nil then
            displayName = displayName .. " -- " .. area
        end
        if #entry.locs == 0 then
            displayName = displayName .. " (empty)"
        end

        --Same enlarged swatch treatment as the zone-type rows.
        local rowGradient = m.zoneStripes.Gradient(entry.patternColor, entry.patternAngle)
        local rowSwatchColor = entry.patternColor
        if rowGradient ~= nil then
            rowSwatchColor = "white"
        end

        --"Visuals" badge: only for zones whose TYPE has a visual
        --representation. Lit = this zone displays its art on the map;
        --click toggles the zone's own hideAppearance flag (the record
        --write triggers the aura rebuild that adds/removes the art).
        local rowHasVisuals = entry.calculated ~= true and ZoneTypeHasVisuals(entry.keywordInfo)
        local visualsBadge = nil
        if rowHasVisuals then
            visualsBadge = gui.Panel{
                classes = {"markupEntireMap", cond(entry.hideAppearance ~= true, "lit")},
                width = 48,
                height = 16,
                hmargin = 2,
                valign = "center",
                bgimage = "panels/square.png",
                hover = MM.SideTooltip("This zone's type has a visual representation. When lit, this zone displays it on the map; click to show only the stripes for this zone."),

                --MUST swallow the press. Without it the mouse-DOWN bubbles to
                --the row, whose press selects the zone and calls RefreshZoneUI
                ---- which replaces zoneListPanel.children, destroying this very
                --badge before the mouse comes back up, so the click never
                --fires and only the row's selection is seen. (The identical
                --badge on the zone-TYPE chip needs no such guard: that chip's
                --press only re-runs "refreshchips", which retags the selected
                --class instead of rebuilding.)
                swallowPress = true,

                click = function(element)
                    local floor = game.currentFloor
                    if floor == nil then
                        return
                    end
                    local hide = entry.hideAppearance ~= true
                    floor:SetMarkupZone(entry.zoneid, MM.BuildZoneRecord(entry, { hideAppearance = hide }))
                    RefreshZoneUI()
                end,

                gui.Label{
                    classes = {"markupEntireMapLabel", "sizeXs"},
                    text = "Visuals",
                    fontSize = 10,
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                },
            }
        end

        return gui.Panel{
            classes = {"markupChip", cond(entry.zoneid == m.zoneTargetId, "selected")},
            --zoneListPanel is already the 96% content column, so rows fill it
            --entirely and line up with the zone-type rows above.
            width = "100%",
            height = 36,
            halign = "center",
            flow = "horizontal",
            bgimage = true,
            pad = 4,
            borderBox = true,
            vmargin = 1,

            data = {
                zoneid = entry.zoneid,
            },

            --NOTE: a bare `tooltip = "..."` arg on a plain gui.Panel eagerly
            --constructs an orphaned tooltip label at create time ("was created
            --but not attached to a parent" on game entry); the idiom for
            --hover tooltips on panels is gui.Tooltip as the hover handler.
            hover = gui.Tooltip(cond(entry.calculated == true,
                string.format("Calculated from %s, cannot be directly edited. Click to show it on the map.", entry.calculatedSource or "the map"),
                "Click to select this zone and show it on the map. Right-click for options.")),

            press = function(element)
                if entry.calculated == true then
                    --read-only: nothing to select or arm, just show it.
                    MM.JumpToZone(entry)
                    return
                end
                m.zoneTargetId = entry.zoneid
                --also select the matching type chip so continued painting
                --extends this zone rather than switching types. (A hole
                --target id is inert at paint time -- painting always cuts a
                --new hole -- but the chip selection keeps the tool on holes.)
                for i,paletteEntry in ipairs(m.zonePaletteEntries) do
                    if entry.hole == true then
                        if paletteEntry.kind == "hole" then
                            m.zoneSelectedType = i
                            break
                        end
                    elseif paletteEntry.keywordid ~= nil and paletteEntry.keywordid == entry.keywordid then
                        m.zoneSelectedType = i
                        break
                    end
                end
                zonePalettePanel:FireEvent("refreshchips")
                RefreshZoneUI()
                --pan to the zone and pulse a highlight over its tiles.
                MM.JumpToZone(entry)
                --selecting a zone sets the paint target, so arm the tool too.
                MM.TakeMarkupFocus()
            end,

            rightClick = function(element)
                if entry.calculated == true then
                    return
                end
                --holes have nothing to edit (no name/height/visibility), so
                --their menu is delete-only.
                local menuEntries = {}
                if entry.hole ~= true then
                    menuEntries[#menuEntries+1] = {
                        text = "Edit Zone...",
                        click = function()
                            element.popup = nil
                            ShowZoneDialog(entry, element)
                        end,
                    }
                end
                menuEntries[#menuEntries+1] = {
                    text = cond(entry.hole == true, "Delete Hole", "Delete Zone"),
                    click = function()
                        element.popup = nil
                        local floor = game.currentFloor
                        if floor ~= nil then
                            floor:RemoveMarkupZone(entry.zoneid)
                            if m.zoneTargetId == entry.zoneid then
                                m.zoneTargetId = nil
                            end
                            RefreshZoneUI()
                        end
                    end,
                }
                element.popup = gui.ContextMenu{
                    entries = menuEntries,
                }
            end,

            gui.Panel{
                width = 28,
                height = 28,
                valign = "center",
                bgimage = true,
                bgcolor = rowSwatchColor,
                gradient = rowGradient,
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Panel{
                --the Visuals badge (48 + 2+2 hmargin) comes off the text
                --column when present, on top of the standing 36 (swatch +
                --this column's margins).
                width = cond(rowHasVisuals, "100%-88", "100%-36"),
                height = "100%",
                flow = "vertical",
                hmargin = 4,

                gui.Label{
                    classes = {"bold", "sizeXs"},
                    text = displayName,
                    width = "100%",
                    height = "auto",
                },

                gui.Label{
                    classes = {"fgMuted", "sizeXs"},
                    text = table.concat(meta, ", "),
                    width = "100%",
                    height = "auto",
                },
            },

            --last positional entry: may be nil (no visuals for this type),
            --and a nil mid-constructor would hole the array.
            visualsBadge,
        }
    end

    --The floor's zones bucketed by zone TYPE, in the order the types first
    --appear in the (ord-sorted) list, with each bucket's zones still in ord
    --order. Grouping is what makes a long list legible - a floor with a dozen
    --zones is nearly always three or four types painted several times over -
    --and it is what the opacity slider hangs off, since fading is a property
    --of the type, not of one painted region.
    local GroupZonesOnFloor = function(floorid)
        local groups = {}
        local order = {}

        for _,entry in ipairs(MM.ZonesOnFloor(floorid)) do
            local key = m.zoneStripes.GroupKey(entry)
            local group = groups[key]
            if group == nil then
                group = {
                    key = key,
                    name = entry.keywordName or "Zone",
                    --the first zone's swatch stands for the group: colour and
                    --stripe angle are properties of the keyword, so every zone
                    --in the group looks the same on the map anyway.
                    patternColor = entry.patternColor,
                    patternAngle = entry.patternAngle,
                    entries = {},
                }
                groups[key] = group
                order[#order+1] = group
            end
            group.entries[#group.entries+1] = entry
        end

        --Holes group last: they live in their own cache (ZonesOnFloor must
        --stay keyword-only -- the paint/erase machinery iterates it), which
        --the ZonesOnFloor call above just refreshed. Sorted by id so the
        --list order is stable across rebuilds (hole records carry no ord).
        local holeEntries = {}
        for _,entry in ipairs(m.holes.cache) do
            if entry.floorid == floorid then
                holeEntries[#holeEntries+1] = entry
            end
        end
        if #holeEntries > 0 then
            table.sort(holeEntries, function(a, b)
                return a.zoneid < b.zoneid
            end)
            order[#order+1] = {
                key = m.holes.groupKey,
                name = "Hole",
                patternColor = m.holes.color,
                patternAngle = K.ZONE_ANGLE_A,
                entries = holeEntries,
            }
        end

        --Calculated zones last: read-only regions the engine derives from the
        --map (m.calculatedZones). Their own group, so the header can say what
        --they are and so no painted type's opacity slider implies control
        --over them (they are not in the overlay feed; the slider would be
        --dead).
        local calculated = m.calculatedZones.Entries(floorid)
        if #calculated > 0 then
            order[#order+1] = {
                key = m.calculatedZones.groupKey,
                name = "Calculated",
                calculated = true,
                patternColor = calculated[1].patternColor,
                patternAngle = calculated[1].patternAngle,
                entries = calculated,
            }
        end

        return order
    end

    --A group's header: the striped type swatch, the type name and how many
    --zones of it are on this floor, and the opacity slider that fades the
    --whole type on the map. Widths add up to exactly 100% (margins count in
    --horizontal flow), so nothing wraps as the panel is resized.
    local CreateZoneGroupHeader = function(group)
        local gradient = m.zoneStripes.Gradient(group.patternColor, group.patternAngle)
        local swatchColor = group.patternColor
        if gradient ~= nil then
            swatchColor = "white"
        end

        local ApplyOpacity = function(element)
            m.zoneStripes.SetOpacity(group.key, element.value)
        end

        --transient and local: nothing here is written to the map, a
        --setting or the players' clients. See m.zoneStripes.opacity.
        --Calculated groups get no slider: their zones are not drawn by the
        --overlay feed, so there is nothing to fade.
        local opacitySlider = nil
        if group.calculated ~= true then
            opacitySlider = gui.PercentSlider{
                width = 88,
                hmargin = 4,
                valign = "center",
                styles = m.zoneStripes.OpacitySliderStyles(),
                value = m.zoneStripes.Opacity(group.key),
                hover = gui.Tooltip("Fades this zone type on the map so you can see what is under it. A local viewing aid only - it is not saved, and players never see it."),
                --a drag fires 'preview' per frame and 'confirm' on release;
                --a click on the bar fires 'confirm' alone. All three land on
                --the same handler so the map tracks the bar live.
                preview = ApplyOpacity,
                change = ApplyOpacity,
                confirm = ApplyOpacity,
            }
        end

        return gui.Panel{
            width = "100%",
            height = 20,
            halign = "center",
            flow = "horizontal",
            vmargin = 3,

            --hmargin 4 lines the swatch up with the row swatches below, which
            --are inset by the chip's own pad of 4.
            gui.Panel{
                width = 14,
                height = 14,
                hmargin = 4,
                valign = "center",
                bgimage = true,
                bgcolor = swatchColor,
                gradient = gradient,
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Label{
                classes = {"markupSectionHeader"},
                text = string.format("%s (%d)", group.name, #group.entries),
                uppercase = true,
                --the slider (88 + 4+4 hmargin) comes off the label when
                --present, on top of the swatch's standing 22 (14 + 4+4).
                width = cond(group.calculated == true, "100%-22", "100%-118"),
                height = "auto",
                valign = "center",
                hover = cond(group.calculated == true,
                    gui.Tooltip("Zones the engine works out from the map itself rather than from painting. They cannot be edited here; change what they come from instead."),
                    nil),
            },

            --last positional entry: may be nil (calculated group), and a nil
            --mid-constructor would hole the array.
            opacitySlider,
        }
    end

    --Same icon-over-caption chips as the walls tool strip, with the eraser
    --behind a divider and tinted @danger.
    local BuildZoneToolButtons = function()
        local result = {}
        local dividerAdded = false
        for _,toolInfo in ipairs(K.ZONE_TOOLS) do
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
            if toolInfo.id == m.zoneToolId then
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
                    m.zoneToolId = element.data.toolid
                    zoneToolsPanel:FireEvent("refreshzonetools")
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

    zoneToolsPanel = gui.Panel{
        width = "96%",
        height = 48,
        halign = "center",
        flow = "horizontal",

        --keep the custom map tool alive: the engine expires custom tools
        --after ~1s, and every registration returns a fresh event source that
        --must be listened to again.
        thinkTime = 0.3,

        events = {
            refreshzonetools = function(element)
                for _,child in ipairs(element.children) do
                    child:SetClass("selected", child.data.toolid == m.zoneToolId)
                end
            end,

            think = function(element)
                if m.mode ~= "zones" or not MM.ZonesSupported() then
                    return
                end

                local toolInfo = MM.ZoneToolById(m.zoneToolId)
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
                if m.mode ~= "zones" or path == nil then
                    return
                end
                local toolInfo = MM.ZoneToolById(m.zoneToolId)
                if toolInfo == nil then
                    return
                end
                if toolInfo.erase then
                    element:FireEvent("zoneerase", path)
                else
                    element:FireEvent("zonepaint", path)
                end
            end,

            --closed stroke: rasterize to tiles and merge into the target zone
            --of the selected type (creating one when none exists).
            zonepaint = function(element, path)
                local floor = game.currentFloor
                if floor == nil or not MM.ZonesSupported() then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    if not ok then
                        dmhub.Debug("MARKUP:: zone painting needs an engine build with MapPath points support")
                    end
                    return
                end

                local locs = MM.PolygonToLocs(points)
                if #locs == 0 then
                    return
                end

                --the built-in Hole type: keep the drawn polygon and cut a
                --real hole instead of painting a keyword zone. None of the
                --keyword machinery below (dispels, contiguity merging)
                --applies to holes.
                local selectedEntry = m.zonePaletteEntries[m.zoneSelectedType]
                if selectedEntry ~= nil and selectedEntry.kind == "hole" then
                    m.holes.Paint(floor, points, locs)
                    RefreshZoneUI()
                    return
                end

                local keywordid = EnsureZoneTypeKeyword(m.zoneSelectedType)
                if keywordid == nil then
                    dmhub.Debug("MARKUP:: no valid zone type selected; stroke ignored")
                    return
                end

                --what the selected chip calls this type: used to name a new
                --zone (and to heal by name) when the keyword upload hasn't
                --landed locally yet.
                local fallbackInfo = nil
                local paletteEntry = m.zonePaletteEntries[m.zoneSelectedType]
                if paletteEntry ~= nil and paletteEntry.kind == "preset" then
                    local preset = K.ZONE_PRESETS_BY_KEY[paletteEntry.key]
                    if preset ~= nil then
                        fallbackInfo = { name = preset.name, color = preset.color }
                    end
                end

                --Dispel interactions with zones of OTHER types
                --(EnvironmentalKeyword.dispels), resolved at paint time by
                --editing the records: tiles of a type dispelled by the
                --painted type are DELETED where the stroke covers them, and
                --conversely the stroke cannot paint over a zone whose type
                --dispels the painted type (those tiles drop out of the
                --stroke). When two types dispel each other, the painted one
                --wins -- last drawn takes the ground.
                local paintedDispels = MM.KeywordDispels(MM.GetKeyword(keywordid))
                local dispelBlocked = {}
                for _,entry in ipairs(MM.ZonesOnFloor(floor.floorid)) do
                    if entry.keywordid ~= nil and entry.keywordid ~= keywordid
                        and paintedDispels[entry.keywordid] == nil
                        and MM.KeywordDispels(entry.keywordInfo)[keywordid] ~= nil then
                        for _,l in ipairs(entry.locs) do
                            dispelBlocked[MM.ZoneLocKey(l.x, l.y)] = true
                        end
                    end
                end
                if next(dispelBlocked) ~= nil then
                    local kept = {}
                    for _,l in ipairs(locs) do
                        if dispelBlocked[MM.ZoneLocKey(l.x, l.y)] == nil then
                            kept[#kept+1] = l
                        end
                    end
                    locs = kept
                    if #locs == 0 then
                        dmhub.Debug("MARKUP:: stroke entirely inside a zone type that dispels the painted type; nothing painted")
                        return
                    end
                end

                --Contiguity-based painting: the stroke joins the same-type
                --zones it overlaps or borders (bridging strokes unify them
                --into one record); a stroke touching none becomes its own
                --new zone. Non-contiguous results are auto-split, so one
                --zone record = one contiguous region on the map.
                local strokeSet = {}
                for _,l in ipairs(locs) do
                    strokeSet[MM.ZoneLocKey(l.x, l.y)] = true
                end

                --zones of a type the painted type dispels lose the stroke's
                --tiles (applied inside the stroke's transaction below).
                local dispelEdits = {}
                if next(paintedDispels) ~= nil then
                    for _,entry in ipairs(MM.ZonesOnFloor(floor.floorid)) do
                        if entry.keywordid ~= nil and entry.keywordid ~= keywordid
                            and paintedDispels[entry.keywordid] ~= nil then
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
                                dispelEdits[#dispelEdits+1] = { entry = entry, kept = kept }
                            end
                        end
                    end
                end

                local touched = {}
                for _,entry in ipairs(MM.ZonesOnFloor(floor.floorid)) do
                    if entry.keywordid == keywordid then
                        for _,l in ipairs(entry.locs) do
                            if strokeSet[MM.ZoneLocKey(l.x, l.y)]
                                or strokeSet[MM.ZoneLocKey(l.x + 1, l.y)]
                                or strokeSet[MM.ZoneLocKey(l.x - 1, l.y)]
                                or strokeSet[MM.ZoneLocKey(l.x, l.y + 1)]
                                or strokeSet[MM.ZoneLocKey(l.x, l.y - 1)] then
                                touched[#touched+1] = entry
                                break
                            end
                        end
                    end
                end

                if #touched == 0 then
                    --a (rare) self-intersecting freehand stroke can rasterize
                    --to several separate regions: one zone per region.
                    local components = MM.SplitContiguousComponents(locs)
                    dmhub.BeginTransaction()
                    for _,edit in ipairs(dispelEdits) do
                        --deletes emptied zones, splits bisected ones.
                        MM.WriteZoneLocsSplitting(floor, edit.entry, edit.kept)
                    end
                    for i,component in ipairs(components) do
                        local zoneid = MM.CreateZone(keywordid, component, fallbackInfo)
                        if i == 1 then
                            m.zoneTargetId = zoneid
                        end
                    end
                    dmhub.EndTransaction()
                else
                    --primary keeps its identity/settings: the targeted zone
                    --when the stroke touches it, else the largest touched.
                    local primary = nil
                    for _,entry in ipairs(touched) do
                        if primary == nil or #entry.locs > #primary.locs then
                            primary = entry
                        end
                    end
                    for _,entry in ipairs(touched) do
                        if entry.zoneid == m.zoneTargetId then
                            primary = entry
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
                    for _,entry in ipairs(touched) do
                        for _,l in ipairs(entry.locs) do
                            AddLoc(l.x, l.y)
                        end
                    end
                    for _,l in ipairs(locs) do
                        AddLoc(l.x, l.y)
                    end

                    dmhub.BeginTransaction()
                    for _,edit in ipairs(dispelEdits) do
                        --deletes emptied zones, splits bisected ones.
                        MM.WriteZoneLocsSplitting(floor, edit.entry, edit.kept)
                    end
                    for _,entry in ipairs(touched) do
                        if entry.zoneid ~= primary.zoneid then
                            floor:RemoveMarkupZone(entry.zoneid)
                        end
                    end
                    MM.WriteZoneLocsSplitting(floor, primary, newLocs)
                    dmhub.EndTransaction()

                    m.zoneTargetId = primary.zoneid
                end

                RefreshZoneUI()
            end,

            --eraser stroke: remove the region's tiles from every zone on the
            --floor; zones left empty are deleted. One undo step per stroke.
            zoneerase = function(element, path)
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
                for _,entry in ipairs(MM.ZonesOnFloor(floor.floorid)) do
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
                        edits[#edits+1] = { entry = entry, kept = kept }
                    end
                end

                --holes erase by CLIPPING, like floor erasing: the erase
                --region is subtracted from each touched hole's polygons
                --(dmhub.ClipPolygons, Clipper-backed), so erasing across a
                --hole trims or bisects the shape rather than deleting it. A
                --rect erased from the middle leaves a donut ({points, holes}
                --entries); a fully covered hole deletes its record. The
                --stroke's own polygon is the clip region -- the geometric
                --shape, not the rasterized tiles the zone edits use. The
                --cache is fresh here (ZonesOnFloor ran EnsureZoneCache).
                --Fallback on engines without ClipPolygons: delete any hole
                --shape the region's tiles touch, whole.
                local holeEdits = {}
                local clipSupported = false
                pcall(function()
                    clipSupported = dmhub.ClipPolygons ~= nil
                end)
                if clipSupported then
                    local eraseRing = {}
                    for i = 1,#points do
                        eraseRing[i] = points[i]
                    end
                    for _,entry in ipairs(m.holes.cache) do
                        if entry.floorid == floor.floorid and #entry.polygons > 0 then
                            local ok, touched = pcall(function()
                                local inter = dmhub.ClipPolygons{
                                    subjects = entry.polygons,
                                    clips = { eraseRing },
                                    operation = "intersection",
                                }
                                return #inter > 0
                            end)
                            if ok and touched then
                                local okDiff, clipped = pcall(function()
                                    return dmhub.ClipPolygons{
                                        subjects = entry.polygons,
                                        clips = { eraseRing },
                                        operation = "difference",
                                    }
                                end)
                                if okDiff and clipped ~= nil then
                                    holeEdits[#holeEdits+1] = { entry = entry, polygons = clipped }
                                end
                            end
                        end
                    end
                else
                    for _,entry in ipairs(m.holes.cache) do
                        if entry.floorid == floor.floorid then
                            for _,l in ipairs(entry.locs) do
                                if remove[MM.ZoneLocKey(l.x, l.y)] then
                                    holeEdits[#holeEdits+1] = { entry = entry, polygons = {} }
                                    break
                                end
                            end
                        end
                    end
                end

                if #edits == 0 and #holeEdits == 0 then
                    return
                end

                dmhub.BeginTransaction()
                for _,edit in ipairs(edits) do
                    --deletes emptied zones, and splits a zone the erase cut
                    --in half into separate records (one per region).
                    MM.WriteZoneLocsSplitting(floor, edit.entry, edit.kept)
                    if #edit.kept == 0 and m.zoneTargetId == edit.entry.zoneid then
                        m.zoneTargetId = nil
                    end
                end
                for _,edit in ipairs(holeEdits) do
                    if #edit.polygons == 0 then
                        floor:RemoveMarkupZone(edit.entry.zoneid)
                    else
                        floor:SetMarkupZone(edit.entry.zoneid, {
                            category = "hole",
                            polygons = edit.polygons,
                            locs = m.holes.EntryLocs(edit.polygons),
                        })
                    end
                end
                dmhub.EndTransaction()

                RefreshZoneUI()
            end,
        },

        children = BuildZoneToolButtons(),
    }

    zoneListPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        --cheap change detection: the records (any client) or the current
        --floor changing rebuilds the list.
        thinkTime = 0.5,

        data = {
            seq = nil,
            --the built-in tile-rules serial (walls, solids, floor patches,
            --object aura rebuilds, tilesheet edits): what moves the
            --calculated zones.
            logicSeq = nil,
            floorid = nil,
        },

        events = {
            think = function(element)
                if m.mode ~= "zones" or not MM.ZonesSupported() then
                    return
                end
                if dmhub.markupZonesSeq ~= element.data.seq or dmhub.tileRulesSeq ~= element.data.logicSeq or game.currentFloorId ~= element.data.floorid then
                    element:FireEvent("refreshzones")
                end
            end,

            refreshzones = function(element)
                if not MM.ZonesSupported() then
                    return
                end

                --split any legacy multi-region records first, THEN snapshot
                --the sequence: the snapshot includes the normalization writes,
                --so the think loop doesn't immediately re-fire this event.
                MM.NormalizeZonesOnFloor(game.currentFloorId)

                element.data.seq = dmhub.markupZonesSeq
                element.data.logicSeq = dmhub.tileRulesSeq
                element.data.floorid = game.currentFloorId

                --grouped by zone type, each group under its own header (which
                --carries the type's opacity slider).
                local children = {}
                if element.data.floorid ~= nil then
                    for _,group in ipairs(GroupZonesOnFloor(element.data.floorid)) do
                        children[#children+1] = CreateZoneGroupHeader(group)
                        for _,entry in ipairs(group.entries) do
                            children[#children+1] = CreateZoneRow(entry)
                        end
                    end
                end

                if #children == 0 then
                    children[#children+1] = gui.Label{
                        classes = {"fgMuted", "sizeXs"},
                        text = "No zones on this floor yet. Pick a zone type and paint on the map.",
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

    zonesPanel = gui.Panel{
        classes = {cond(m.mode ~= "zones", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        markupmode = function(element)
            element:SetClass("collapsed", m.mode ~= "zones")
            if m.mode == "zones" then
                zonePalettePanel:FireEvent("refreshzonepalette")
                zoneListPanel:FireEvent("refreshzones")
            end
        end,

        gui.Label{
            classes = {"fgMuted", cond(MM.ZonesSupported(), "collapsed")},
            text = "Zones need an engine build with markup zone support.",
            width = "90%",
            height = "auto",
            halign = "center",
            vmargin = 8,
            textAlignment = "center",
        },

        --Tool first, matching the walls tab: fixed controls at a stable
        --position on top, the growable type list below.
        MM.SectionHeader("Tool"),

        zoneToolsPanel,

        MM.SectionHeader("Zone Types"),

        zonePalettePanel,

        zoneAddButton,

        MM.SectionHeader("Zones on This Floor"),

        zoneListPanel,
    }


    return {
        panel = zonesPanel,
        toolPanel = zoneToolsPanel,
        prime = function()
            zonePalettePanel:FireEvent("refreshzonepalette")
            zoneListPanel:FireEvent("refreshzones")
        end,
    }
end
