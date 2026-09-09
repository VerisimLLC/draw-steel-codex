local mod = dmhub.GetModLoading()

--Dev gate for the map-pack browser ("...or Use an Existing Map") in the
--create-map dialog. No editor field, so it never appears in the settings UI;
--turn it on with: /set dev:patreonmaps true
setting{
    id = "dev:patreonmaps",
    description = "Show the map pack browser in the create map dialog.",
    default = false,
    storage = "preference",
}

--True if the map pack browser should be offered to this user.
local function PatreonMapsEnabled()
    return dmhub.GetSettingValue("dev:patreonmaps") == true
end

local function ComponentTypeMatches(value, componentType)
    if value == nil then
        return false
    end

    local text = tostring(value)
    return text == componentType or text == ("ObjectComponent" .. componentType)
end

local function ComponentField(component, field)
    local ok, value = pcall(function()
        return component[field]
    end)
    if ok then
        return value
    end

    return nil
end

local function ComponentMatches(component, key, componentType)
    if ComponentTypeMatches(key, componentType) then
        return true
    end

    return ComponentTypeMatches(ComponentField(component, "name"), componentType)
        or ComponentTypeMatches(ComponentField(component, "type"), componentType)
        or ComponentTypeMatches(ComponentField(component, "componentType"), componentType)
        or ComponentTypeMatches(ComponentField(component, "@class"), componentType)
end

local function ObjectNodeHasComponent(id, componentType)
    local node = id and assets:GetObjectNode(id)
    if node == nil or node.components == nil then
        return false
    end

    for key, component in pairs(node.components) do
        if ComponentMatches(component, key, componentType) then
            return true
        end
    end

    return false
end

mod.shared.ShowCreateMapDialog = function()

    --map packs are dev-gated; with them off the dialog is just the
    --empty/import choice and the name field.
    local packsEnabled = PatreonMapsEnabled()

    local selectedMap = nil
    --packs layout only: switches the main area between the blank / import /
    --library views when the sidebar selection changes.
    local m_setMainMode = nil
    --which main view is showing; BuildLibraryNav reads it to light the
    --active filter row when the rows arrive after the async pack sync.
    local m_mainMode = "empty"
    local m_packEntry = nil
    local m_packEntries = {}
    local m_search = ""
    local m_dialog = nil

    --fixed dialog geometry: a sources sidebar on the left, the library grid
    --in the middle and a docked preview pane on the right.
    local DIALOG_WIDTH = 1560
    local DIALOG_HEIGHT = 900
    local SIDEBAR_WIDTH = 270
    local PREVIEW_WIDTH = 400
    local FOOTER_HEIGHT = 72
    local HEADER_HEIGHT = 44
    --the hero composition (full map plus zoom windows) fits the pane width;
    --height is capped so the text below it stays in view.
    local DETAIL_IMAGE_W = PREVIEW_WIDTH - 24
    local DETAIL_IMAGE_H = 280
    --the grid shows this many fixed-size tile columns and scrolls.
    local GRID_COLUMNS = 5

    --community markup (Map Markup panel share icon): the shared markup sets
    --listed for the selected pack map, and the one chosen to add it with.
    local m_markupId = nil
    local m_markupMapKey = nil
    local markupHeading
    local markupList
    local markupStatus

    local m_mapName = "New Map"
    --the name the dialog last filled in by itself (a pack map's name), so a
    --user edit is kept when they switch tiles but an untouched name follows
    --the selection.
    local m_autoName = m_mapName

    --tile type is always squares for now.
    local tileType = "squares"

    local createButton
    local nameInput
    local packGrid
    local packStatus
    --builds the sidebar's library filter rows once the index has synced;
    --assigned in the packs-enabled branch below.
    local BuildLibraryNav = function() end

    --Patreon gating (see mod.shared.MapPackPatreonState): the creator record
    --of the selected pack map (name, website, campaign page), what the
    --create button currently does, and a fingerprint of the account's
    --Patreon state so a link or pledge landing while the dialog is open
    --refreshes the badges and the button by itself.
    local m_creator = nil
    local m_buttonMode = "create"
    local m_patreonSignature = nil

    --details pane (right of the grid): a title block, then a hero
    --composition (the full map fitted along one side, balanced by zoomed-in
    --windows into the same artwork), a meta line, tag chips, the Patreon
    --strip, and the appearance buttons.
    local detailTitle = gui.Label{ classes = {"mapPackDetailTitle"}, text = "" }
    local detailCreator = gui.Label{ classes = {"mapPackDetailByline"}, text = "" }
    --rebuilt on every selection: the hero's geometry follows the map's aspect.
    local detailHero = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 10,
    }
    --the Patreon strip: the glyph plus what the selected appearance needs,
    --or that the account's membership covers it, on a raised accent-edged bar.
    local detailAccessIcon = gui.Panel{
        classes = {"mapPackPatreonIcon"},
        width = 16,
        height = 16,
        valign = "top",
        vmargin = 2,
    }
    local detailAccessText = gui.Label{
        classes = {"mapPackDetailText"},
        width = "100%-24",
        vmargin = 0,
        text = "",
    }
    local detailAccess = gui.Panel{
        classes = {"mapPackAccessStrip", "hidden"},
        --the accent edge is the strip's own background: the inner panel
        --covers all but a 3px sliver at the left, whatever the text height.
        gui.Panel{
            classes = {"mapPackAccessInner"},
            detailAccessIcon,
            detailAccessText,
        },
    }
    local detailInfo = gui.Label{ classes = {"mapPackDetailMeta"}, text = "" }
    local detailTags = gui.Panel{
        classes = {"hidden"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        halign = "left",
        tmargin = 6,
    }
    local appearancesHeading = gui.Panel{
        classes = {"hidden"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 14,
        bmargin = 2,
        gui.Label{ classes = {"mapPackSectionLabel"}, text = "Appearances" },
        gui.Panel{ classes = {"mapPackSectionRule"} },
    }
    local variantsPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        halign = "left",
        tmargin = 4,
    }
    --thumbnail prefetch: binding a sibling variant's thumb to an invisible
    --1x1 panel makes the engine download and cache it while the user is
    --still looking at the current appearance, so switching appearances
    --shows the new image immediately instead of waiting on the download.
    local detailPrefetch = gui.Panel{
        floating = true,
        width = 1,
        height = 1,
        opacity = 0,
        interactable = false,
    }

    --"Codex Enhancements" with the Codex logo beside it.
    markupHeading = gui.Panel{
        classes = {"hidden"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        vmargin = 8,
        gui.Panel{
            width = 18,
            height = 18,
            halign = "left",
            valign = "center",
            rmargin = 6,
            bgimage = "ui-icons/codex-logo.png",
            bgcolor = "white",
        },
        gui.Label{
            classes = {"mapPackDetailText"},
            width = "auto",
            vmargin = 0,
            halign = "left",
            valign = "center",
            bold = true,
            text = "Codex Enhancements",
        },
    }
    markupStatus = gui.Label{
        classes = {"mapPackDetailText", "hidden"},
        fontSize = 12,
        text = "Choose a set to add the map with that markup, or none for the plain map.",
    }
    --a plain list: the details pane already scrolls, and a nested vscroll
    --container resolves its rows' "100%" against a wider basis than its
    --siblings, spilling them past the pane's right border.
    markupList = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
    }

    --the preview pane docks right of the grid and is always present; a
    --placeholder fills it until a pack map is selected.
    local previewPlaceholder = gui.Panel{
        width = "100%",
        height = "auto",
        valign = "center",
        flow = "vertical",
        gui.Panel{
            classes = {"cmPreviewGlyph"},
            bgimage = "phosphor/book-open.png",
        },
        gui.Label{
            classes = {"mapPackDetailText"},
            width = "80%",
            halign = "center",
            textAlignment = "center",
            vmargin = 10,
            text = "Select a map to preview it here.",
        },
    }
    --the scroll container spans almost the whole pane so its scrollbar sits
    --against the right border; the inner column restores the content inset.
    local detailContent = gui.Panel{
        classes = {"hidden"},
        width = "100%-2",
        height = "100%-16",
        halign = "center",
        valign = "top",
        vmargin = 8,
        vscroll = true,
        flow = "vertical",
        gui.Panel{
            width = "100%-22",
            height = "auto",
            halign = "center",
            flow = "vertical",
            detailTitle,
            detailCreator,
            detailHero,
            detailInfo,
            detailTags,
            detailAccess,
            appearancesHeading,
            variantsPanel,
            detailPrefetch,
            markupHeading,
            markupStatus,
            markupList,
        },
    }
    local detailPanel = gui.Panel{
        classes = {"cmPreview"},
        width = PREVIEW_WIDTH,
        height = "100%",
        valign = "top",
        previewPlaceholder,
        detailContent,
    }

    local SelectPackEntry

    local SameMap = function(a, b)
        return a ~= nil and b ~= nil and a.pack == b.pack and a.id == b.id
    end

    local SameEntry = function(a, b)
        return SameMap(a, b) and a.variantIndex == b.variantIndex
    end

    --"12 walls, 3 zones, 2 footstep regions, 1 prop" for a shared markup set.
    local MarkupPartsText = function(info)
        local parts = {}
        local function add(n, singular, plural)
            if n > 0 then
                parts[#parts + 1] = string.format("%d %s", n, cond(n == 1, singular, plural))
            end
        end
        add(info.walls, "wall", "walls")
        add(info.zones, "zone", "zones")
        add(info.footsteps, "footstep region", "footstep regions")
        if info.footstepDefault and info.footsteps == 0 then
            parts[#parts + 1] = "footstep default"
        end
        add(info.props, "prop", "props")
        add(info.elevation, "elevation area", "elevation areas")
        if #parts == 0 then
            return "settings only"
        end
        return table.concat(parts, ", ")
    end

    --the status line is static (a changing line reflows the pane); the
    --checked row itself shows what will be added. This only drops a
    --selection whose row no longer exists.
    local RefreshMarkupStatus = function()
        if m_markupId == nil then
            return
        end
        for _, row in ipairs(markupList.children) do
            if row.data.info.id == m_markupId then
                return
            end
        end
        m_markupId = nil
    end

    local RefreshMarkupList
    local MarkupRow = function(info)
        --checkmark at the row's right edge; the slot always takes its space
        --so nothing shifts on selection, and only the selected row shows it.
        local checkPanel = gui.Panel{
            classes = {"mapPackMarkupCheck", cond(info.id == m_markupId, "checked")},
            bgimage = "phosphor/check-bold.png",
        }
        local row
        row = gui.Panel{
            classes = {"mapPackMarkupRow", cond(info.id == m_markupId, "selected")},
            data = { info = info, check = checkPanel },
            flow = "vertical",
            press = function(element)
                if m_markupId == info.id then
                    m_markupId = nil
                else
                    m_markupId = info.id
                end
                for _, other in ipairs(markupList.children) do
                    local selected = other.data.info.id == m_markupId
                    other:SetClass("selected", selected)
                    other.data.check:SetClass("checked", selected)
                end
                RefreshMarkupStatus()
            end,

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                gui.Label{
                    classes = {"mapPackMarkupAuthor"},
                    text = cond(info.author ~= "", info.author, "Anonymous"),
                },
                gui.Label{
                    classes = {"mapPackMarkupParts"},
                    text = MarkupPartsText(info),
                },
                --the uploader can take their own set down again.
                gui.Panel{
                    classes = {"iconButton", cond(info.mine, nil, "hidden")},
                    bgimage = "phosphor/trash-fill.png",
                    width = 16,
                    height = 16,
                    halign = "right",
                    valign = "center",
                    --the row's press selects the set; deleting must not.
                    swallowPress = true,
                    hover = gui.Tooltip("Delete your shared markup"),
                    press = function(element)
                        gui.ModalMessage{
                            title = "Delete Shared Markup",
                            message = "Remove this markup set for everyone? This cannot be undone.",
                            options = {
                                {
                                    text = "Delete",
                                    execute = function()
                                        mappacks.DeleteMarkup{
                                            pack = info.pack,
                                            mapid = info.mapid,
                                            id = info.id,
                                            success = function()
                                                if m_markupId == info.id then
                                                    m_markupId = nil
                                                end
                                                m_markupMapKey = nil
                                                RefreshMarkupList()
                                            end,
                                            error = function(msg)
                                                gui.ModalMessage{ title = "Could not delete", message = msg }
                                            end,
                                        }
                                    end,
                                },
                                {
                                    text = "Cancel",
                                },
                            },
                        }
                    end,
                },
                checkPanel,
            },
            gui.Label{
                classes = {"mapPackMarkupDescription", cond(info.description ~= "", nil, "collapsed")},
                text = info.description,
            },
        }
        return row
    end

    --lists the markup sets shared for the selected map; fetched once per map
    --(variants of one map share its list) and cleared when nothing is
    --selected.
    RefreshMarkupList = function()
        local entry = m_packEntry
        local key = nil
        if entry ~= nil then
            key = entry.pack .. "/" .. entry.id
        end
        if key == m_markupMapKey then
            return
        end
        m_markupMapKey = key
        m_markupId = nil
        markupList.children = {}
        markupHeading:SetClass("hidden", true)
        markupStatus:SetClass("hidden", true)
        if entry == nil then
            return
        end

        mappacks.ListMarkup{
            pack = entry.pack,
            mapid = entry.id,
            success = function(list)
                if m_markupMapKey ~= key or not markupList.valid then
                    return
                end
                if #list == 0 then
                    return
                end
                local rows = {}
                for _, info in ipairs(list) do
                    rows[#rows + 1] = MarkupRow(info)
                end
                markupList.children = rows
                markupHeading:SetClass("hidden", false)
                markupStatus:SetClass("hidden", false)
                RefreshMarkupStatus()
            end,
            error = function(msg)
                if m_markupMapKey ~= key or not markupList.valid then
                    return
                end
                markupHeading:SetClass("hidden", false)
                markupStatus:SetClass("hidden", false)
                markupStatus.text = "Could not load shared markup: " .. tostring(msg)
            end,
        }
    end

    --the index's current record for an entry (each search evaluates the
    --owned flag live against the account's pledges), or the entry itself if
    --it is no longer listed.
    local FreshEntry = function(entry)
        for _, other in ipairs(mappacks.Search{ text = "", pack = entry.pack, maxResults = 100000 }) do
            if SameEntry(other, entry) then
                return other
            end
        end
        return entry
    end

    --a fingerprint of everything the Patreon gating depends on, so a change
    --(account linked, pledge landing or lapsing) can be noticed by polling.
    local PatreonSignature = function()
        local parts = {}
        for _, e in ipairs(dmhub.patreonOrgEntitlements or {}) do
            parts[#parts + 1] = string.format("%s:%s:%d", tostring(e.orgid), tostring(e.entitled), tonumber(e.cents) or 0)
        end
        table.sort(parts)
        table.insert(parts, 1, tostring(dmhub.patreonUserId))
        return table.concat(parts, "|")
    end

    --every index entry for the same map as entry, in variant order. Taken
    --from the whole index rather than the grid, which only shows one
    --variant per map unless a search asked for more.
    local SiblingVariants = function(entry)
        local result = {}
        for _, other in ipairs(mappacks.Search{ text = "", pack = entry.pack, maxResults = 100000 }) do
            if SameMap(other, entry) then
                result[#result + 1] = other
            end
        end
        table.sort(result, function(a, b) return a.variantIndex < b.variantIndex end)
        return result
    end

    --the entries the grid shows for a search result. Without a search each
    --map appears once, as its lowest-numbered variant. With a search every
    --matching variant is kept but ordered so a not-yet-seen map always comes
    --before another variant of a map already listed. Within a map the
    --variants are ranked by how well they matched (matchScore from the
    --engine: whole-word keyword hits outrank prefix hits like "cave" on
    --"cavern"), so a search shows the variant that earned the match rather
    --than the map's base appearance; maps in turn are ranked by their best
    --variant. Variant index breaks ties, so an empty search (every score 0)
    --keeps index order.
    local BetterMatch = function(a, b)
        local sa = a.matchScore or 0
        local sb = b.matchScore or 0
        if sa ~= sb then
            return sa > sb
        end
        return a.variantIndex < b.variantIndex
    end

    local DiversifyEntries = function(entries, searching)
        local byMap = {}
        local order = {}
        for _, entry in ipairs(entries) do
            local key = entry.pack .. "/" .. entry.id
            local group = byMap[key]
            if group == nil then
                group = {}
                byMap[key] = group
                order[#order + 1] = group
            end
            group[#group + 1] = entry
        end

        for _, group in ipairs(order) do
            table.sort(group, BetterMatch)
        end

        --stable: groups whose best variants tie keep their index order.
        for i, group in ipairs(order) do
            group.ord = i
        end
        table.sort(order, function(a, b)
            local sa = a[1].matchScore or 0
            local sb = b[1].matchScore or 0
            if sa ~= sb then
                return sa > sb
            end
            return a.ord < b.ord
        end)

        local result = {}
        local round = 1
        local added = true
        while added do
            added = false
            for _, group in ipairs(order) do
                if group[round] ~= nil then
                    result[#result + 1] = group[round]
                    added = true
                end
            end
            round = round + 1
            if not searching then
                break
            end
        end
        return result
    end

    local UpdateCreateButton

    --the hero composition for the selected map: the full map fitted along
    --its long axis inside DETAIL_IMAGE_W x DETAIL_IMAGE_H, balanced by
    --three zoomed-in windows into the same thumbnail. A tall map gets the
    --zooms stacked beside it; a wide or squarish one gets them in a row
    --underneath.
    local HERO_GAP = 8

    --a zoom window: a tileW x tileH panel showing an fw x fh fraction of the
    --map image, aspect-matched to the tile ((fw * w) / (fh * h) ==
    --tileW / tileH) so nothing stretches. The three windows split the map's
    --long axis (the given one) into thirds: window seg (0..2) rests at the
    --start of its third and, while hovered, glides through it with the same
    --eased cosine swing the grid tiles use, easing home on mouse-out.
    local HeroZoom = function(thumb, tileW, tileH, fw, fh, axis, seg, alignArg)
        --an extreme aspect can push a fraction past 1; shrink both so the
        --window stays aspect-true.
        if fw > 1 then
            fh = fh / fw
            fw = 1
        end
        if fh > 1 then
            fw = fw / fh
            fh = 1
        end

        --the patrol along the long axis: from the third's start to its end,
        --less the window's own extent. A window bigger than its third does
        --not pan; it just pins near the spread position.
        local f = cond(axis == "y", fh, fw)
        local segLen = 1 / 3
        local range = segLen - f
        local restCenter
        if range > 0 then
            restCenter = seg * segLen + f / 2
        else
            range = 0
            restCenter = math.max(f / 2, math.min(1 - f / 2, (seg + 0.5) * segLen))
        end

        local RectFor = function(offset)
            local c = restCenter + offset
            if axis == "y" then
                return { x1 = 0.5 - fw / 2, y1 = c - fh / 2, x2 = 0.5 + fw / 2, y2 = c + fh / 2 }
            end
            return { x1 = c - fw / 2, y1 = 0.5 - fh / 2, x2 = c + fw / 2, y2 = 0.5 + fh / 2 }
        end

        --the swing period matches the grid tiles' feel: the fraction range
        --scaled by the zoomed image's on-screen extent gives pixels.
        local tilePx = cond(axis == "y", tileH, tileW)
        local tuning = mod.shared.MapPackPanTuning
        local panPeriod = math.max(tuning.minPeriod, 2 * (range * tilePx / f) / tuning.speed)
        --the eased return stops thinking under half an on-screen pixel.
        local panEpsilon = 0.5 * f / tilePx
        local panOffset = 0
        local panStart = nil   --time the current swing began (nil = not hovered)
        local lastThink = nil

        return gui.Panel{
            classes = {"mapPackHeroZoom"},
            width = tileW,
            height = tileH,
            halign = alignArg,
            bgimage = thumb,
            imageRect = RectFor(0),
            hover = function(element)
                if range <= 0 then
                    return
                end
                --resume the swing from wherever the glide-back left us so
                --the image never jumps: invert offset = range*(1-cos)/2.
                local phase = math.acos(1 - 2 * math.min(1, panOffset / range))
                panStart = dmhub.Time() - phase * panPeriod / (2 * math.pi)
                lastThink = dmhub.Time()
                element.thinkTime = 0.01
            end,
            dehover = function(element)
                panStart = nil
            end,
            think = function(element)
                local now = dmhub.Time()
                if panStart ~= nil then
                    local phase = (now - panStart) * 2 * math.pi / panPeriod
                    panOffset = range * (1 - math.cos(phase)) / 2
                else
                    --ease back to the third's start, then stop thinking.
                    local dt = now - (lastThink or now)
                    panOffset = panOffset * math.exp(-dt * tuning.returnRate)
                    if panOffset < panEpsilon then
                        panOffset = 0
                        element.thinkTime = nil
                    end
                end
                lastThink = now
                element.imageRect = RectFor(panOffset)
            end,
        }
    end

    local BuildHero = function(entry)
        local w = tonumber(entry.tilesW) or 1
        local h = tonumber(entry.tilesH) or 1
        if w < 1 then w = 1 end
        if h < 1 then h = 1 end
        local thumb = mod.shared.MapPackThumbImage(entry)

        --price pill on the map's corner while the appearance is gated
        --behind a pledge the account lacks.
        local pill = nil
        if mod.shared.MapPackPatreonState(entry) == "locked" then
            local price = mod.shared.MapPackTierText(entry.tier):gsub("/month", "/mo")
            pill = gui.Panel{
                classes = {"mapPackHeroPill"},
                floating = true,
                gui.Panel{ classes = {"mapPackHeroPillIcon"} },
                gui.Label{ classes = {"mapPackHeroPillText"}, text = price },
            }
        end

        local fitW = DETAIL_IMAGE_H * w / h
        if fitW <= DETAIL_IMAGE_W - 128 then
            --tall map: full map at the left, zooms in a right-hand column.
            local imgW = math.floor(fitW)
            local zoomW = DETAIL_IMAGE_W - imgW - HERO_GAP
            local zoomH = math.floor((DETAIL_IMAGE_H - 2 * HERO_GAP) / 3)
            local fh = 0.16
            local fw = fh * (zoomW / zoomH) * (h / w)
            return gui.Panel{
                width = "100%",
                height = DETAIL_IMAGE_H,
                flow = "horizontal",
                gui.Panel{
                    classes = {"mapPackHeroImage"},
                    width = imgW,
                    height = DETAIL_IMAGE_H,
                    halign = "left",
                    bgimage = thumb,
                    pill,
                },
                gui.Panel{
                    width = zoomW,
                    height = "100%",
                    halign = "right",
                    flow = "vertical",
                    HeroZoom(thumb, zoomW, zoomH, fw, fh, "y", 0, "right"),
                    gui.Panel{ width = 1, height = HERO_GAP },
                    HeroZoom(thumb, zoomW, zoomH, fw, fh, "y", 1, "right"),
                    gui.Panel{ width = 1, height = HERO_GAP },
                    HeroZoom(thumb, zoomW, zoomH, fw, fh, "y", 2, "right"),
                },
            }
        end

        --wide or squarish map: full map on top, zooms in a row underneath.
        local zoomH = 88
        local imgH = math.floor(DETAIL_IMAGE_W * h / w)
        local imgW = DETAIL_IMAGE_W
        if imgH > DETAIL_IMAGE_H - zoomH - HERO_GAP then
            imgH = DETAIL_IMAGE_H - zoomH - HERO_GAP
            imgW = math.floor(imgH * w / h)
        end
        local zoomW = math.floor((DETAIL_IMAGE_W - 2 * HERO_GAP) / 3)
        local fw = 0.16
        local fh = fw * (zoomH / zoomW) * (w / h)
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Panel{
                classes = {"mapPackHeroImage"},
                width = imgW,
                height = imgH,
                halign = "center",
                bgimage = thumb,
                pill,
            },
            gui.Panel{
                width = "100%",
                height = zoomH,
                flow = "horizontal",
                halign = "left",
                tmargin = HERO_GAP,
                HeroZoom(thumb, zoomW, zoomH, fw, fh, "x", 0, "left"),
                gui.Panel{ width = HERO_GAP, height = 1 },
                HeroZoom(thumb, zoomW, zoomH, fw, fh, "x", 1, "left"),
                gui.Panel{ width = HERO_GAP, height = 1 },
                HeroZoom(thumb, zoomW, zoomH, fw, fh, "x", 2, "left"),
            },
        }
    end

    --an appearance button: the variant's name on a raised two-column row.
    --No lock glyph here: the Patreon strip above already says whether the
    --selection is gated.
    local CreateVariantButton = function(sibling, selected)
        return gui.Panel{
            classes = {"mapPackVariantButton", cond(selected, "selected")},
            data = { entry = sibling },
            press = function(element)
                SelectPackEntry(element.data.entry)
            end,
            gui.Label{
                classes = {"mapPackVariantLabel"},
                interactable = false,
                text = cond(sibling.variant ~= "", sibling.variant, "Default"),
            },
        }
    end

    --the Patreon line for the selected appearance; hidden for a free one.
    local RefreshAccessLine = function()
        local entry = m_packEntry
        local state = nil
        if entry ~= nil then
            state = mod.shared.MapPackPatreonState(entry)
        end
        detailAccess:SetClass("hidden", state == nil)
        if state == nil then
            return
        end

        local creatorName = nil
        if m_creator ~= nil then
            creatorName = m_creator.displayName
        end
        local text = mod.shared.MapPackPatreonText(entry, creatorName)
        if state == "locked" then
            local access = mappacks.GetPackAccess(entry.pack)
            if not access.linked then
                text = text .. ". Link your Patreon account to unlock it."
            elseif (access.cents or 0) > 0 then
                text = text .. string.format(". Your current pledge is %s.", mod.shared.MapPackTierText(access.cents))
            else
                text = text .. "."
            end
        else
            text = text .. "."
        end
        detailAccessIcon.bgimage = mod.shared.MapPackPatreonIcon(entry)
        detailAccessText.text = text
    end

    local RefreshDetails = function()
        local entry = m_packEntry
        detailContent:SetClass("hidden", entry == nil)
        previewPlaceholder:SetClass("hidden", entry ~= nil)
        RefreshMarkupList()
        if entry == nil then
            return
        end

        detailHero.children = { BuildHero(entry) }
        --the appearance buttons below say which variant is chosen, so the
        --title drops the " - Variant" suffix from the entry name.
        local title = entry.name
        if entry.variant ~= "" then
            local suffix = " - " .. entry.variant
            if title:sub(-#suffix) == suffix then
                title = title:sub(1, #title - #suffix)
            end
        end
        detailTitle.text = title
        detailCreator.text = ""
        m_creator = nil
        RefreshAccessLine()
        mod.shared.GetMapPackCreator(entry, function(info)
            --the lookup may land after the user moved on to another map.
            --(SameEntry rather than identity: a live refresh swaps the
            --selected entry for the index's fresh record of it.)
            if not SameEntry(m_packEntry, entry) or not detailCreator.valid then
                return
            end
            m_creator = info
            if info.displayName ~= nil and info.displayName ~= "" then
                detailCreator.text = "by " .. info.displayName
            end
            RefreshAccessLine()
            UpdateCreateButton()
        end)
        local summary = entry.description
        if summary == nil or summary == "" then
            summary = entry.sceneName
        end
        detailInfo.text = string.format("%s  -  %d x %d tiles", summary, entry.tilesW, entry.tilesH)
        --entry.keywords is the handful of representative tags; the long
        --searchTerms list only feeds the search box and is not shown.
        local tagPanels = {}
        for _, tag in ipairs(entry.keywords) do
            tagPanels[#tagPanels + 1] = gui.Panel{
                classes = {"mapPackTagChip"},
                gui.Label{
                    classes = {"mapPackTagText"},
                    text = tag:sub(1, 1):upper() .. tag:sub(2),
                },
            }
        end
        detailTags.children = tagPanels
        detailTags:SetClass("hidden", #tagPanels == 0)

        --a lone "Default" appearance button is noise; the section only
        --shows when there is a real choice.
        local buttons = {}
        local prefetch = {}
        for _, sibling in ipairs(SiblingVariants(entry)) do
            buttons[#buttons + 1] = CreateVariantButton(sibling, SameEntry(sibling, entry))
            if not SameEntry(sibling, entry) then
                prefetch[#prefetch + 1] = gui.Panel{
                    width = 1,
                    height = 1,
                    opacity = 0,
                    interactable = false,
                    bgimage = mod.shared.MapPackThumbImage(sibling),
                }
            end
        end
        variantsPanel.children = buttons
        detailPrefetch.children = prefetch
        appearancesHeading:SetClass("hidden", #buttons <= 1)
        variantsPanel:SetClass("hidden", #buttons <= 1)
    end

    local ClearPackSelection = function()
        m_packEntry = nil
        --no grid when the pack browser is gated off.
        if packGrid ~= nil then
            for _, tile in ipairs(packGrid.children) do
                tile:SetClass("selected", false)
            end
        end
        RefreshDetails()
    end

    --the button follows the selection: Create Map for a new map, Add Map for
    --a pack appearance the account may add, and for a gated one it lacks
    --access to, Link Patreon (no Patreon account attached: opens the Account
    --settings, which host the link flow) or Join Patreon (attached, but the
    --pledge does not cover it: opens the creator's Patreon page).
    UpdateCreateButton = function()
        local mode = "create"
        if m_packEntry ~= nil then
            mode = "add"
            if mod.shared.MapPackPatreonState(m_packEntry) == "locked" then
                local access = mappacks.GetPackAccess(m_packEntry.pack)
                mode = cond(access.linked, "join", "link")
            end
        end
        m_buttonMode = mode
        local labels = { create = "Create Map", add = "Add Map", link = "Link Patreon", join = "Join Patreon" }
        createButton.text = labels[mode]
    end

    --fill the name field from the selection unless the user typed their own.
    local SetAutoName = function(name)
        if m_mapName == m_autoName then
            m_mapName = name
            nameInput.text = name
        end
        m_autoName = name
    end

    local MapItemPress = function(element)
        selectedMap = element
        for _,el in ipairs(element.parent.children) do
            el:SetClass("selected", el == element)
        end
        ClearPackSelection()
        SetAutoName("New Map")
        UpdateCreateButton()
        if m_setMainMode ~= nil then
            m_setMainMode(element.data.type)
        end
    end

    SelectPackEntry = function(entry)
        m_packEntry = entry
        if selectedMap ~= nil and selectedMap.valid then
            for _, el in ipairs(selectedMap.parent.children) do
                el:SetClass("selected", false)
            end
        end
        --a variant chosen from the chips may not have its own tile; then
        --light the first tile the grid shows for that map instead.
        local litTile = nil
        for _, tile in ipairs(packGrid.children) do
            if SameEntry(tile.data.entry, entry) then
                litTile = tile
                break
            elseif litTile == nil and SameMap(tile.data.entry, entry) then
                litTile = tile
            end
        end
        for _, tile in ipairs(packGrid.children) do
            tile:SetClass("selected", tile == litTile)
        end
        SetAutoName(entry.sceneName ~= "" and entry.sceneName or entry.name)
        RefreshDetails()
        UpdateCreateButton()
    end

    --the grid scrolls but stays cheap: the search keeps only lightweight
    --index entries, and tiles (and their thumbnails) are built a chunk at a
    --time -- a Show More card at the end of the grid appends the next chunk.
    local cellW, cellH = mod.shared.MapPackTileCellSize()
    local GRID_CHUNK = GRID_COLUMNS * 6
    local m_shown = GRID_CHUNK

    --which pack the library sidebar has filtered to; nil is all packs.
    local m_packFilter = nil

    --only built with the pack browser itself; with the dev gate off nothing
    --would parent these.
    if packsEnabled then
        packGrid = gui.Panel{
            --a little slack so rounding never wraps the last column.
            width = GRID_COLUMNS * cellW + 4,
            --auto + maxHeight is what makes vscroll engage (same pattern as
            --markupList above); the cap is the content row's height.
            height = "auto",
            maxHeight = DIALOG_HEIGHT - 56 - FOOTER_HEIGHT - 12,
            flow = "horizontal",
            wrap = true,
            valign = "top",
            halign = "left",
            vscroll = true,
        }

        packStatus = gui.Label{
            classes = {"mapPackStatus"},
            text = "Syncing map packs...",
        }
    end

    --builds tiles for the entries shown so far, plus the Show More card
    --when more remain.
    local RenderTiles
    RenderTiles = function()
        local count = math.min(#m_packEntries, m_shown)
        local tiles = {}
        for i = 1, count do
            local entry = m_packEntries[i]
            local tile = mod.shared.CreateMapPackTile(entry, SelectPackEntry)
            tile:SetClass("selected", SameEntry(entry, m_packEntry))
            tiles[#tiles + 1] = tile
        end
        if #m_packEntries > count then
            --a tile-sized card so the grid rhythm holds; data = {} keeps
            --SelectPackEntry's tile.data.entry reads nil-safe.
            tiles[#tiles + 1] = gui.Panel{
                classes = {"cmShowMore"},
                data = {},
                flow = "vertical",
                press = function(element)
                    m_shown = m_shown + GRID_CHUNK
                    RenderTiles()
                end,
                gui.Label{
                    classes = {"cmShowMoreLabel"},
                    text = string.format("Show More\n%d of %d", count, #m_packEntries),
                },
            }
        end
        packGrid.children = tiles
    end

    local RefreshPackGrid = function()
        if m_dialog == nil or not m_dialog.valid or not mappacks.synced then
            return
        end

        --the full match list; entries are small tables and only the shown
        --chunk becomes widgets.
        local searching = m_search:match("%S") ~= nil
        m_packEntries = DiversifyEntries(mappacks.Search{
            text = m_search,
            pack = m_packFilter,
            maxResults = 100000,
        }, searching)

        --keep the selected variant if its map is still listed, even when
        --the grid shows a different variant of it.
        local stillSelected = nil
        local selectedIndex = nil
        for i, entry in ipairs(m_packEntries) do
            if SameEntry(entry, m_packEntry) then
                stillSelected = entry
                selectedIndex = i
                break
            elseif stillSelected == nil and SameMap(entry, m_packEntry) then
                stillSelected = FreshEntry(m_packEntry)
                selectedIndex = i
            end
        end

        if mappacks.count == 0 then
            packStatus.text = "No map packs are available yet."
        elseif #m_packEntries == 0 then
            packStatus.text = "No maps match your search."
        else
            --the grid shows one entry per map without a search, so count
            --maps rather than the index's variant entries.
            local mapCount = #DiversifyEntries(mappacks.Search{ text = "", pack = m_packFilter, maxResults = 100000 }, false)
            if searching then
                local matchedMaps = #DiversifyEntries(m_packEntries, false)
                packStatus.text = string.format("%d of %d maps", matchedMaps, mapCount)
            else
                packStatus.text = string.format("%d maps", mapCount)
            end
        end

        --a fresh list starts back at one chunk, grown as needed so a kept
        --selection is always among the built tiles.
        m_shown = GRID_CHUNK
        if selectedIndex ~= nil and selectedIndex > m_shown then
            m_shown = math.ceil(selectedIndex / GRID_CHUNK) * GRID_CHUNK
        end

        if stillSelected ~= nil then
            m_packEntry = stillSelected
            RenderTiles()
            SelectPackEntry(stillSelected)
        else
            if m_packEntry ~= nil then
                m_packEntry = nil
                RefreshDetails()
                UpdateCreateButton()
            end
            RenderTiles()
        end
    end

    local AddPackMap = function(entry, name, markupId)
        mappacks.AddMapToGame{
            pack = entry.pack,
            mapid = entry.id,
            variantIndex = entry.variantIndex,
            name = name,
            markupId = markupId,
            success = function(mapid)
                dmhub.Coroutine(function()
                    for i = 1, 200 do
                        if game.GetMap(mapid) ~= nil then
                            break
                        end
                        coroutine.yield(0.05)
                    end
                    local map = game.GetMap(mapid)
                    if map ~= nil then
                        map:Travel()
                    end
                end)
            end,
            error = function(msg)
                gui.ModalMessage{
                    title = "Could not add map",
                    message = msg,
                }
            end,
        }
    end

    nameInput = gui.Input{
        classes = {"form"},
        text = m_mapName,
        change = function(element)
            m_mapName = element.text
        end,
    }

    m_patreonSignature = PatreonSignature()

    createButton = gui.Button{
        classes = {"sizeL"},
        halign = "left",
        text = "Create Map",

        --the engine mirrors /Patrons live, so a Patreon link or a pledge
        --made while this dialog is open shows up here within seconds: the
        --grid is re-searched (fresh owned flags on every entry) and the
        --details and button follow.
        thinkTime = 0.5,
        think = function(element)
            local signature = PatreonSignature()
            if signature ~= m_patreonSignature then
                m_patreonSignature = signature
                RefreshPackGrid()
            end
        end,

        click = function(element)
            if m_buttonMode == "link" then
                --the Account tab of the settings hosts the Patreon link
                --flow. The settings sheet lives in the hud's dialog layer,
                --BELOW modals, so this dialog has to close first or the
                --settings open behind it (verified live 2026-09-05).
                gui.CloseModal()
                dmhub.ShowPlayerSettings{ tab = "Account" }
                return
            end
            if m_buttonMode == "join" then
                local url = nil
                if m_creator ~= nil then
                    url = m_creator.campaignUrl
                    if url == nil or url == "" then
                        url = m_creator.url
                    end
                end
                if url ~= nil and url ~= "" then
                    dmhub.OpenURL(url)
                else
                    gui.ModalMessage{
                        title = "Patreon",
                        message = "This creator has not listed a Patreon page yet.",
                    }
                end
                return
            end

            if m_packEntry ~= nil then
                local entry = m_packEntry
                local name = m_mapName
                local markupId = m_markupId
                gui.CloseModal()
                AddPackMap(entry, name, markupId)
                return
            end

            local mapType = selectedMap.data.type
            gui.CloseModal()

            if mapType == "import" then
                mod.shared.ImportMap{
                    tileType = tileType,
                    nofade = true,
                    finish = function(info)
                        mod.shared.FinishMapImport(m_mapName, info)
                    end,
                }
            else
                local guid = game.CreateMap{
                    description = m_mapName
                }

                dmhub.Coroutine(function()
                    while game.GetMap(guid) == nil do
                        coroutine.yield(0.05)
                    end

                    local map = game.GetMap(guid)
                    map:Travel()

                    while game.currentMapId ~= guid do
                        coroutine.yield(0.05)
                    end

                    dmhub.SetSettingValue("maplayout:tiletype", tileType)
                end)
            end
        end,
    }

	--the grid lays out each wrapped row by the tiles' own alignment; without
	--this a short row spreads its tiles across the full width.
	local tileStyles = mod.shared.MapPackTileStyles()
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackTile"},
		halign = "left",
	}

	--details-pane pieces: byline, hero image/zooms with the price pill, the
	--muted meta line, tag chips, the accent-edged Patreon strip, section
	--headers, and the two-column appearance buttons.
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackDetailByline"},
		fontSize = 12,
		color = "@fgMuted",
		width = "100%",
		height = "auto",
		tmargin = 2,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackHeroImage"},
		bgcolor = "white",
		cornerRadius = 6,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackHeroZoom"},
		bgcolor = "white",
		cornerRadius = 6,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackHeroPill"},
		bgimage = "panels/square.png",
		bgcolor = "#000000cc",
		cornerRadius = 10,
		width = "auto",
		height = "auto",
		flow = "horizontal",
		halign = "left",
		valign = "top",
		margin = 8,
		hpad = 8,
		vpad = 4,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackHeroPillIcon"},
		width = 12,
		height = 12,
		valign = "center",
		rmargin = 5,
		bgimage = "phosphor/patreon-logo-duotone.png",
		bgcolor = "white",
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackHeroPillText"},
		fontSize = 12,
		bold = true,
		color = "white",
		width = "auto",
		height = "auto",
		valign = "center",
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackDetailMeta"},
		fontSize = 13,
		color = "@fgMuted",
		width = "100%",
		height = "auto",
		textWrap = true,
		tmargin = 10,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackTagChip"},
		bgimage = "panels/square.png",
		bgcolor = "@bgRaised",
		cornerRadius = 8,
		width = "auto",
		height = "auto",
		halign = "left",
		hpad = 7,
		vpad = 2,
		rmargin = 4,
		vmargin = 2,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackTagText"},
		fontSize = 11,
		color = "@fgMuted",
		width = "auto",
		height = "auto",
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackAccessStrip"},
		bgimage = "panels/square.png",
		bgcolor = "@accent",
		cornerRadius = 4,
		width = "100%",
		height = "auto",
		flow = "horizontal",
		tmargin = 12,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackAccessInner"},
		bgimage = "panels/square.png",
		bgcolor = "@bgRaised",
		cornerRadius = 4,
		width = "100%-3",
		height = "auto",
		halign = "right",
		flow = "horizontal",
		pad = 10,
		borderBox = true,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackSectionLabel"},
		fontSize = 11,
		bold = true,
		uppercase = true,
		color = "@fgMuted",
		width = "auto",
		height = "auto",
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackSectionRule"},
		bgimage = "panels/square.png",
		bgcolor = "@border",
		opacity = 0.5,
		width = "100%",
		height = 1,
		tmargin = 4,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackVariantButton"},
		bgimage = "panels/square.png",
		bgcolor = "@bgRaised",
		cornerRadius = 6,
		width = "48%",
		height = 28,
		flow = "horizontal",
		halign = "left",
		margin = 3,
		hpad = 8,
		borderBox = true,
		borderWidth = 2,
		borderColor = "clear",
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackVariantButton", "hover"},
		borderColor = "@fgMuted",
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackVariantButton", "selected"},
		borderColor = "@accent",
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackVariantLabel"},
		fontSize = 12,
		width = "auto",
		height = "auto",
		valign = "center",
		halign = "left",
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackVariantLabel", "parent:selected"},
		bold = true,
	}

	--shared-markup rows under the details pane.
	--deselected rows read as grey and dim; the selected one gets the
	--accent border, full brightness and a checkmark in the left slot.
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackMarkupRow"},
		bgimage = "panels/square.png",
		bgcolor = "@bg",
		cornerRadius = 6,
		width = "100%",
		height = "auto",
		pad = 6,
		vmargin = 2,
		borderWidth = 1,
		borderColor = "@fgMuted",
		borderBox = true,
		opacity = 0.55,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackMarkupRow", "hover"},
		borderColor = "@fg",
		opacity = 0.8,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackMarkupRow", "selected"},
		borderWidth = 2,
		borderColor = "@accent",
		opacity = 1,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackMarkupCheck"},
		width = 16,
		height = 16,
		valign = "center",
		halign = "right",
		lmargin = 8,
		bgcolor = "@accent",
		opacity = 0,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackMarkupCheck", "checked"},
		opacity = 1,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackMarkupAuthor"},
		fontSize = 14,
		bold = true,
		width = "auto",
		height = "auto",
		valign = "center",
		halign = "left",
		rmargin = 8,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackMarkupParts"},
		fontSize = 12,
		width = "auto",
		height = "auto",
		valign = "center",
		halign = "left",
		opacity = 0.8,
	}
	tileStyles[#tileStyles + 1] = {
		selectors = {"mapPackMarkupDescription"},
		fontSize = 13,
		width = "100%",
		height = "auto",
		textWrap = true,
		vmargin = 2,
	}

    --sidebar, preview pane, footer and Show More styles for the picker
    --layout. All local to this dialog; nothing lands in DefaultStyles.
    --One quiet ground: the framedPanel surface runs under the whole dialog,
    --regions are separated by hairlines, and only hover/selected rows fill.
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmSidebar"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        border = {x1 = 0, x2 = 1, y1 = 0, y2 = 0},
        borderColor = "@border",
    }
    --the sidebar rows copy the Maps panel's list grammar exactly
    --(BuildMapListStyles in MapsPanel.lua): 34px quiet rows with hpad 12,
    --14px names, 13px bold section headers over a 0.35 hairline, 11px
    --muted counts, 0.2 seams.
    --width stops 1px short so a selected row's fill never paints over the
    --sidebar's right hairline.
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmNavItem"},
        flow = "horizontal",
        bgimage = "panels/square.png",
        bgcolor = "clear",
        width = "100%-1",
        height = 34,
        halign = "left",
        hpad = 12,
        borderBox = true,
    }
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmNavItem", "hover"},
        bgcolor = "@bgAlt",
        transitionTime = 0.1,
    }
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmNavItem", "selected"},
        bgcolor = "@bgAlt",
        border = {x1 = 3, x2 = 0, y1 = 0, y2 = 0},
        borderColor = "@accent",
        priority = 5,
    }
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmNavIcon"},
        width = 18,
        height = 18,
        valign = "center",
        rmargin = 8,
        bgcolor = "@fg",
    }
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmNavLabel"},
        fontSize = 14,
        color = "@fg",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
    }
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmNavLabel", "parent:selected"},
        bold = true,
        color = "@fgStrong",
    }
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmNavCount"},
        fontSize = 11,
        color = "@fgMuted",
        width = "auto",
        height = "auto",
        valign = "center",
        halign = "right",
    }
    --section header: the folder-header grammar (13px bold over a hairline).
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmNavSection"},
        fontSize = 13,
        bold = true,
        color = "@fg",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
    }
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmNavSectionHeader"},
        flow = "horizontal",
        bgimage = "panels/square.png",
        bgcolor = "clear",
        width = "100%",
        height = 30,
        tmargin = 8,
        hpad = 12,
        borderBox = true,
        halign = "left",
    }
    --the header's underline, a step brighter than row seams.
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmNavRule"},
        bgimage = "panels/square.png",
        bgcolor = "@border",
        opacity = 0.35,
        width = "100%",
        height = 1,
    }
    --seam between the source rows and the library section.
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmNavDivider"},
        bgimage = "panels/square.png",
        bgcolor = "@border",
        opacity = 0.2,
        width = "100%",
        height = 1,
        vmargin = 8,
    }
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmPreview"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        cornerRadius = 8,
        borderWidth = 1,
        borderColor = "@border",
    }
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmPreviewGlyph"},
        width = 44,
        height = 44,
        halign = "center",
        bgcolor = "@fgMuted",
    }
    --a hairline above the footer separates it from the grid row.
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmFooterDivider"},
        bgimage = "panels/square.png",
        bgcolor = "@border",
        opacity = 0.35,
        width = "100%",
        height = 1,
        valign = "bottom",
    }
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmFooter"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
    }
    --the Show More card sits in the grid at tile size so the rhythm holds.
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmShowMore"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        cornerRadius = 6,
        width = cellW - 12,
        height = cellH - 12,
        margin = 6,
        halign = "left",
        borderWidth = 1,
        borderColor = "@border",
    }
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmShowMore", "hover"},
        bgcolor = "@bgAlt",
        borderColor = "@accentHover",
        transitionTime = 0.1,
    }
    tileStyles[#tileStyles + 1] = {
        selectors = {"cmShowMoreLabel"},
        fontSize = 14,
        color = "@fg",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
    }

    if packsEnabled then
        --sidebar: the two creation sources (the same selection group the
        --old tiles formed: MapItemPress lights one and clears the other).
        local sourceNav = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            valign = "top",
            gui.Panel{
                classes = {"cmNavItem"},
                flow = "horizontal",
                press = MapItemPress,
                --stays the fallback creation type (a blank map) even while
                --the library view is the one showing.
                create = function(element)
                    selectedMap = element
                end,
                data = { type = "empty" },
                gui.Panel{ classes = {"cmNavIcon"}, halign = "left", bgimage = "phosphor/squares-four.png" },
                gui.Label{ classes = {"cmNavLabel"}, halign = "left", text = "Blank Map" },
            },
            gui.Panel{
                classes = {"cmNavItem"},
                flow = "horizontal",
                press = MapItemPress,
                data = { type = "import" },
                gui.Panel{ classes = {"cmNavIcon"}, halign = "left", bgimage = "phosphor/upload-simple-bold.png" },
                gui.Label{ classes = {"cmNavLabel"}, halign = "left", text = "Import Image or UVTT" },
            },
        }

        --library filters: All Maps plus one row per pack, labeled with the
        --creator's display name once the async lookup lands. Pressing one
        --brings the library view up in the main area (GoToLibrary, assigned
        --once the nav panels exist).
        local libraryNav
        local GoToLibrary
        local m_gridGeneration = 0
        local LibraryFilterItem = function(label, count, packid)
            local nameLabel = gui.Label{ classes = {"cmNavLabel"}, halign = "left", text = label }
            return gui.Panel{
                classes = {"cmNavItem"},
                flow = "horizontal",
                data = { pack = packid, label = nameLabel },
                press = function(element)
                    m_packFilter = element.data.pack
                    GoToLibrary()
                    --the row lights up and the view switches this frame;
                    --building the tile grid is deferred so the click feels
                    --instant and the maps fill in a moment later. A
                    --generation stamp makes rapid clicks rebuild only once.
                    m_gridGeneration = m_gridGeneration + 1
                    local generation = m_gridGeneration
                    dmhub.Schedule(0.01, function()
                        if generation == m_gridGeneration then
                            RefreshPackGrid()
                        end
                    end)
                end,
                gui.Panel{
                    classes = {"cmNavIcon"},
                    halign = "left",
                    bgimage = cond(packid == nil, "phosphor/book-open.png", "phosphor/user.png"),
                },
                nameLabel,
                gui.Label{ classes = {"cmNavCount"}, text = tostring(count) },
            }
        end

        libraryNav = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            valign = "top",
        }

        --shows the library in the main area: the sources unselect, the row
        --for the active filter lights, and the main view switches.
        GoToLibrary = function()
            for _, el in ipairs(sourceNav.children) do
                el:SetClass("selected", false)
            end
            for _, row in ipairs(libraryNav.children) do
                row:SetClass("selected", row.data.pack == m_packFilter)
            end
            if m_setMainMode ~= nil then
                m_setMainMode("library")
            end
        end

        local m_builtLibraryNav = false
        BuildLibraryNav = function()
            if m_builtLibraryNav or not mappacks.synced or not libraryNav.valid then
                return
            end
            m_builtLibraryNav = true
            local all = DiversifyEntries(mappacks.Search{ text = "", maxResults = 100000 }, false)
            local packOrder = {}
            local packInfo = {}
            for _, e in ipairs(all) do
                local info = packInfo[e.pack]
                if info == nil then
                    info = { count = 0, entry = e }
                    packInfo[e.pack] = info
                    packOrder[#packOrder + 1] = e.pack
                end
                info.count = info.count + 1
            end
            local rows = { LibraryFilterItem("All Maps", #all, nil) }
            --only worth filtering when there is more than one pack.
            if #packOrder > 1 then
                for _, packid in ipairs(packOrder) do
                    local info = packInfo[packid]
                    local row = LibraryFilterItem("Map Pack", info.count, packid)
                    rows[#rows + 1] = row
                    mod.shared.GetMapPackCreator(info.entry, function(creator)
                        if row.valid and creator ~= nil and (creator.displayName or "") ~= "" then
                            row.data.label.text = creator.displayName
                        end
                    end)
                end
            end
            libraryNav.children = rows
            --the rows arrive after the dialog opened; when the library view
            --is already showing, light the row for the active filter.
            if m_mainMode == "library" then
                for _, row in ipairs(rows) do
                    row:SetClass("selected", row.data.pack == m_packFilter)
                end
            end
        end

        --title-bar styles: the compact dock-panel header grammar (small
        --uppercase title beside an icon, actions at the right).
        tileStyles[#tileStyles + 1] = {
            selectors = {"cmHeader"},
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = "100%",
            height = HEADER_HEIGHT,
            hpad = 12,
            borderBox = true,
            halign = "left",
        }
        tileStyles[#tileStyles + 1] = {
            selectors = {"cmHeaderIcon"},
            width = 18,
            height = 18,
            valign = "center",
            rmargin = 8,
            bgcolor = "@fg",
        }
        tileStyles[#tileStyles + 1] = {
            selectors = {"cmHeaderTitle"},
            fontSize = 13,
            bold = true,
            uppercase = true,
            color = "@fgStrong",
            width = "auto",
            height = "auto",
            valign = "center",
        }
        tileStyles[#tileStyles + 1] = {
            selectors = {"cmClose"},
            width = 16,
            height = 16,
            valign = "center",
            bgcolor = "@fgMuted",
        }
        tileStyles[#tileStyles + 1] = {
            selectors = {"cmClose", "hover"},
            bgcolor = "@fgStrong",
        }

        --the full-width title bar: title at the left, search beside it, the
        --map count and close at the right.
        local headerBar = gui.Panel{
            classes = {"cmHeader"},
            --grouped so the bar's leftover width cannot spread the items
            --apart; the bar holds exactly a left group and a right group.
            gui.Panel{
                width = "auto",
                height = "100%",
                halign = "left",
                flow = "horizontal",
                gui.Panel{ classes = {"cmHeaderIcon"}, bgimage = "phosphor/map-trifold.png" },
                gui.Label{ classes = {"cmHeaderTitle"}, text = "Create Map" },
            },
            --anchored to the bar's right edge as a group, so the widths of
            --the title and search field can never push the close button out.
            gui.Panel{
                width = "auto",
                height = "100%",
                halign = "right",
                flow = "horizontal",
                --the status text sits LEFT of the search field on purpose:
                --this group hugs the right edge, so the rightmost items stay
                --pinned and the label's changing width grows into the empty
                --middle instead of shoving the search field around.
                packStatus,
                --the standard search field: magnifier, clear x, and the
                --shared searchInput look. It fires "search" with the
                --trimmed, lowercased text.
                gui.SearchInput{
                    width = 400,
                    valign = "center",
                    rmargin = 16,
                    placeholderText = "Search maps...",
                    search = function(element, str)
                        m_search = str
                        --typing a search means looking at the library.
                        if str ~= "" then
                            GoToLibrary()
                        end
                        RefreshPackGrid()
                    end,
                },
                gui.Panel{
                    classes = {"cmClose"},
                    bgimage = "phosphor/x-bold.png",
                    lmargin = 16,
                    press = function(element)
                        gui.CloseModal()
                    end,
                },
            },
        }

        local sidebar = gui.Panel{
            classes = {"cmSidebar"},
            width = SIDEBAR_WIDTH,
            height = "100%",
            flow = "vertical",
            gui.Panel{
                width = "100%",
                height = "auto",
                valign = "top",
                flow = "vertical",
                tmargin = 8,
                sourceNav,
                gui.Panel{ classes = {"cmNavDivider"} },
                gui.Panel{
                    classes = {"cmNavSectionHeader"},
                    gui.Label{ classes = {"cmNavSection"}, text = "Map Library" },
                },
                gui.Panel{ classes = {"cmNavRule"} },
                libraryNav,
            },
        }

        createButton.valign = "center"
        nameInput.valign = "center"

        --main-area views, toggled by the sidebar selection ------------------

        tileStyles[#tileStyles + 1] = {
            selectors = {"cmDropArea"},
            bgimage = "panels/square.png",
            bgcolor = "@bgAlt",
            width = "70%",
            height = "60%",
            halign = "center",
            valign = "center",
            cornerRadius = 12,
            borderWidth = 2,
            borderColor = "@border",
            flow = "vertical",
        }
        tileStyles[#tileStyles + 1] = {
            selectors = {"cmDropArea", "hover"},
            bgcolor = "@bgRaised",
            borderColor = "@accentHover",
            transitionTime = 0.1,
        }
        tileStyles[#tileStyles + 1] = {
            selectors = {"cmHint"},
            fontSize = 15,
            color = "@fgMuted",
            width = "auto",
            height = "auto",
            halign = "center",
            textAlignment = "center",
        }

        --hands dropped or picked files to the existing import wizard, which
        --skips its own drop screen when paths are supplied.
        local StartImportWithPaths = function(paths)
            if paths == nil or #paths == 0 then
                return
            end
            local name = m_mapName
            gui.CloseModal()
            mod.shared.ImportMap{
                tileType = tileType,
                nofade = true,
                paths = paths,
                finish = function(info)
                    mod.shared.FinishMapImport(name, info)
                end,
            }
        end

        local contentGeometry = {
            width = "100%-40",
            height = string.format("100%%-%d", FOOTER_HEIGHT + 24),
            halign = "center",
            valign = "top",
            tmargin = 12,
        }

        --the library: grid + preview (visible when a library row is picked).
        local libraryContent = gui.Panel{
            classes = {"collapsed"},
            width = contentGeometry.width,
            height = contentGeometry.height,
            halign = contentGeometry.halign,
            valign = contentGeometry.valign,
            tmargin = contentGeometry.tmargin,
            flow = "horizontal",
            gui.Panel{
                width = string.format("100%%-%d", PREVIEW_WIDTH + 10),
                height = "100%",
                halign = "left",
                valign = "top",
                packGrid,
            },
            detailPanel,
        }

        --blank map: just says what pressing Create Map will do.
        local blankContent = gui.Panel{
            width = contentGeometry.width,
            height = contentGeometry.height,
            halign = contentGeometry.halign,
            valign = contentGeometry.valign,
            tmargin = contentGeometry.tmargin,
            flow = "vertical",
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                flow = "vertical",
                gui.Panel{ classes = {"cmPreviewGlyph"}, bgimage = "phosphor/squares-four.png" },
                gui.Label{
                    classes = {"cmHint"},
                    vmargin = 12,
                    text = "An empty grid map.\nName it below and press Create Map.",
                },
            },
        }

        --import: the drop-or-browse screen, shown as soon as the source is
        --selected. Files go straight into the import pipeline.
        local importContent = gui.Panel{
            classes = {"collapsed"},
            width = contentGeometry.width,
            height = contentGeometry.height,
            halign = contentGeometry.halign,
            valign = contentGeometry.valign,
            tmargin = contentGeometry.tmargin,
            flow = "vertical",
            gui.Panel{
                classes = {"cmDropArea"},
                dragAndDropExtensions = {".png", ".jpg", ".jpeg", ".mp4", ".webm", ".webp", ".dd2vtt", ".uvtt", ".json"},
                dropfiles = function(element, paths)
                    StartImportWithPaths(paths)
                end,
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    flow = "vertical",
                    interactable = false,
                    gui.Panel{
                        classes = {"cmPreviewGlyph"},
                        interactable = false,
                        bgimage = "phosphor/upload-simple-bold.png",
                    },
                    gui.Label{
                        classes = {"cmHint"},
                        interactable = false,
                        vmargin = 12,
                        text = "Drop image, video, or vtt files here.\nMultiple files create a multi-floor map.",
                    },
                },
            },
            gui.Label{
                classes = {"cmHint"},
                vmargin = 10,
                text = "- or -",
            },
            gui.Button{
                classes = {"sizeL"},
                halign = "center",
                text = "Choose Files",
                click = function(element)
                    dmhub.OpenFileDialog{
                        id = "ObjectImagePath",
                        extensions = {"jpeg", "jpg", "png", "mp4", "webm", "webp", "dd2vtt", "uvtt", "json"},
                        multiFiles = true,
                        prompt = "Choose image, video, or vtt file to use as map.",
                        openFiles = function(paths)
                            StartImportWithPaths(paths)
                        end,
                    }
                end,
            },
        }

        local mainModePanels = {
            empty = blankContent,
            import = importContent,
            library = libraryContent,
        }
        m_setMainMode = function(mode)
            m_mainMode = mode
            for name, panel in pairs(mainModePanels) do
                panel:SetClass("collapsed", name ~= mode)
            end
            --leaving the library view unlights its rows, so only the
            --active source reads as selected.
            if mode ~= "library" then
                for _, row in ipairs(libraryNav.children) do
                    row:SetClass("selected", false)
                end
            end
        end
        --open on the library with All Maps active (m_packFilter starts nil);
        --the filter rows light themselves in BuildLibraryNav once synced.
        GoToLibrary()

        local main = gui.Panel{
            width = string.format("100%%-%d", SIDEBAR_WIDTH),
            height = "100%",
            flow = "vertical",

            blankContent,
            importContent,
            libraryContent,

            --footer action bar: the name travels with the commit buttons.
            gui.Panel{
                classes = {"cmFooter"},
                width = "100%",
                height = FOOTER_HEIGHT,
                valign = "bottom",
                flow = "horizontal",
                gui.Panel{
                    classes = {"cmFooterDivider"},
                    floating = true,
                    valign = "top",
                },
                gui.Label{
                    classes = {"form"},
                    width = "auto",
                    valign = "center",
                    hmargin = 20,
                    text = "Map Name:",
                },
                nameInput,
                --right-anchored group: immune to the name field's width and
                --the create button's changing labels (Add Map, Link Patreon).
                gui.Panel{
                    width = "auto",
                    height = "100%",
                    halign = "right",
                    flow = "horizontal",
                    gui.Button{
                        classes = {"sizeL"},
                        valign = "center",
                        hmargin = 12,
                        text = "Cancel",
                        escapeActivates = true,
                        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                        click = function(element)
                            gui.CloseModal()
                        end,
                    },
                    createButton,
                },
            },
        }

        m_dialog = gui.Panel{
            classes = {"framedPanel"},
            width = DIALOG_WIDTH,
            height = DIALOG_HEIGHT,
            --borderless: the modal reads as a sheet; the framedPanel class
            --still supplies the surface and rounded corners.
            borderWidth = 0,
            styles = ThemeEngine.MergeStyles(tileStyles),
            flow = "vertical",
            headerBar,
            gui.Panel{ classes = {"cmNavRule"} },
            gui.Panel{
                width = "100%",
                height = string.format("100%%-%d", HEADER_HEIGHT + 1),
                flow = "horizontal",
                sidebar,
                main,
            },
        }
    else
        --without the pack browser the dialog is just the two tiles, the
        --name field and the buttons, so it shrinks to fit them.
        m_dialog = gui.Panel{
            classes = {"framedPanel"},
            width = 700,
            height = 320,
            styles = ThemeEngine.MergeStyles(tileStyles),

            gui.Panel{
                width = "100%-24",
                height = "100%-32",
                halign = "center",
                valign = "center",

                flow = "vertical",

                gui.Label{
                    classes = {"modalTitle"},
                    text = "Create Map",
                    vmargin = 0,
                },

                gui.Panel{
                    flow = "horizontal",
                    halign = "center",
                    valign = "top",
                    width = "auto",
                    height = "auto",
                    vmargin = 8,

                    styles = ThemeEngine.MergeTokens({
                        {
                            selectors = {"mapItem"},
                            bgimage = true,
                            bgcolor = "@bg",
                            cornerRadius = 12,
                            width = 1920*0.1,
                            height = 1080*0.1,
                            halign = "center",
                            hmargin = 8,
                        },
                        {
                            selectors = {"mapItem", "hover"},
                            borderWidth = 2,
                            borderColor = "@accent",
                        },
                        {
                            selectors = {"mapItem", "selected"},
                            borderWidth = 2,
                            borderColor = "@fg",
                        },
                        {
                            selectors = {"mapText"},
                            fontSize = 14,
                            width = "auto",
                            height = "auto",
                            textAlignment = "center",
                        },
                    }),

                    gui.Panel{
                        classes = {"mapItem", "selected"},
                        press = MapItemPress,
                        create = function(element)
                            selectedMap = element
                        end,
                        data = {
                            type = "empty",
                        },
                        gui.Label{
                            classes = {"mapText"},
                            text = "Empty Map",
                            interactable = false,
                        },
                    },

                    gui.Panel{
                        classes = {"mapItem"},
                        press = MapItemPress,
                        data = {
                            type = "import",
                        },
                        gui.Label{
                            classes = {"mapText"},
                            text = "Import an Image\nor UVTT file",
                            interactable = false,
                        },
                    },
                },

                gui.Panel{
                    width = 600,
                    height = "auto",
                    flow = "vertical",
                    valign = "top",
                    halign = "center",
                    vmargin = 4,
                    gui.Panel{
                        classes = {"formRow"},
                        gui.Label{
                            classes = {"form"},
                            text = "Map Name:",
                        },
                        nameInput,
                    },
                },

                gui.Panel{
                    width = 600,
                    height = 48,
                    halign = "center",
                    valign = "bottom",
                    createButton,
                    gui.Button{
                        classes = {"sizeL"},
                        halign = "right",
                        text = "Cancel",
                        escapeActivates = true,
                        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                        click = function(element)
                            gui.CloseModal()
                        end,
                    },
                },
            }
        }
    end

    gui.ShowModal(m_dialog)

    if packsEnabled == false then
        return
    end

    if mappacks.synced then
        BuildLibraryNav()
        RefreshPackGrid()
    end

    --re-sync on every open so newly published packs appear; only changed
    --pack index blobs are downloaded.
    mappacks.Sync{
        success = function()
            BuildLibraryNav()
            RefreshPackGrid()
        end,
        error = function(msg)
            BuildLibraryNav()
            RefreshPackGrid()
            if m_dialog ~= nil and m_dialog.valid then
                packStatus.text = msg
            end
        end,
    }
end

local function isClockwise(polygon)
    local sum = 0
    local n = #polygon

    for i = 1, n do
        local j = (i % n) + 1
        sum = sum + (polygon[j].x - polygon[i].x) * (polygon[j].y + polygon[i].y)
    end

    return sum > 0
end

mod.shared.ImportMapToFloorCo = function(info)
    if info == nil or info.floor == nil or info.primaryFloor == nil then
        return
    end

    local obj = info.floor:SpawnObjectLocal(info.objid)
    if obj == nil then
        return
    end

    obj.x = 0
    obj.y = 0
    obj:Upload()

    if type(info.uvttData) ~= "table" then
        return
    end

    local function pointsEqual(a, b)
        return a ~= nil and b ~= nil
            and tonumber(a.x) == tonumber(b.x)
            and tonumber(a.y) == tonumber(b.y)
    end

    local function gridSize(data)
        local result = 100
        if type(data.grid) == "table" then
            result = tonumber(data.grid.size) or 100
        elseif data.grid ~= nil then
            result = tonumber(data.grid) or 100
        end
        if result == 0 then
            result = 100
        end
        return result
    end

    local function safeColor(value, defaultValue)
        local text = tostring(value or defaultValue or "ffffff")
        if string.sub(text, 1, 1) ~= "#" then
            text = "#" .. text
        end

        local ok, result = pcall(function() return core.Color(text) end)
        if ok then
            return result
        end

        return core.Color("#ffffff")
    end

    local function portalObjectScale(nodeId, segmentLength)
        local node = nodeId and assets:GetObjectNode(nodeId)
        local imageId = node and (node.image or node.thumbnailId or node.imageId)
        local info = imageId and gui.TryGetImageDimensions(imageId)
        local width = info and tonumber(info.width)
        local height = info and tonumber(info.height)
        local ppu = info and tonumber(info.ppu)

        if width ~= nil and height ~= nil and ppu ~= nil and ppu > 0 then
            -- Object instance scale is absolute for the image. The asset node's
            -- default scale is already consumed by normal spawning behavior and
            -- would make imported portals too small if applied again here.
            local nativeLongAxisTiles = math.max(width, height) / ppu
            if nativeLongAxisTiles > 0 then
                return segmentLength / nativeLongAxisTiles
            end
        end

        return segmentLength
    end

    local maxcount = 0
    while (obj.area == nil or (obj.area.x1 == 0 and obj.area.x2 == 0)) and maxcount < 20 do
        coroutine.yield(0.1)
        maxcount = maxcount + 1
    end

    for i = 1, 60 do
        coroutine.yield(0.01)
    end

    local area = obj.area
    if area == nil then
        return
    end

    local data = info.uvttData
    local choices = info.assetChoices or {}
    local function importAsset(choiceValue, settingId, fallback)
        local value = choiceValue
        if value == nil or value == "" then
            value = dmhub.GetSettingValue(settingId)
        end
        if value == nil or value == "" then
            value = fallback
        end
        return value
    end

    local wallAsset       = choices.wallAssetId        or dmhub.GetSettingValue("mapimport:wall_asset_id")
    local objectWallAsset = choices.objectWallAssetId  or dmhub.GetSettingValue("mapimport:object_wall_asset_id")
    local terrainWallAsset = importAsset(choices.terrainWallAssetId, "mapimport:terrain_wall_asset_id", objectWallAsset)
    local invisibleWallAsset = importAsset(choices.invisibleWallAssetId, "mapimport:invisible_wall_asset_id", objectWallAsset)
    local transparentWindowWallAsset = importAsset(choices.transparentWindowWallAssetId, "mapimport:transparent_window_wall_asset_id", objectWallAsset)
    local unrecognizedWallAsset = choices.unrecognizedWallAssetId or dmhub.GetSettingValue("mapimport:unrecognized_wall_asset_id") or wallAsset
    local doornode        = choices.doorObjectId       or dmhub.GetSettingValue("mapimport:door_object_id")
    local windownode      = choices.windowObjectId     or dmhub.GetSettingValue("mapimport:window_object_id")
    local secretDoorNode  = choices.secretDoorObjectId or dmhub.GetSettingValue("mapimport:secret_door_object_id")
    local lightnodeChoice = choices.lightObjectId      or dmhub.GetSettingValue("mapimport:light_object_id")
    local function normalizeMode(value, defaultValue, allowed)
        local mode = tostring(value or defaultValue)
        if allowed[mode] == true then
            return mode
        end
        return defaultValue
    end

    local function importMode(choiceKey, settingId, defaultValue, allowed)
        local mode = choices[choiceKey]
        if mode == nil then
            mode = dmhub.GetSettingValue(settingId)
        end
        return normalizeMode(mode, defaultValue, allowed)
    end

    local function legacyImportMode(choiceKey, legacyChoiceKey, settingId, legacySettingId, defaultValue, allowed)
        local mode = choices[choiceKey]
        if mode == nil then
            mode = choices[legacyChoiceKey]
        end
        if mode == nil then
            mode = dmhub.GetSettingValue(settingId)
        end
        if mode == nil or mode == "" then
            mode = dmhub.GetSettingValue(legacySettingId)
        end
        return normalizeMode(mode, defaultValue, allowed)
    end

    local function appendList(result, source)
        if type(source) == "table" then
            for _, item in ipairs(source) do
                result[#result+1] = item
            end
        end
    end

    local function mergedFoundryInvisibleWalls(data)
        local result = {}
        appendList(result, type(data) == "table" and data.foundry_invisible_walls or nil)
        appendList(result, type(data) == "table" and data.foundry_movement_walls or nil)
        return result
    end

    local function hasEntries(list)
        return type(list) == "table" and #list > 0
    end

    local function optionalList(list)
        if hasEntries(list) then
            return list
        end
        return nil
    end

    local wallModeAllowed = {wall = true, none = true}
    local assetModeAllowed = {asset = true, none = true}
    local windowModeAllowed = {asset = true, movement_wall = true, none = true}
    local structuralWallMode = importMode("structuralWallMode", "mapimport:structural_wall_mode", "wall", wallModeAllowed)
    local objectWallMode = importMode("objectWallMode", "mapimport:object_wall_mode", "wall", wallModeAllowed)
    local terrainWallMode = importMode("terrainWallMode", "mapimport:terrain_wall_mode", "wall", wallModeAllowed)
    local invisibleWallMode = legacyImportMode("invisibleWallMode", "movementWallMode", "mapimport:invisible_wall_mode", "mapimport:movement_wall_mode", "wall", wallModeAllowed)
    local unrecognizedWallMode = importMode("unrecognizedWallMode", "mapimport:unrecognized_wall_mode", "none", wallModeAllowed)
    local doorMode = importMode("doorMode", "mapimport:door_mode", "asset", assetModeAllowed)
    local windowMode = importMode("windowMode", "mapimport:window_mode", "asset", windowModeAllowed)
    local secretDoorMode = importMode("secretDoorMode", "mapimport:secret_door_mode", "asset", assetModeAllowed)
    local lightMode = importMode("lightMode", "mapimport:light_mode", "asset", assetModeAllowed)
    if choices.unrecognizedWallMode == nil and choices.includeUnrecognizedWalls ~= nil then
        unrecognizedWallMode = cond(choices.includeUnrecognizedWalls == true, "wall", "none")
    end
    local flipFoundryTerrainWalls = choices.flipFoundryTerrainWalls == true
    if choices.flipFoundryTerrainWalls == nil then
        flipFoundryTerrainWalls = dmhub.GetSettingValue("mapimport:flip_foundry_terrain_walls") == true
    end
    local nudgeX = tonumber(choices.alignmentOffsetX) or 0
    local nudgeY = tonumber(choices.alignmentOffsetY) or 0
    if nudgeX ~= 0 or nudgeY ~= 0 then
        area = {
            x1 = area.x1 + nudgeX,
            x2 = area.x2 + nudgeX,
            y1 = area.y1 - nudgeY,
            y2 = area.y2 - nudgeY,
        }
    end

    local function executeWalls(points, wallid, closed)
        if #points == 0 or wallid == nil or wallid == "" then
            return
        end

        info.primaryFloor:ExecutePolygonOperation{
            points = points,
            tileid = nil,
            wallid = wallid,
            erase = false,
            closed = closed,
        }
    end

    local function appendWorldPoint(points, p)
        if type(p) ~= "table" then
            return false
        end

        local x = tonumber(p.x)
        local y = tonumber(p.y)
        if x == nil or y == nil then
            return false
        end

        points[#points+1] = area.x1 + x
        points[#points+1] = area.y2 - y
        return true
    end

    local function copySegments(lineSet)
        local segments = {}
        if type(lineSet) ~= "table" then
            return segments
        end

        for _, segment in ipairs(lineSet) do
            if type(segment) == "table" and #segment >= 2 then
                local copy = {}
                for _, p in ipairs(segment) do
                    if type(p) == "table" and tonumber(p.x) ~= nil and tonumber(p.y) ~= nil then
                        copy[#copy+1] = {x = tonumber(p.x), y = tonumber(p.y)}
                    end
                end
                if #copy >= 2 then
                    segments[#segments+1] = copy
                end
            end
        end

        return segments
    end

    local function processLineSet(lineSet, wallid, objectWalls)
        local segments = copySegments(lineSet)
        local segmentsDeleted = {}
        local changes = true
        local ncount = 0

        while (not objectWalls) and changes and ncount < 50 do
            changes = false
            ncount = ncount + 1

            for i, segment in ipairs(segments) do
                if segmentsDeleted[i] == nil then
                    for j, nextSegment in ipairs(segments) do
                        if i ~= j and segmentsDeleted[j] == nil and pointsEqual(segment[#segment], nextSegment[1]) then
                            for _, point in ipairs(nextSegment) do
                                segment[#segment+1] = point
                            end

                            segmentsDeleted[j] = true
                            changes = true
                        end
                    end
                end
            end
        end

        local pointsList = {}
        local objectPointsList = {}
        for i, seg in ipairs(segments) do
            if segmentsDeleted[i] == nil then
                local poly = seg
                if objectWalls and pointsEqual(seg[1], seg[#seg]) and not isClockwise(seg) then
                    poly = {}
                    for j = #seg, 1, -1 do
                        poly[#poly+1] = seg[j]
                    end
                end

                local isObject = objectWalls and pointsEqual(poly[1], poly[#poly])
                local points = {}
                for j, p in ipairs(poly) do
                    if (not isObject) or j ~= #poly then
                        appendWorldPoint(points, p)
                    end
                end

                if #points >= 4 then
                    if isObject then
                        objectPointsList[#objectPointsList+1] = points
                    else
                        pointsList[#pointsList+1] = points
                    end
                end
            end
        end

        executeWalls(pointsList, wallid, false)
        executeWalls(objectPointsList, wallid, true)
    end

    local function lineSetHasSegments(lineSet)
        if type(lineSet) ~= "table" then
            return false
        end

        for _, segment in ipairs(lineSet) do
            if type(segment) == "table" and #segment >= 2 then
                return true
            end
        end

        return false
    end

    local function splitOpenClosedLineSet(lineSet)
        local openLines = {}
        local closedLines = {}
        if type(lineSet) ~= "table" then
            return openLines, closedLines
        end

        for _, segment in ipairs(lineSet) do
            if type(segment) == "table" and #segment >= 2 then
                if pointsEqual(segment[1], segment[#segment]) then
                    closedLines[#closedLines+1] = segment
                else
                    openLines[#openLines+1] = segment
                end
            end
        end

        return openLines, closedLines
    end

    local function buildPolylines(walls)
        local out = {}
        if type(walls) ~= "table" then
            return out
        end

        for _, wall in ipairs(walls) do
            if type(wall) == "table" and type(wall.points) == "table" and #wall.points >= 2 then
                local pts = {}
                for _, p in ipairs(wall.points) do
                    appendWorldPoint(pts, p)
                end
                if #pts >= 4 then
                    out[#out+1] = pts
                end
            end
        end

        return out
    end

    local function reverseLine(line)
        local result = {}
        for i = #line, 1, -1 do
            result[#result+1] = line[i]
        end
        return result
    end

    local function buildWallLineSet(walls)
        local out = {}
        if type(walls) ~= "table" then
            return out
        end

        for _, wall in ipairs(walls) do
            local sourcePoints = type(wall) == "table" and wall.points or nil
            if type(sourcePoints) == "table" and #sourcePoints >= 2 then
                local pts = {}
                for _, p in ipairs(sourcePoints) do
                    if type(p) == "table" and tonumber(p.x) ~= nil and tonumber(p.y) ~= nil then
                        pts[#pts+1] = {x = tonumber(p.x), y = tonumber(p.y)}
                    end
                end
                if #pts >= 2 then
                    out[#out+1] = pts
                end
            end
        end

        return out
    end

    local function foundrySenseName(value)
        value = tonumber(value)
        if value == 0 then return "None" end
        if value == 10 then return "Limited" end
        if value == 20 then return "Normal" end
        if value == 30 then return "Proximity" end
        if value == 40 then return "Distance" end
        return tostring(value)
    end

    local function foundryDoorName(value)
        value = tonumber(value)
        if value == 0 then return "Wall" end
        if value == 1 then return "Door" end
        if value == 2 then return "SecretDoor" end
        return tostring(value)
    end

    local function foundryDirectionName(value)
        value = tonumber(value)
        if value == 0 then return "Both" end
        if value == 1 then return "Left" end
        if value == 2 then return "Right" end
        return tostring(value)
    end

    local function foundryDoorStateName(value)
        value = tonumber(value)
        if value == 0 then return "Closed" end
        if value == 1 then return "Open" end
        if value == 2 then return "Locked" end
        return tostring(value)
    end

    local function foundryWallFlags(wall)
        local door = tonumber(wall.door) or 0
        local sight = tonumber(wall.sight) or 20
        local move = tonumber(wall.move) or 20
        local light = tonumber(wall.light) or 20
        local sound = tonumber(wall.sound) or 20
        local dir = tonumber(wall.dir) or 0
        local ds = tonumber(wall.ds) or 0
        local threshold = type(wall.threshold) == "table" and wall.threshold or nil

        local sense = {
            door = door,
            door_name = foundryDoorName(door),
            sight = sight,
            sight_name = foundrySenseName(sight),
            move = move,
            move_name = foundrySenseName(move),
            light = light,
            light_name = foundrySenseName(light),
            sound = sound,
            sound_name = foundrySenseName(sound),
        }
        if threshold ~= nil then
            sense.threshold = threshold
        end

        return {
            foundry_direction = dir,
            foundry_direction_name = foundryDirectionName(dir),
            foundry_door_state = ds,
            foundry_door_state_name = foundryDoorStateName(ds),
            foundry_sense = sense,
        }
    end

    local function foundryWallEntry(p1, p2, wall)
        local threshold = type(wall.threshold) == "table" and wall.threshold or nil
        local entry = {
            points = {p1, p2},
            sense = {
                door = foundryDoorName(tonumber(wall.door) or 0),
                sight = foundrySenseName(tonumber(wall.sight) or 20),
                move = foundrySenseName(tonumber(wall.move) or 20),
                light = foundrySenseName(tonumber(wall.light) or 20),
                sound = foundrySenseName(tonumber(wall.sound) or 20),
            },
            flags = foundryWallFlags(wall),
        }
        if threshold ~= nil then
            entry.threshold = threshold
        end
        return entry
    end

    local function foundryPortal(p1, p2, wall, closed, secret)
        local flags = foundryWallFlags(wall)
        local portal = {
            bounds = {p1, p2},
            closed = closed,
            flags = flags,
            foundryDoorState = flags.foundry_door_state,
            foundryDoorStateName = flags.foundry_door_state_name,
            foundryDirection = flags.foundry_direction,
            foundryDirectionName = flags.foundry_direction_name,
        }
        if secret == true then
            portal.secret = true
        end
        return portal
    end

    local function processFoundryTerrainWalls(walls, wallid, flipOpen)
        local segments = buildWallLineSet(walls)
        local segmentsDeleted = {}
        local changes = true
        local ncount = 0

        while changes and ncount < 50 do
            changes = false
            ncount = ncount + 1

            for i, segment in ipairs(segments) do
                if segmentsDeleted[i] == nil then
                    for j, nextSegment in ipairs(segments) do
                        if i ~= j and segmentsDeleted[j] == nil and pointsEqual(segment[#segment], nextSegment[1]) then
                            for _, point in ipairs(nextSegment) do
                                segment[#segment+1] = point
                            end

                            segmentsDeleted[j] = true
                            changes = true
                        end
                    end
                end
            end
        end

        local pointsList = {}
        local closedPointsList = {}
        for i, seg in ipairs(segments) do
            if segmentsDeleted[i] == nil then
                local poly = seg
                local closed = pointsEqual(poly[1], poly[#poly])
                if closed and not isClockwise(poly) then
                    poly = reverseLine(poly)
                elseif (not closed) and flipOpen then
                    poly = reverseLine(poly)
                end

                local points = {}
                for j, p in ipairs(poly) do
                    if (not closed) or j ~= #poly then
                        appendWorldPoint(points, p)
                    end
                end

                if #points >= 4 then
                    if closed then
                        closedPointsList[#closedPointsList+1] = points
                    else
                        pointsList[#pointsList+1] = points
                    end
                end
            end
        end

        executeWalls(pointsList, wallid, false)
        executeWalls(closedPointsList, wallid, true)
    end

    local function readPortalSegment(portal)
        local bounds = type(portal) == "table" and portal.bounds or nil
        if type(bounds) ~= "table" or #bounds ~= 2 then
            return nil
        end

        local b1 = type(bounds[1]) == "table" and bounds[1] or nil
        local b2 = type(bounds[2]) == "table" and bounds[2] or nil
        local x1 = b1 and tonumber(b1.x) or nil
        local y1 = b1 and tonumber(b1.y) or nil
        local x2 = b2 and tonumber(b2.x) or nil
        local y2 = b2 and tonumber(b2.y) or nil

        if x1 == nil or y1 == nil or x2 == nil or y2 == nil then
            return nil
        end

        local dx = x2 - x1
        local dy = y2 - y1
        return {
            portal = portal,
            x1 = x1,
            y1 = y1,
            x2 = x2,
            y2 = y2,
            closed = portal.closed == true,
            secret = portal.secret == true,
            length = math.sqrt(dx*dx + dy*dy),
        }
    end

    local function endpointsEqual(ax, ay, bx, by)
        return math.abs(ax - bx) <= 0.0001 and math.abs(ay - by) <= 0.0001
    end

    local function portalSegmentsTouch(a, b)
        return endpointsEqual(a.x1, a.y1, b.x1, b.y1)
            or endpointsEqual(a.x1, a.y1, b.x2, b.y2)
            or endpointsEqual(a.x2, a.y2, b.x1, b.y1)
            or endpointsEqual(a.x2, a.y2, b.x2, b.y2)
    end

    local function collapsedPortalFromGroup(group)
        local minX = group[1].x1
        local maxX = group[1].x1
        local minY = group[1].y1
        local maxY = group[1].y1
        local best = group[1]
        local closed = false
        local secret = false

        for _, segment in ipairs(group) do
            minX = math.min(minX, segment.x1, segment.x2)
            maxX = math.max(maxX, segment.x1, segment.x2)
            minY = math.min(minY, segment.y1, segment.y2)
            maxY = math.max(maxY, segment.y1, segment.y2)
            closed = closed or segment.closed
            secret = secret or segment.secret
            if segment.length > best.length then
                best = segment
            end
        end

        local centerX = (minX + maxX) / 2
        local centerY = (minY + maxY) / 2
        local width = maxX - minX
        local height = maxY - minY
        local p1, p2

        if width >= height then
            if best.x1 <= best.x2 then
                p1 = {x = minX, y = centerY}
                p2 = {x = maxX, y = centerY}
            else
                p1 = {x = maxX, y = centerY}
                p2 = {x = minX, y = centerY}
            end
        else
            if best.y1 <= best.y2 then
                p1 = {x = centerX, y = minY}
                p2 = {x = centerX, y = maxY}
            else
                p1 = {x = centerX, y = maxY}
                p2 = {x = centerX, y = minY}
            end
        end

        return {
            bounds = {p1, p2},
            closed = closed,
            secret = secret,
        }
    end

    local function collapseConnectedPortals(portalList)
        local segments = {}
        if type(portalList) ~= "table" then
            return segments
        end

        for _, portal in ipairs(portalList) do
            local segment = readPortalSegment(portal)
            if segment ~= nil then
                segments[#segments+1] = segment
            end
        end

        local result = {}
        local used = {}
        for i, segment in ipairs(segments) do
            if used[i] == nil then
                local group = {segment}
                used[i] = true

                local changed = true
                while changed do
                    changed = false
                    for j, candidate in ipairs(segments) do
                        if used[j] == nil and candidate.closed == segment.closed and candidate.secret == segment.secret then
                            for _, member in ipairs(group) do
                                if portalSegmentsTouch(member, candidate) then
                                    group[#group+1] = candidate
                                    used[j] = true
                                    changed = true
                                    break
                                end
                            end
                        end
                    end
                end

                if #group >= 3 then
                    result[#result+1] = collapsedPortalFromGroup(group)
                else
                    for _, candidate in ipairs(group) do
                        result[#result+1] = candidate.portal
                    end
                end
            end
        end

        return result
    end

    local structuralLines = data.line_of_sight
    local objectLines = data.objects_line_of_sight
    local portals = type(data.portals) == "table" and data.portals or nil
    local foundryTerrainWalls = type(data.foundry_terrain_walls) == "table" and data.foundry_terrain_walls or nil
    local foundryInvisibleWalls = optionalList(mergedFoundryInvisibleWalls(data))
    local foundryUnrecognizedWalls = type(data.foundry_unrecognized_walls) == "table" and data.foundry_unrecognized_walls or nil
    local convertedFromFoundry = false
    local objectOnlyLineOfSight = false

    if type(structuralLines) ~= "table" and type(data.walls) == "table" then
        convertedFromFoundry = true
        structuralLines = {}
        portals = {}
        foundryTerrainWalls = {}
        foundryInvisibleWalls = {}
        foundryUnrecognizedWalls = {}

        local foundryGrid = gridSize(data)
        for _, wall in ipairs(data.walls) do
            local points = type(wall) == "table" and wall.c or nil
            if type(points) == "table" and #points == 4 then
                local x1 = tonumber(points[1])
                local y1 = tonumber(points[2])
                local x2 = tonumber(points[3])
                local y2 = tonumber(points[4])
                if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil then
                    local p1 = {x = x1 / foundryGrid, y = y1 / foundryGrid}
                    local p2 = {x = x2 / foundryGrid, y = y2 / foundryGrid}
                    local door = tonumber(wall.door) or 0
                    local move = tonumber(wall.move) or 20
                    local sight = tonumber(wall.sight) or 20
                    local light = tonumber(wall.light) or 20
                    local dir = tonumber(wall.dir) or 0
                    local threshold = type(wall.threshold) == "table" and wall.threshold or nil
                    local windowLike = threshold ~= nil
                        and threshold.light ~= nil and threshold.sight ~= nil
                        and light ~= move and sight ~= move

                    if (door == 0 or door == 2) and windowLike then
                        portals[#portals+1] = foundryPortal(p1, p2, wall, false, false)
                    elseif door == 1 then
                        portals[#portals+1] = foundryPortal(p1, p2, wall, true, false)
                    elseif door == 2 then
                        portals[#portals+1] = foundryPortal(p1, p2, wall, true, true)
                    elseif door ~= 0 or dir ~= 0 then
                        foundryUnrecognizedWalls[#foundryUnrecognizedWalls+1] = foundryWallEntry(p1, p2, wall)
                    elseif door == 0 and sight == 20 and move == 20 then
                        structuralLines[#structuralLines+1] = {p1, p2}
                    elseif door == 0 and sight == 10 and move == 20 then
                        foundryTerrainWalls[#foundryTerrainWalls+1] = foundryWallEntry(p1, p2, wall)
                    elseif door == 0 and sight == 0 and move == 20 then
                        foundryInvisibleWalls[#foundryInvisibleWalls+1] = foundryWallEntry(p1, p2, wall)
                    else
                        foundryUnrecognizedWalls[#foundryUnrecognizedWalls+1] = foundryWallEntry(p1, p2, wall)
                    end
                end
            end
        end
    end

    if (not convertedFromFoundry)
            and (not lineSetHasSegments(structuralLines))
            and lineSetHasSegments(objectLines) then
        objectOnlyLineOfSight = true
        structuralLines, objectLines = splitOpenClosedLineSet(objectLines)
    end

    if structuralWallMode == "wall" then
        processLineSet(structuralLines, wallAsset, false)
    end
    if objectWallMode == "wall" then
        processLineSet(objectLines, objectWallAsset, true)
    end
    if terrainWallMode == "wall" then
        processFoundryTerrainWalls(foundryTerrainWalls, terrainWallAsset, flipFoundryTerrainWalls)
    end
    if invisibleWallMode == "wall" then
        processFoundryTerrainWalls(foundryInvisibleWalls, invisibleWallAsset, flipFoundryTerrainWalls)
    end
    if unrecognizedWallMode == "wall" then
        executeWalls(buildPolylines(foundryUnrecognizedWalls), unrecognizedWallAsset, false)
    end

    if portals ~= nil then
        local portalsToSpawn = portals
        if objectOnlyLineOfSight then
            portalsToSpawn = collapseConnectedPortals(portals)
        end
        for _, portal in ipairs(portalsToSpawn) do
            local bounds = type(portal) == "table" and portal.bounds or nil
            if type(bounds) == "table" and #bounds == 2 then
                local b1 = type(bounds[1]) == "table" and bounds[1] or nil
                local b2 = type(bounds[2]) == "table" and bounds[2] or nil
                local x1 = b1 and tonumber(b1.x) or nil
                local y1 = b1 and tonumber(b1.y) or nil
                local x2 = b2 and tonumber(b2.x) or nil
                local y2 = b2 and tonumber(b2.y) or nil

                if x1 ~= nil and y1 ~= nil and x2 ~= nil and y2 ~= nil then
                    local points = {area.x1 + x1, area.y2 - y1, area.x1 + x2, area.y2 - y2}
                    local portalKind = "window"
                    if portal.closed then
                        portalKind = cond(portal.secret == true, "secret", "door")
                    end
                    local portalMode = windowMode
                    if portalKind == "door" then
                        portalMode = doorMode
                    elseif portalKind == "secret" then
                        portalMode = secretDoorMode
                    end

                    if portalMode == "asset" and not convertedFromFoundry and not objectOnlyLineOfSight then
                        executeWalls({points}, wallAsset, false)
                    elseif portalKind == "window" and portalMode == "movement_wall" then
                        executeWalls({points}, transparentWindowWallAsset, false)
                    end

                    local nodeId = windownode
                    if portal.closed then
                        nodeId = cond(portal.secret == true, secretDoorNode, doornode)
                    end

                    if portalMode == "asset" and nodeId ~= nil and nodeId ~= "" then
                        local portalObj = info.primaryFloor:SpawnObjectLocal(nodeId)
                        if portalObj ~= nil then
                            local flags = type(portal.flags) == "table" and portal.flags or nil
                            local foundryDoorState = portal.foundryDoorState or (flags and flags.foundry_door_state)
                            -- TODO: Apply Foundry open/locked door state when DMHub exposes a door-state API.
                            local delta = core.Vector2(x2 - x1, y1 - y2)
                            -- A portal object's position is its hinge, not its center,
                            -- so anchor it at the first endpoint of the portal segment.
                            portalObj.x = area.x1 + x1
                            portalObj.y = area.y2 - y1
                            portalObj.rotation = delta.angle + (tonumber(dmhub.GetSettingValue("mapimport:portal_rotation_offset")) or 90)
                            portalObj.scale = portalObjectScale(nodeId, delta.length)
                            portalObj:Upload()
                        end
                    end
                end
            end
        end
    end

@if MCDM
    local lightnode = lightnodeChoice or "2339211c-c35a-4e0a-a5fa-79d2e446bd3b"
@else
    local lightnode = lightnodeChoice or "-MGBXtOnKAXNhhLK89_9"
@end
    if lightMode == "asset" and type(data.lights) == "table" and ObjectNodeHasComponent(lightnode, "Light") then
        local foundryGrid = gridSize(data)
        for _, light in ipairs(data.lights) do
            if type(light) == "table" then
                local x, y, radius, intensity, color, shadows
                if type(light.position) == "table" then
                    x = tonumber(light.position.x)
                    y = tonumber(light.position.y)
                    radius = tonumber(light.range) or 0
                    intensity = ((tonumber(light.intensity) or 1) * 0.5) ^ 0.5
                    color = safeColor(light.color, "ffffff")
                    shadows = light.shadows
                    if shadows == nil then
                        shadows = true
                    end
                else
                    x = tonumber(light.x) and (tonumber(light.x) / foundryGrid) or nil
                    y = tonumber(light.y) and (tonumber(light.y) / foundryGrid) or nil
                    radius = tonumber(light.dim) or tonumber(light.bright) or 0
                    intensity = (tonumber(light.tintAlpha) or 0.1) * 3
                    color = safeColor(light.tintColor, "#ffffff")
                    shadows = true
                end

                if x ~= nil and y ~= nil then
                    local lightObj = info.primaryFloor:SpawnObjectLocal(lightnode)
                    local component = lightObj and lightObj:GetComponent("Light")
                    if component ~= nil then
                        lightObj.x = area.x1 + x
                        lightObj.y = area.y2 - y
                        component:SetProperty("radius", radius)
                        component:SetProperty("intensity", intensity)
                        component:SetProperty("castsShadows", shadows)
                        component:SetProperty("color", color)
                        lightObj:Upload()
                    end
                end
            end
        end
    end

    if type(data.environment) == "table" then
        if data.environment.ambient_light ~= nil then
            dmhub.SetSettingValue("undergroundillumination", safeColor(data.environment.ambient_light, "ffffff").value)
        else
            dmhub.SetSettingValue("undergroundillumination", 1.0)
        end
    end
end

mod.shared.FinishMapImport = function(mapName, info)
    local floors = {}

    for i,objid in ipairs(info.objids) do
        floors[#floors+1] = {
            description = cond(#info.objids == 1, "Main Floor", string.format("Floor %d", i)),
            layerDescription = "Map Layer",
            parentFloor = #floors+1,
        }

        floors[#floors+1] = {
            description = cond(#info.objids == 1, "Main Floor", string.format("Floor %d", i)),
        }
    end


    local guid = game.CreateMap{
        description = mapName,
        groundLevel = #floors,
        floors = floors,
    }
    dmhub.Coroutine(function()
        while game.GetMap(guid) == nil do
            coroutine.yield(0.05)
        end

        -- Round to nearest tile: if the image overhangs an integer tile
        -- by less than half a tile (a few pixels) we round down, not up.
        -- math.ceil would always round up even for tiny overhangs.
        local w = math.floor(info.width + 0.5)
        local h = math.floor(info.height + 0.5)

        -- Final safety net: the import dialog clamps user input, but if any
        -- code path slips a huge value through, refuse to write it. See
        -- MAX_MAP_TILES_PER_AXIS in MapImport.lua for the full rationale.
        local MAX_DIM = 2000
        if w > MAX_DIM or h > MAX_DIM then
            w = math.min(w, MAX_DIM)
            h = math.min(h, MAX_DIM)
        end

        local map = game.GetMap(guid)
        map.description = mapName
        -- Bounds box: dimMin..dimMax (inclusive) covers exactly w cells in
        -- x and h cells in y. For odd w/h the box is centered on origin.
        -- For even w/h the box is biased RIGHT (center at +0.5) to match
        -- the renderer's pivot wrap, which lands _mapPivot at 0.5-tileDim/2
        -- for even-tile-count perfect fits and therefore shifts the image
        -- right by half a tile. A left-biased box would appear "one tile
        -- to the left of where it should be" relative to the image.
        map.dimensions = {
            x1 = -math.ceil(w/2) + 1,
            y1 = -math.ceil(h/2) + 1,
            x2 = math.floor(w/2),
            y2 = math.floor(h/2),
        }
        map:Upload()

        map:Travel()

        while game.currentMapId ~= guid do
            coroutine.yield(0.05)
        end

        --try to wait a bit to make sure we are synced on the new map.
        for i=1,120 do
            coroutine.yield(0.01)
        end

        local settings = info.mapSettings
        if settings ~= nil then
            for k,v in pairs(settings) do
                dmhub.SetSettingValue(k, v)
            end
        end

        local floors = game.currentMap.floorsWithoutLayers

        for i,floor in ipairs(floors) do
            local uvttData = nil
            if info.uvttData ~= nil then
                uvttData = info.uvttData[i]
            end

            --send to the map layer instead of the primary floor.
            local targetFloor = floor
            for i,layer in ipairs(game.currentMap.floors) do
                if layer.parentFloor == floor.floorid then
                    targetFloor = layer
                    break
                end
            end

            mod.shared.ImportMapToFloorCo{
                objid = info.objids[i],
                floor = targetFloor,
                primaryFloor = floor,
                uvttData = uvttData,
                assetChoices = info.assetChoices,
            }
        end

    end)
end

-- Open the alignment dialog in "realign" mode for an already-imported floor.
-- The dialog reuses the same drag/zoom/pan UI as the new-floor flow but, instead
-- of creating a new floor on confirm, it just updates the existing object's
-- (x, y) position so the user can re-align it against the other map images.
mod.shared.ShowFloorRealignDialog = function(mapLayer, mapObj)
    if mapObj == nil then
        return
    end
    mod.shared.ShowFloorAlignmentDialog{
        realignTarget = mapObj,
    }
end

-- Show a dialog to let the user align a new floor image to the existing map.
-- info: the import result with objids, width, height, paths, imageWidth, imageHeight.
-- For realign mode, info.realignTarget is a LuaObjectInstance (with a Map component)
-- and the rest of info may be empty.
mod.shared.ShowFloorAlignmentDialog = function(info)
    -- Mode A (default): aligning a freshly-imported new floor. info has objids/width/height.
    -- Mode B (realign): info.realignTarget is the existing LuaObjectInstance to reposition.
    --   In this mode info.objids may be empty; we reuse the same UI to drag the existing
    --   floor's image around and on confirm we set obj.x/obj.y instead of creating a new floor.
    local realignTarget = info.realignTarget

    if realignTarget == nil and (info.objids == nil or #info.objids == 0) then
        return
    end

    local currentMap = game.currentMap
    if currentMap == nil then
        return
    end

    local dim = currentMap.dimensions
    local mapW = dim.x2 - dim.x1
    local mapH = dim.y2 - dim.y1

    -- floorW, floorH are the moving image's tile span. In realign mode, derive from
    -- the existing object's actual rendered span (fractional). In normal mode, use the
    -- import's reported tile count, ceil'd.
    local floorW
    local floorH
    -- references[]: list of {imageid, x1, y1, x2, y2} drawn as static backdrop in the
    -- preview panel. Normal mode renders the canvas image at canvas bounds (legacy
    -- behaviour, exactly one entry). Realign mode renders every OTHER Map object at
    -- its actual world bounds.
    local references = {}

    -- Default offset: the moving floor's top-left in world tile coords.
    local offsetX
    local offsetY

    -- Captured at setup time and used by the Confirm handler to convert offset
    -- (top-left of rendered image) back to obj.x/obj.y. The renderer's _mapPivot
    -- is rarely exactly (0.5, 0.5) -- it's wrapped to near-center but can be
    -- offset by up to one tile, so we must respect it instead of assuming centered.
    local realignPivotX = 0.5
    local realignPivotY = 0.5

    if realignTarget ~= nil then
        local d = realignTarget.mapAlignmentDiagnostic
        if d == nil then
            gui.ModalMessage{title = "Error", message = "Could not read this floor's calibration."}
            return
        end
        floorW = d.imageWorldWidth
        floorH = d.imageWorldHeight
        if (floorW or 0) <= 0 or (floorH or 0) <= 0 then
            -- Fallback to the area-derived span if the renderer hasn't computed _tileDim yet.
            floorW = (d.areaX2 or 0) - (d.areaX1 or 0)
            floorH = (d.areaY2 or 0) - (d.areaY1 or 0)
        end
        if (floorW or 0) <= 0 or (floorH or 0) <= 0 then
            gui.ModalMessage{title = "Error", message = "Could not determine this floor's size."}
            return
        end

        realignPivotX = d.mapPivotX or 0.5
        realignPivotY = d.mapPivotY or 0.5

        -- Use the actual rendered top-left (areaX1/areaY1). Falling back to
        -- pos - imageWorldDim * mapPivot if for some reason the area fields are
        -- missing -- this is the same formula the renderer uses internally.
        if d.areaX1 ~= nil and d.areaY1 ~= nil then
            offsetX = d.areaX1
            offsetY = d.areaY1
        else
            offsetX = (realignTarget.x or 0) - floorW * realignPivotX
            offsetY = (realignTarget.y or 0) - floorH * realignPivotY
        end

        -- Collect every OTHER Map object as a reference backdrop.
        for _, floor in ipairs(currentMap.floors) do
            for _, obj in pairs(floor.objects) do
                if obj:GetComponent("Map") ~= nil and obj.id ~= realignTarget.id then
                    local od = obj.mapAlignmentDiagnostic
                    if od ~= nil and od.areaX1 ~= nil then
                        references[#references+1] = {
                            imageid = obj.imageid,
                            x1 = od.areaX1, y1 = od.areaY1,
                            x2 = od.areaX2, y2 = od.areaY2,
                        }
                    end
                end
            end
        end

        printf("FLOOR_REALIGN:: target=%s/%s floorW=%.4f floorH=%.4f initialOffset=(%.4f,%.4f) refs=%d",
            d.floorid, d.objid, floorW, floorH, offsetX, offsetY, #references)
    else
        -- Round to nearest tile (see CreateMap comment above).
        floorW = math.floor(info.width + 0.5)
        floorH = math.floor(info.height + 0.5)
        offsetX = dim.x1
        offsetY = dim.y1
    end

    -- Check if the new floor is the same size as the existing map.
    printf("FLOOR_ALIGN:: ShowFloorAlignmentDialog called: mapW=%s mapH=%s floorW=%s floorH=%s",
        tostring(mapW), tostring(mapH), tostring(floorW), tostring(floorH))
    printf("FLOOR_ALIGN:: Existing map dims: x1=%s y1=%s x2=%s y2=%s", json(dim.x1), json(dim.y1), json(dim.x2), json(dim.y2))
    printf("FLOOR_ALIGN:: Default offset: (%s, %s)", tostring(offsetX), tostring(offsetY))
    printf("FLOOR_ALIGN:: Incoming info: width=%s height=%s objids=%s imageWidth=%s imageHeight=%s",
        tostring(info.width), tostring(info.height), json(info.objids or {}), tostring(info.imageWidth), tostring(info.imageHeight))

    -- Snapshot every existing Map LevelObject's calibration so we can compare against the new one.
    do
        local count = 0
        for _, floor in ipairs(currentMap.floors) do
            for _, obj in pairs(floor.objects) do
                if obj:GetComponent("Map") ~= nil then
                    count = count + 1
                    local d = obj.mapAlignmentDiagnostic
                    if d ~= nil then
                        printf("FLOOR_ALIGN_DIAG:: Existing Map object [%d] floorid=%s objid=%s calibration=%s",
                            count, floor.floorid, obj.id, json(d))
                    else
                        printf("FLOOR_ALIGN_DIAG:: Existing Map object [%d] floorid=%s objid=%s had nil mapAlignmentDiagnostic",
                            count, floor.floorid, obj.id)
                    end
                end
            end
        end
        if count == 0 then
            printf("FLOOR_ALIGN_DIAG:: ShowFloorAlignmentDialog: no existing Map LevelObjects found.")
        end
    end

    if realignTarget == nil then
        -- If the user picked "Match Existing Map", we have a calibration captured
        -- from the existing Map LevelObject. Bypass the alignment dialog and place
        -- the new floor at the same world position as the existing one. Once
        -- FinishFloorImport applies the calibration, the new image will render
        -- with the same _tileDim/_mapPivot, so its world bounds match exactly.
        if info.matchCalibration ~= nil then
            printf("FLOOR_ALIGN:: matchCalibration present -- skipping alignment dialog and aligning to existing.")
            mod.shared.FinishFloorImport(info, offsetX, offsetY)
            return
        end

        local sameSize = (floorW == mapW and floorH == mapH)

        if sameSize then
            printf("FLOOR_ALIGN:: Same size detected, skipping alignment dialog")
            mod.shared.FinishFloorImport(info, offsetX, offsetY)
            return
        end
    end

    -- Find the existing map's floor image for display (legacy single-image backdrop in
    -- normal mode). In realign mode the references[] list above is what we render.
    local existingImageId = nil
    if realignTarget == nil then
        local floors = currentMap.floorsWithoutLayers
        if #floors > 0 then
            for _, floor in ipairs(currentMap.floors) do
                for _, obj in pairs(floor.objects) do
                    if obj:GetComponent("Map") ~= nil then
                        existingImageId = obj.imageid
                        break
                    end
                end
                if existingImageId ~= nil then break end
            end
        end
    end

    -- The moving image. Normal mode: the first imported asset. Realign mode: the
    -- existing object's image.
    local newImageId
    if realignTarget ~= nil then
        newImageId = realignTarget.imageid
    else
        newImageId = info.objids[1]
    end

    local newFloorOpacity = 0.6

    -- Build the alignment UI.
    local previewLabel
    local previewPanel

    local function fireUpdatePreview()
        if previewLabel == nil or previewPanel == nil then
            return
        end
        previewLabel:FireEvent("updatePreview")
        previewPanel:FireEvent("updatePreview")
    end

    -- Format an offset for display: integer if whole, two decimals otherwise.
    local function fmtOffset(v)
        if v == math.floor(v) then
            return tostring(math.floor(v))
        end
        return string.format("%.2f", v)
    end

    -- Realign mode allows fractional offsets (the existing object may be at a
    -- fractional world position because its image span isn't an integer number
    -- of tiles). Normal mode keeps the legacy integer-only behaviour.
    local allowFractional = realignTarget ~= nil

    local offsetXInput = gui.Input{
        fontSize = 18,
        width = 80,
        height = 24,
        text = fmtOffset(offsetX),
        edit = function(element)
            local val = tonumber(element.text)
            if val ~= nil and (allowFractional or val == math.floor(val)) then
                offsetX = val
                fireUpdatePreview()
            end
        end,
        change = function(element)
            local val = tonumber(element.text)
            if val ~= nil and (allowFractional or val == math.floor(val)) then
                offsetX = val
            else
                element.text = fmtOffset(offsetX)
            end
            fireUpdatePreview()
        end,
    }

    local offsetYInput = gui.Input{
        fontSize = 18,
        width = 80,
        height = 24,
        text = fmtOffset(offsetY),
        edit = function(element)
            local val = tonumber(element.text)
            if val ~= nil and (allowFractional or val == math.floor(val)) then
                offsetY = val
                fireUpdatePreview()
            end
        end,
        change = function(element)
            local val = tonumber(element.text)
            if val ~= nil and (allowFractional or val == math.floor(val)) then
                offsetY = val
            else
                element.text = fmtOffset(offsetY)
            end
            fireUpdatePreview()
        end,
    }

    previewLabel = gui.Label{
        classes = {"form"},
        width = "100%",
        height = "auto",
        color = "#cccccc",
        wrap = true,
        halign = "left",
        text = "",

        updatePreview = function(element)
            local newX2 = offsetX + floorW
            local newY2 = offsetY + floorH

            local lines = {}
            if realignTarget ~= nil then
                local centerX = offsetX + floorW / 2
                local centerY = offsetY + floorH / 2
                lines[#lines+1] = string.format(
                    "This floor: (%s, %s) to (%s, %s); center (%s, %s).",
                    fmtOffset(offsetX), fmtOffset(offsetY),
                    fmtOffset(newX2), fmtOffset(newY2),
                    fmtOffset(centerX), fmtOffset(centerY))
                for i, ref in ipairs(references) do
                    local cx = (ref.x1 + ref.x2) / 2
                    local cy = (ref.y1 + ref.y2) / 2
                    lines[#lines+1] = string.format(
                        "Other [%d]: (%s, %s) to (%s, %s); center (%s, %s).",
                        i,
                        fmtOffset(ref.x1), fmtOffset(ref.y1),
                        fmtOffset(ref.x2), fmtOffset(ref.y2),
                        fmtOffset(cx), fmtOffset(cy))
                end
            else
                local canvasX1 = math.min(dim.x1, offsetX)
                local canvasY1 = math.min(dim.y1, offsetY)
                local canvasX2 = math.max(dim.x2, newX2)
                local canvasY2 = math.max(dim.y2, newY2)
                local canvasW = canvasX2 - canvasX1
                local canvasH = canvasY2 - canvasY1
                local needsExpand = (canvasX1 < dim.x1 or canvasY1 < dim.y1 or canvasX2 > dim.x2 or canvasY2 > dim.y2)

                lines[#lines+1] = string.format("New floor at (%d, %d) to (%d, %d).", offsetX, offsetY, newX2, newY2)
                if needsExpand then
                    lines[#lines+1] = string.format("Map canvas will expand to %dx%d tiles.", canvasW, canvasH)
                else
                    lines[#lines+1] = "New floor fits within the existing canvas."
                end
            end

            element.text = table.concat(lines, realignTarget ~= nil and "\n" or " ")
        end,
    }

    -- The preview area: shows actual images of both floors with grid overlay.
    -- Supports mouse wheel zoom, right-drag to pan, left-drag to move new floor.
    local previewSize = 620

    -- View state: zoom level and center position in tile coordinates.
    -- Start zoomed out to fit everything.
    local canvasX1Init, canvasY1Init, canvasX2Init, canvasY2Init
    if realignTarget ~= nil then
        canvasX1Init = offsetX
        canvasY1Init = offsetY
        canvasX2Init = offsetX + floorW
        canvasY2Init = offsetY + floorH
        for _, ref in ipairs(references) do
            canvasX1Init = math.min(canvasX1Init, ref.x1)
            canvasY1Init = math.min(canvasY1Init, ref.y1)
            canvasX2Init = math.max(canvasX2Init, ref.x2)
            canvasY2Init = math.max(canvasY2Init, ref.y2)
        end
    else
        canvasX1Init = math.min(dim.x1, offsetX)
        canvasY1Init = math.min(dim.y1, offsetY)
        canvasX2Init = math.max(dim.x2, offsetX + floorW)
        canvasY2Init = math.max(dim.y2, offsetY + floorH)
    end
    local canvasWInit = canvasX2Init - canvasX1Init
    local canvasHInit = canvasY2Init - canvasY1Init

    local viewCenterX = (canvasX1Init + canvasX2Init) / 2
    local viewCenterY = (canvasY1Init + canvasY2Init) / 2
    -- Pixels per tile at zoom=1: fit the initial canvas with padding.
    local basePixelsPerTile = (previewSize - 20) / (math.max(canvasWInit, canvasHInit) * 1.1)
    local viewZoom = 1.0
    local minZoom = 0.5
    local maxZoom = 20.0

    -- Drag state for moving the new floor.
    local isDraggingFloor = false
    local dragStartOffsetX = 0
    local dragStartOffsetY = 0
    -- Pan drag state: track the view center at drag start.
    local panStartCenterX = 0
    local panStartCenterY = 0

    local function getPixelsPerTile()
        return basePixelsPerTile * viewZoom
    end

    -- Convert tile coords to pixel coords in the preview panel.
    -- Map coords: +X right, +Y UP. Panel coords: +X right, +Y DOWN.
    -- So we negate Y to flip the vertical axis.
    local function tileToPixel(tx, ty)
        local ppt = getPixelsPerTile()
        local cx = previewSize / 2
        local cy = previewSize / 2
        return cx + (tx - viewCenterX) * ppt, cy - (ty - viewCenterY) * ppt
    end

    -- Convert pixel coords in the preview panel to tile coords.
    local function pixelToTile(px, py)
        local ppt = getPixelsPerTile()
        local cx = previewSize / 2
        local cy = previewSize / 2
        return viewCenterX + (px - cx) / ppt, viewCenterY - (py - cy) / ppt
    end

    local function updateInputsFromOffset()
        offsetXInput.textNoNotify = fmtOffset(offsetX)
        offsetYInput.textNoNotify = fmtOffset(offsetY)
    end

    -- Get panel top-left pixel position for a tile rect.
    -- Map coords: +Y up. Panel coords: +Y down.
    -- The top of the rect (tileY + tileH, highest Y) maps to the smallest pixel Y.
    local function rectToPanel(tileX, tileY, tileW, tileH)
        local ppt = getPixelsPerTile()
        local px, _ = tileToPixel(tileX, 0)
        local _, py = tileToPixel(0, tileY + tileH)
        return px, py, tileW * ppt, tileH * ppt
    end

    -- Persistent image panels: created once and re-positioned in updatePreview
    -- to avoid the white-flash that occurred when bgimage panels were rebuilt
    -- every frame during drag. A panel listed in element.children is preserved
    -- across the assignment, so we always include these in the rebuilt list.
    -- Reference panels (one per ref). Each is the static backdrop image of an
    -- already-placed Map object (realign mode), or the canvas-sized existing
    -- image (normal mode).
    local refImagePanels = {}
    local refBorderPanels = {}
    if realignTarget ~= nil then
        for i, ref in ipairs(references) do
            if ref.imageid ~= nil then
                refImagePanels[i] = gui.Panel{
                    bgimage = ref.imageid,
                    bgimageStreamed = ref.imageid,
                    bgcolor = "white",
                    halign = "left", valign = "top",
                    x = 0, y = 0,
                    width = 0, height = 0,
                }
            end
            refBorderPanels[i] = gui.Panel{
                halign = "left", valign = "top",
                x = 0, y = 0,
                width = 0, height = 0,
                borderColor = "#6699cc",
                borderWidth = 2,
            }
        end
    elseif existingImageId ~= nil then
        refImagePanels[1] = gui.Panel{
            bgimage = existingImageId,
            bgimageStreamed = existingImageId,
            bgcolor = "white",
            halign = "left", valign = "top",
            x = 0, y = 0,
            width = 0, height = 0,
        }
    end

    -- Moving floor image panel: persistent so dragging doesn't recreate it.
    local movingImagePanel = nil
    if newImageId ~= nil then
        movingImagePanel = gui.Panel{
            bgimage = newImageId,
            bgimageStreamed = newImageId,
            bgcolor = "white",
            opacity = newFloorOpacity,
            halign = "left", valign = "top",
            x = 0, y = 0,
            width = 0, height = 0,
        }
    end

    -- Moving floor border (always present, drawn on top of grid lines).
    local movingBorderPanel = gui.Panel{
        halign = "left", valign = "top",
        x = 0, y = 0,
        width = 0, height = 0,
        borderColor = "#cc9966",
        borderWidth = 2,
    }

    -- Canvas border for normal mode.
    local canvasBorderPanel = nil
    if realignTarget == nil then
        canvasBorderPanel = gui.Panel{
            halign = "left", valign = "top",
            x = 0, y = 0,
            width = 0, height = 0,
            borderColor = "#6699cc",
            borderWidth = 2,
        }
    end

    -- Right/middle-click pan state. Tracks previous mouse position while either
    -- button is held and applies a delta-pan in the think callback.
    local panPrevX = nil
    local panPrevY = nil

    previewPanel = gui.Panel{
        width = previewSize,
        height = previewSize,
        halign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#111111",
        flow = "none",
        borderColor = "#555555",
        borderWidth = 1,
        clip = true,
        data = {},

        -- Dragging: right-drag to pan, left-drag to move new floor.
        -- Middle-click pan is handled separately in the think callback.
        draggable = true,
        dragMove = false,
        dragThreshold = 2,

        events = {
            press = function(element)
                -- Right/middle button drags are handled in `think` (the engine's drag
                -- system only triggers `dragging` for left-click). Skip them here.
                if element:GetMouseButton(1) or element:GetMouseButton(2) then
                    isDraggingFloor = false
                    return
                end

                local mp = element.mousePoint
                if mp == nil then return end
                -- mousePoint is in normalized [0,1] panel-local coords. Convert to
                -- panel-local pixel coords (top-left = 0,0; +y down).
                local mx = mp.x * previewSize
                local my = (1 - mp.y) * previewSize

                -- Left mouse: check if over the new floor image.
                local nx, ny, nw, nh = rectToPanel(offsetX, offsetY, floorW, floorH)
                if mx >= nx and mx <= nx + nw and my >= ny and my <= ny + nh then
                    isDraggingFloor = true
                    dragStartOffsetX = offsetX
                    dragStartOffsetY = offsetY
                else
                    isDraggingFloor = false
                    panStartCenterX = viewCenterX
                    panStartCenterY = viewCenterY
                end
            end,

            dragging = function(element)
                -- dragDelta is cumulative from drag start, in panel pixel coords.
                local dd = element.dragDelta
                -- Convert pixel delta to tile delta using pixelToTile math.
                -- pixelToTile: tileX = viewCenterX + (px - cx) / ppt
                -- So a pixel delta of dd.x maps to tile delta of dd.x / ppt (for X)
                -- and dd.y maps to tile delta of -dd.y / ppt (for Y, because Y is flipped)
                local ppt = getPixelsPerTile()
                local dtx = dd.x / ppt
                local dty = -dd.y / ppt  -- negate: panel +y is down, tile +y is up
                if isDraggingFloor then
                    -- Move the new floor, snapping to tile boundaries.
                    local newOX = dragStartOffsetX + math.floor(dtx + 0.5)
                    local newOY = dragStartOffsetY + math.floor(dty + 0.5)
                    if newOX ~= offsetX or newOY ~= offsetY then
                        offsetX = newOX
                        offsetY = newOY
                        updateInputsFromOffset()
                        fireUpdatePreview()
                    end
                else
                    -- Pan the view using cumulative delta from start.
                    viewCenterX = panStartCenterX - dtx
                    viewCenterY = panStartCenterY - dty
                    element:FireEvent("updatePreview")
                end
            end,

            drag = function(element)
                -- Drag ended.
                isDraggingFloor = false
                fireUpdatePreview()
            end,
        },

        -- Mouse wheel zoom + middle-click pan. Middle-click is handled here
        -- because the engine's drag system only triggers `dragging` callbacks
        -- on left/right click, not middle.
        thinkTime = 0.02,
        think = function(element)
            -- mousePoint is nil when the mouse isn't over the panel. When present,
            -- it is in normalized [0,1] panel-local coords -- multiply by previewSize
            -- to get panel-local pixels (top-left = 0,0; +y down).
            local mp = element.mousePoint
            local mouseInside = mp ~= nil
            local mx, my = 0, 0
            if mouseInside then
                mx = mp.x * previewSize
                my = (1 - mp.y) * previewSize
            end

            -- Mouse wheel zoom (only when mouse is over the panel).
            local wheel = dmhub.mouseWheel
            if mouseInside and wheel ~= 0 then
                local tileBefore_x, tileBefore_y = pixelToTile(mx, my)

                if wheel > 0 then
                    viewZoom = math.min(maxZoom, viewZoom * 1.15)
                else
                    viewZoom = math.max(minZoom, viewZoom / 1.15)
                end

                -- Adjust center so the tile under the mouse stays in place.
                local tileAfter_x, tileAfter_y = pixelToTile(mx, my)
                viewCenterX = viewCenterX + (tileBefore_x - tileAfter_x)
                viewCenterY = viewCenterY + (tileBefore_y - tileAfter_y)

                element:FireEvent("updatePreview")
            end

            -- Right-click or middle-click drag pans. The engine's drag system only
            -- fires `dragging` callbacks for left-click, so we poll GetMouseButton.
            local panning = element:GetMouseButton(1) or element:GetMouseButton(2)
            if panning and mouseInside then
                if panPrevX ~= nil then
                    local dx = mx - panPrevX
                    local dy = my - panPrevY
                    if dx ~= 0 or dy ~= 0 then
                        local ppt = getPixelsPerTile()
                        viewCenterX = viewCenterX - dx / ppt
                        viewCenterY = viewCenterY + dy / ppt
                        element:FireEvent("updatePreview")
                    end
                end
                panPrevX = mx
                panPrevY = my
            else
                panPrevX = nil
                panPrevY = nil
            end

            -- Arrow-key nudge (1 tile per press, with edge-detection so a held key
            -- moves once per think tick).
            local function arrowEdge(key, prevField)
                local down = dmhub.KeyPressed(key)
                local prev = element.data[prevField]
                element.data[prevField] = down
                return down and not prev
            end
            local nudgedX = 0
            local nudgedY = 0
            if arrowEdge("LeftArrow",  "ke_left")  then nudgedX = nudgedX - 1 end
            if arrowEdge("RightArrow", "ke_right") then nudgedX = nudgedX + 1 end
            if arrowEdge("UpArrow",    "ke_up")    then nudgedY = nudgedY + 1 end
            if arrowEdge("DownArrow",  "ke_down")  then nudgedY = nudgedY - 1 end
            if nudgedX ~= 0 or nudgedY ~= 0 then
                offsetX = offsetX + nudgedX
                offsetY = offsetY + nudgedY
                updateInputsFromOffset()
                fireUpdatePreview()
            end
        end,

        updatePreview = function(element)
            local ppt = getPixelsPerTile()

            local children = {}

            -- Update persistent backdrop panels with current positions.
            if realignTarget ~= nil then
                for i, ref in ipairs(references) do
                    local ex, ey, ew, eh = rectToPanel(ref.x1, ref.y1, ref.x2 - ref.x1, ref.y2 - ref.y1)
                    if refImagePanels[i] ~= nil then
                        refImagePanels[i].x = ex
                        refImagePanels[i].y = ey
                        refImagePanels[i].selfStyle.width = ew
                        refImagePanels[i].selfStyle.height = eh
                        children[#children+1] = refImagePanels[i]
                    end
                end
            elseif refImagePanels[1] ~= nil then
                local ex, ey, ew, eh = rectToPanel(dim.x1, dim.y1, mapW, mapH)
                refImagePanels[1].x = ex
                refImagePanels[1].y = ey
                refImagePanels[1].selfStyle.width = ew
                refImagePanels[1].selfStyle.height = eh
                children[#children+1] = refImagePanels[1]
            end

            -- Update persistent moving-floor panel.
            if movingImagePanel ~= nil then
                local nx, ny, nw, nh = rectToPanel(offsetX, offsetY, floorW, floorH)
                movingImagePanel.x = nx
                movingImagePanel.y = ny
                movingImagePanel.selfStyle.width = nw
                movingImagePanel.selfStyle.height = nh
                movingImagePanel.selfStyle.opacity = newFloorOpacity
                children[#children+1] = movingImagePanel
            end

            -- Grid lines: only draw visible ones.
            -- Compute visible tile range from viewport.
            local visTileX1, visTileY1 = pixelToTile(0, 0)
            local visTileX2, visTileY2 = pixelToTile(previewSize, previewSize)
            -- Ensure x1 < x2, y1 < y2.
            if visTileX1 > visTileX2 then visTileX1, visTileX2 = visTileX2, visTileX1 end
            if visTileY1 > visTileY2 then visTileY1, visTileY2 = visTileY2, visTileY1 end

            local gridX1 = math.floor(visTileX1)
            local gridX2 = math.ceil(visTileX2)
            local gridY1 = math.floor(visTileY1)
            local gridY2 = math.ceil(visTileY2)

            -- Skip grid lines if too dense (more than ~200 visible).
            local gridCountX = gridX2 - gridX1
            local gridCountY = gridY2 - gridY1
            if gridCountX <= 200 and gridCountY <= 200 then
                -- Determine grid line thickness based on zoom.
                local lineW = math.max(1, math.floor(ppt / 32))

                -- Vertical grid lines.
                for tx = gridX1, gridX2 do
                    local px, _ = tileToPixel(tx, 0)
                    children[#children+1] = gui.Panel{
                        bgimage = "panels/square.png",
                        bgcolor = "#ffffff18",
                        halign = "left", valign = "top",
                        x = px, y = 0,
                        width = lineW, height = previewSize,
                    }
                end

                -- Horizontal grid lines.
                for ty = gridY1, gridY2 do
                    local _, py = tileToPixel(0, ty)
                    children[#children+1] = gui.Panel{
                        bgimage = "panels/square.png",
                        bgcolor = "#ffffff18",
                        halign = "left", valign = "top",
                        x = 0, y = py,
                        width = previewSize, height = lineW,
                    }
                end
            end

            -- Reference borders (persistent).
            if realignTarget ~= nil then
                for i, ref in ipairs(references) do
                    if refBorderPanels[i] ~= nil then
                        local bx, by, bw, bh = rectToPanel(ref.x1, ref.y1, ref.x2 - ref.x1, ref.y2 - ref.y1)
                        refBorderPanels[i].x = bx
                        refBorderPanels[i].y = by
                        refBorderPanels[i].selfStyle.width = bw
                        refBorderPanels[i].selfStyle.height = bh
                        children[#children+1] = refBorderPanels[i]
                    end
                end
            elseif canvasBorderPanel ~= nil then
                local bx, by, bw, bh = rectToPanel(dim.x1, dim.y1, mapW, mapH)
                canvasBorderPanel.x = bx
                canvasBorderPanel.y = by
                canvasBorderPanel.selfStyle.width = bw
                canvasBorderPanel.selfStyle.height = bh
                children[#children+1] = canvasBorderPanel
            end

            -- Moving floor border (persistent).
            do
                local bx, by, bw, bh = rectToPanel(offsetX, offsetY, floorW, floorH)
                movingBorderPanel.x = bx
                movingBorderPanel.y = by
                movingBorderPanel.selfStyle.width = bw
                movingBorderPanel.selfStyle.height = bh
                children[#children+1] = movingBorderPanel
            end

            element.children = children
        end,
    }

    local opacitySlider = gui.Slider{
        style = {
            height = 20,
            width = 200,
            fontSize = 14,
        },
        halign = "left",
        sliderWidth = 140,
        labelWidth = 60,
        labelFormat = "percent",
        minValue = 0,
        maxValue = 100,
        value = 60,
        change = function(element)
            newFloorOpacity = element.value * 0.01
            fireUpdatePreview()
        end,
    }

    local function resetView()
        local cx1, cy1, cx2, cy2
        if realignTarget ~= nil then
            cx1 = offsetX
            cy1 = offsetY
            cx2 = offsetX + floorW
            cy2 = offsetY + floorH
            for _, ref in ipairs(references) do
                cx1 = math.min(cx1, ref.x1)
                cy1 = math.min(cy1, ref.y1)
                cx2 = math.max(cx2, ref.x2)
                cy2 = math.max(cy2, ref.y2)
            end
        else
            cx1 = math.min(dim.x1, offsetX)
            cy1 = math.min(dim.y1, offsetY)
            cx2 = math.max(dim.x2, offsetX + floorW)
            cy2 = math.max(dim.y2, offsetY + floorH)
        end
        viewCenterX = (cx1 + cx2) / 2
        viewCenterY = (cy1 + cy2) / 2
        local cw = cx2 - cx1
        local ch = cy2 - cy1
        basePixelsPerTile = (previewSize - 20) / (math.max(cw, ch) * 1.1)
        viewZoom = 1.0
        fireUpdatePreview()
    end

    -- Zoom slider, log-scaled so the user can sweep across the [minZoom, maxZoom]
    -- range smoothly. Slider value 0..100 maps to log(minZoom)..log(maxZoom).
    local logMin = math.log(minZoom)
    local logMax = math.log(maxZoom)
    local function zoomToSlider(z)
        return (math.log(z) - logMin) / (logMax - logMin) * 100
    end
    local function sliderToZoom(s)
        return math.exp(s / 100 * (logMax - logMin) + logMin)
    end

    local zoomSlider = gui.Slider{
        style = { height = 20, width = 200, fontSize = 14 },
        sliderWidth = 140,
        labelWidth = 60,
        minValue = 0,
        maxValue = 100,
        value = zoomToSlider(viewZoom),
        change = function(element)
            viewZoom = sliderToZoom(element.value)
            fireUpdatePreview()
        end,
        thinkTime = 0.1,
        think = function(element)
            if not element.dragging then
                element.data.setValueNoEvent(zoomToSlider(viewZoom))
            end
        end,
    }

    local controlsPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        vmargin = 4,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",

                gui.Label{
                    classes = {"sizeS"},
                    width = "auto",
                    height = "auto",
                    text = "Top-left at tile: ",
                },
                offsetXInput,
                gui.Label{
                    classes = {"sizeS"},
                    width = "auto",
                    height = "auto",
                    text = " , ",
                },
                offsetYInput,
            },

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                hmargin = 16,

                gui.Label{
                    classes = {"sizeS"},
                    width = "auto",
                    height = "auto",
                    text = "Opacity: ",
                },
                opacitySlider,
            },

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                hmargin = 16,

                gui.Label{
                    classes = {"sizeS"},
                    width = "auto",
                    height = "auto",
                    text = "Zoom: ",
                },
                zoomSlider,
            },

            gui.Button{
                classes = {"sizeM"},
                text = "Reset View",
                halign = "right",
                click = function()
                    resetView()
                end,
            },
        },

        gui.Label{
            classes = {"form", "sizeS"},
            width = "auto",
            height = "auto",
            text = realignTarget ~= nil
                and "Drag this floor to reposition it. Scroll or use the zoom slider. Middle-click drag or drag background to pan."
                or "Drag the new floor to position it. Scroll or use the zoom slider. Middle-click drag or drag background to pan.",
        },
    }

    local dialogPanel = gui.Panel{
        id = "alignDialog",
        classes = {"framedPanel"},
        width = 1000,
        height = 940,
        pad = 16,
        flow = "vertical",
        styles = ThemeEngine.GetStyles(),

        gui.Label{
            classes = {"modalTitle"},
            text = "Align New Floor",
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            vmargin = 4,

            gui.Label{
                classes = {"sizeS"},
                width = "auto",
                height = "auto",
                text = realignTarget ~= nil
                    and string.format("Floor: %.2f x %.2f tiles  |  %d other map object(s) shown.", floorW, floorH, #references)
                    or string.format("Existing map: %dx%d tiles  |  New floor: %dx%d tiles", mapW, mapH, floorW, floorH),
            },
        },

        previewPanel,

        controlsPanel,
        previewLabel,

        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            halign = "center",
            vmargin = 8,

            gui.Button{
                classes = {"sizeL"},
                text = "Confirm",
                click = function()
                    if realignTarget ~= nil then
                        -- Convert offset (top-left of rendered image, == areaX1/Y1)
                        -- back to obj.x/obj.y using the renderer's pivot. This is
                        -- the inverse of `areaX1 = pos.x - imageWorldWidth * mapPivot.x`.
                        local newPosX = offsetX + floorW * realignPivotX
                        local newPosY = offsetY + floorH * realignPivotY
                        printf("FLOOR_REALIGN:: Confirm clicked: offset=(%.4f, %.4f) pivot=(%.6f, %.6f) -> obj.x=%.4f obj.y=%.4f",
                            offsetX, offsetY, realignPivotX, realignPivotY, newPosX, newPosY)
                        gui.CloseModal()
                        realignTarget:MarkUndo()
                        realignTarget.x = newPosX
                        realignTarget.y = newPosY
                        realignTarget:Upload()
                    else
                        printf("FLOOR_ALIGN:: Confirm clicked: offsetX=%d offsetY=%d", offsetX, offsetY)
                        gui.CloseModal()
                        mod.shared.FinishFloorImport(info, offsetX, offsetY)
                    end
                end,
            },

            gui.Button{
                classes = {"sizeL"},
                text = "Cancel",
                escapeActivates = true,
                escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                click = function()
                    gui.CloseModal()
                end,
            },
        },

        gui.Button{
            classes = {"closeButton"},
            halign = "right",
            valign = "top",
            floating = true,
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function()
                gui.CloseModal()
            end,
        },

        create = function(element)
            fireUpdatePreview()
        end,
    }

    gui.ShowModal(dialogPanel)
end

-- Reimport map sizing: re-run the grid calibration on an existing map object.
-- floor: the MapFloorLua that contains the map object
-- mapObj: the LuaObjectInstance with a Map component
mod.shared.ReimportMapSizing = function(floor, mapObj)
    local imageId = mapObj.imageid
    if imageId == nil or imageId == "" then
        gui.ModalMessage{
            title = "Error",
            message = "Could not find image for this map object.",
        }
        return
    end

    -- Capture the current object's tile dimensions for gridless defaults.
    local currentArea = mapObj.area
    local currentTilesW = nil
    local currentTilesH = nil
    if currentArea ~= nil then
        currentTilesW = math.abs(currentArea.x2 - currentArea.x1)
        currentTilesH = math.abs(currentArea.y2 - currentArea.y1)
        printf("REIMPORT:: Current object area: (%.1f,%.1f)-(%.1f,%.1f) = %.1fx%.1f tiles",
            currentArea.x1, currentArea.y1, currentArea.x2, currentArea.y2, currentTilesW, currentTilesH)
    end

    printf("REIMPORT:: Starting reimport for object %s on floor %s, imageId=%s", mapObj.id, floor.floorid, imageId)

    -- Build a reimport dialog using gui.MapImport with imageFromId.
    local resultPanel
    local importPanel
    local gridlessInitApplied = false

    local confirmButton = gui.Button{
        classes = {"sizeL", "hidden"},
        text = "Apply",
        valign = "center",
        halign = "center",
        click = function()
            -- Get calibration data from the import panel before closing.
            local calibration = importPanel:GetCalibrationData()
            if calibration == nil then
                gui.ModalMessage{
                    title = "Error",
                    message = "Calibration data not available. Please complete the grid sizing.",
                }
                return
            end

            printf("REIMPORT:: Applying calibration: width=%.1f height=%.1f scaling=%d controlPoints=%d",
                calibration.width, calibration.height, calibration.scaling, #calibration.controlPoints)

            -- Apply the calibration directly to the existing object's Map component
            -- using the C# method (avoids JSON serialization issues with Vector2 lists).
            mapObj:MarkUndo()
            importPanel:ApplyCalibrationTo(mapObj)

            gui.CloseModal()

            mapObj:Upload()

            printf("REIMPORT:: Applied new calibration to object %s", mapObj.id)

            -- Adjust map boundaries synchronously.
            -- For the reimported floor: compute bounds from calibration data + object center
            -- (don't read obj.area which is stale until re-render).
            -- For other floors: read their area directly (they haven't changed).
            local map = game.currentMap
            if map ~= nil then
                local objX = mapObj.x
                local objY = mapObj.y
                local floorX1 = objX - calibration.width / 2
                local floorY1 = objY - calibration.height / 2
                local floorX2 = objX + calibration.width / 2
                local floorY2 = objY + calibration.height / 2
                printf("REIMPORT:: Reimported floor bounds: (%.1f,%.1f)-(%.1f,%.1f) objPos=(%.1f,%.1f)",
                    floorX1, floorY1, floorX2, floorY2, objX, objY)

                -- Start with the reimported floor's computed bounds.
                local newDimX1 = floorX1
                local newDimY1 = floorY1
                local newDimX2 = floorX2
                local newDimY2 = floorY2

                -- Union with all other map objects' areas (these are already rendered, not stale).
                for _, f in ipairs(map.floors) do
                    for _, obj in pairs(f.objects) do
                        if obj:GetComponent("Map") ~= nil and obj.id ~= mapObj.id then
                            local a = obj.area
                            if a ~= nil then
                                printf("REIMPORT::   Other floor obj %s area: (%.1f,%.1f)-(%.1f,%.1f)", obj.id, a.x1, a.y1, a.x2, a.y2)
                                newDimX1 = math.min(newDimX1, a.x1)
                                newDimY1 = math.min(newDimY1, a.y1)
                                newDimX2 = math.max(newDimX2, a.x2)
                                newDimY2 = math.max(newDimY2, a.y2)
                            end
                        end
                    end
                end

                local dim = map.dimensions
                printf("REIMPORT:: Old dims: (%s,%s)-(%s,%s)", json(dim.x1), json(dim.y1), json(dim.x2), json(dim.y2))
                printf("REIMPORT:: New dims: (%.1f,%.1f)-(%.1f,%.1f)", newDimX1, newDimY1, newDimX2, newDimY2)

                map.dimensions = {
                    x1 = math.floor(newDimX1),
                    y1 = math.floor(newDimY1),
                    x2 = math.ceil(newDimX2),
                    y2 = math.ceil(newDimY2),
                }
                map:Upload("Adjust map boundaries after reimport")
                printf("REIMPORT:: Set map boundaries to (%d,%d)-(%d,%d)",
                    math.floor(newDimX1), math.floor(newDimY1), math.ceil(newDimX2), math.ceil(newDimY2))
            end
        end,
    }

    local continueButton = gui.Button{
        classes = {"sizeL", "hidden"},
        text = "Continue>>",
        valign = "center",
        halign = "center",
        click = function()
            importPanel:Next()
        end,
    }

    local previousButton = gui.Button{
        classes = {"sizeL", "hidden"},
        text = "Back",
        valign = "center",
        halign = "left",
        click = function()
            importPanel:Previous()
        end,
    }

    local buttonsPanel = gui.Panel{
        valign = "bottom",
        halign = "center",
        width = "70%",
        height = "auto",
        flow = "none",
        previousButton,
        continueButton,
        confirmButton,
    }

    local instructionsText = gui.Label{
        width = 400,
        height = "auto",
        wrap = true,
        textAlignment = "topleft",
        fontSize = 18,
        halign = "left",
        valign = "top",
    }

    local gridlessChoice = gui.EnumeratedSliderControl{
        options = {
            {id = true, text = "Grid"},
            {id = false, text = "Gridless"},
        },
        width = 400,
        valign = "top",
        value = true,
        change = function(element)
            if element.value == true then
                importPanel:ClearMarkers()
            else
                importPanel:CreateGridless()
                -- Apply current tile dimensions as the default for gridless mode.
                if currentTilesW ~= nil and currentTilesW > 0 and currentTilesH ~= nil and currentTilesH > 0 then
                    local imgW = importPanel.imageWidth
                    local imgH = importPanel.imageHeight
                    if imgW ~= nil and imgW > 0 and imgH ~= nil and imgH > 0 then
                        local tilePixelW = imgW / currentTilesW
                        local tilePixelH = imgH / currentTilesH
                        importPanel:SetWidth(tilePixelW)
                        importPanel:SetHeight(tilePixelH)
                        printf("REIMPORT:: Set gridless defaults: %.1fx%.1f px/tile (%.0fx%.0f tiles)", tilePixelW, tilePixelH, currentTilesW, currentTilesH)
                    end
                end
            end
        end,
        vmargin = 16,
    }

    local instructionsPanel = gui.Panel{
        width = 400,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        instructionsText,
        gridlessChoice,
    }

    local statusWidth = gui.Input{
        fontSize = 16, width = 80, height = 24,
        change = function(element)
            local val = tonumber(element.text)
            if val ~= nil and val >= 8 and val <= 4096 then
                importPanel:SetWidth(val)
            end
        end,
    }
    local statusHeight = gui.Input{
        fontSize = 16, width = 80, height = 24,
        change = function(element)
            local val = tonumber(element.text)
            if val ~= nil and val >= 8 and val <= 4096 then
                importPanel:SetHeight(val)
            end
        end,
    }

    local statusPanel = gui.Panel{
        classes = {"hidden"},
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",

        gui.Label{
            width = "auto",
            height = "auto",
            halign = "center",
            fontSize = 22,
            bold = true,
            text = "Tile Dimensions",
        },

        gui.Panel{
            flow = "horizontal", width = "auto", height = "auto",
            gui.Label{ classes = {"sizeL"}, width = 90, height = "auto", text = "Width:"},
            statusWidth,
            gui.Label{ classes = {"sizeL"}, lmargin = 4, width = "auto", height = "auto", text = "px"},
        },

        gui.Panel{
            flow = "horizontal", width = "auto", height = "auto",
            gui.Label{ classes = {"sizeL"}, width = 90, height = "auto", text = "Height:"},
            statusHeight,
            gui.Label{ classes = {"sizeL"}, lmargin = 4, width = "auto", height = "auto", text = "px"},
        },
    }

    local zoomSlider = gui.Slider{
        style = { height = 20, width = 200, fontSize = 14 },
        halign = "right",
        valign = "top",
        sliderWidth = 140,
        labelWidth = 60,
        labelFormat = "percent",
        minValue = 0,
        maxValue = 100,
        value = 100,
        thinkTime = 0.1,
        change = function(element)
            importPanel.zoom = element.value * 0.01
        end,
        think = function(element)
            if not element.dragging then
                element.data.setValueNoEvent(importPanel.zoom * 100)
            end
        end,
    }

    -- Create the MapImport panel, loading from the cloud image ID.
    importPanel = gui.MapImport{
        width = 800,
        height = 800,
        halign = "right",
        valign = "top",
        y = 26,
        tileType = "squares",
        imageFromId = imageId,

        thinkTime = 0.05,
        think = function(element)
            gridlessChoice:SetClass("hidden", gridlessChoice.value and (element.haveNext or element.havePrevious or element.haveConfirm or not string.starts_with(element.instructionsText, "Pick a grid square")))
            previousButton:SetClass("hidden", not element.havePrevious)
            continueButton:SetClass("hidden", not element.haveNext)
            confirmButton:SetClass("hidden", not element.haveConfirm)
            instructionsText.text = element.instructionsText

            local tileDim = element.tileDim
            if tileDim == nil then
                statusPanel:SetClass("hidden", true)
            else
                statusPanel:SetClass("hidden", false)
                if (not statusWidth.hasInputFocus) and (not statusHeight.hasInputFocus) then
                    statusWidth.textNoNotify = string.format("%.2f", tileDim.x)
                    statusHeight.textNoNotify = string.format("%.2f", tileDim.y)
                end
            end

            if element.error ~= nil then
                resultPanel.children = {
                    gui.Label{
                        halign = "center", valign = "center",
                        width = "auto", height = "auto",
                        fontSize = 18,
                        text = string.format("Error: %s", element.error),
                    }
                }
            end
        end,
    }

    resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        flow = "none",
        zoomSlider,
        importPanel,
        buttonsPanel,
        instructionsPanel,
        statusPanel,
    }

    local dialogPanel = gui.Panel{
        classes = {"framedPanel"},
        width = 1400,
        height = 940,
        pad = 8,
        flow = "vertical",
        styles = ThemeEngine.GetStyles(),

        gui.Label{
            classes = {"modalTitle"},
            text = "Reimport Map Sizing",
        },

        resultPanel,

        gui.Button{
            classes = {"closeButton"},
            halign = "right",
            valign = "top",
            floating = true,
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function()
                gui.CloseModal()
            end,
        },
    }

    gui.ShowModal(dialogPanel)
end

-- Import a floor image into the current map as a new floor.
-- Creates a primary floor + a map layer on it (matching initial map import structure).
-- info: import result with objids, width, height, mapSettings.
-- offsetX, offsetY: tile position for the new floor's top-left corner.
mod.shared.FinishFloorImport = function(info, offsetX, offsetY)
    printf("FLOOR_IMPORT:: ===== BEGIN FinishFloorImport =====")

    if info.objids == nil or #info.objids == 0 then
        printf("FLOOR_IMPORT:: ERROR: No objids")
        return
    end

    if game.currentMap == nil then
        printf("FLOOR_IMPORT:: ERROR: No current map")
        return
    end

    local mapId = game.currentMap.id
    -- Round to nearest tile (see CreateMap comment above).
    local floorW = math.floor(info.width + 0.5)
    local floorH = math.floor(info.height + 0.5)
    offsetX = offsetX or game.currentMap.dimensions.x1
    offsetY = offsetY or game.currentMap.dimensions.y1

    printf("FLOOR_IMPORT:: mapId=%s floorW=%d floorH=%d offsetX=%d offsetY=%d", mapId, floorW, floorH, offsetX, offsetY)

    -- Compute the object center position.
    local objCenterX = offsetX + floorW / 2
    local objCenterY = offsetY + floorH / 2
    printf("FLOOR_IMPORT:: Object center: (%.1f, %.1f)", objCenterX, objCenterY)

    -- Collect existing floor IDs before creating anything.
    local existingFloorIds = {}
    for _, floor in ipairs(game.currentMap.floors) do
        existingFloorIds[floor.floorid] = true
    end
    printf("FLOOR_IMPORT:: Existing floor count: %d", #game.currentMap.floors)

    -- Create the primary floor. Don't do any other map mutations before this --
    -- Upload() and CreateFloor() both patch the manifest and can conflict.
    game.currentMap:CreateFloor()
    printf("FLOOR_IMPORT:: Called CreateFloor(), starting coroutine to wait for sync...")

    dmhub.Coroutine(function()
        -- Helper to get the fresh map reference.
        local function getMap()
            return game.GetMap(mapId)
        end

        -- Wait for a new primary floor to appear (one not in our snapshot).
        local primaryFloor = nil
        for attempt = 1, 200 do
            local map = getMap()
            if map ~= nil then
                for _, floor in ipairs(map.floors) do
                    if not existingFloorIds[floor.floorid] and floor.isPrimaryLayerOnFloor then
                        primaryFloor = floor
                        break
                    end
                end
            end
            if primaryFloor ~= nil then break end
            coroutine.yield(0.05)
        end

        if primaryFloor == nil then
            printf("FLOOR_IMPORT:: ERROR: Timed out waiting for primary floor")
            return
        end

        printf("FLOOR_IMPORT:: Found primary floor: id=%s desc='%s'", primaryFloor.floorid, primaryFloor.description)

        -- Brief sync pause.
        for i = 1, 10 do coroutine.yield(0.01) end

        -- Step 2: Create a map layer on this primary floor.
        local existingFloorIds2 = {}
        local map = getMap()
        for _, floor in ipairs(map.floors) do
            existingFloorIds2[floor.floorid] = true
        end

        printf("FLOOR_IMPORT:: Creating map layer with parentFloor=%s", primaryFloor.floorid)
        map:CreateFloor{parentFloor = primaryFloor.floorid}

        -- Wait for the layer to appear.
        local mapLayer = nil
        for attempt = 1, 200 do
            map = getMap()
            if map ~= nil then
                for _, floor in ipairs(map.floors) do
                    if not existingFloorIds2[floor.floorid] then
                        mapLayer = floor
                        break
                    end
                end
            end
            if mapLayer ~= nil then break end
            coroutine.yield(0.05)
        end

        if mapLayer == nil then
            printf("FLOOR_IMPORT:: ERROR: Timed out waiting for map layer")
            return
        end

        printf("FLOOR_IMPORT:: Found map layer: id=%s parentFloor=%s", mapLayer.floorid, json(mapLayer.parentFloor))

        -- Label the layer.
        mapLayer.layerDescription = "Map Layer"

        -- Step 3: Expand map dimensions to encompass the new floor.
        -- Done here (after floor creation) to avoid conflicting manifest patches.
        -- Skip in match mode: the new floor occupies the same world bounds as the
        -- existing floor it's matching, which is already inside the canvas.
        if info.matchCalibration ~= nil then
            printf("FLOOR_IMPORT:: matchCalibration in effect; skipping canvas expansion.")
        else
            map = getMap()
            if map ~= nil then
                local dim = map.dimensions
                local newX2 = offsetX + floorW
                local newY2 = offsetY + floorH
                local needsExpand = (offsetX < dim.x1 or offsetY < dim.y1 or newX2 > dim.x2 or newY2 > dim.y2)
                if needsExpand then
                    map.dimensions = {
                        x1 = math.min(dim.x1, offsetX),
                        y1 = math.min(dim.y1, offsetY),
                        x2 = math.max(dim.x2, newX2),
                        y2 = math.max(dim.y2, newY2),
                    }
                    map:Upload("Expand map for new floor")
                    printf("FLOOR_IMPORT:: Expanded map dimensions")
                end
            end
        end

        -- Brief sync pause before spawning.
        for i = 1, 30 do coroutine.yield(0.01) end

        -- Step 4: Spawn the imported map image onto the layer.
        -- If matchCalibration is present, we override the new object's controlPoints/scaling/mapType
        -- with the existing map's, and place it at the existing's (x, y) so the world bounds match.
        local applyMatch = info.matchCalibration ~= nil
        if applyMatch then
            printf("FLOOR_IMPORT:: matchCalibration in effect; will override new object calibration to match existing.")
        end
        local newlySpawnedObjs = {}
        for _, objid in ipairs(info.objids) do
            local placeX = applyMatch and info.matchCalibration.x or objCenterX
            local placeY = applyMatch and info.matchCalibration.y or objCenterY
            printf("FLOOR_IMPORT:: Spawning objid=%s onto layer=%s at (%.4f, %.4f)%s",
                objid, mapLayer.floorid, placeX, placeY, applyMatch and " [match mode]" or "")
            local obj = mapLayer:SpawnObjectLocal(objid)
            if obj ~= nil then
                if applyMatch then
                    obj:ApplyMapCalibration(info.matchCalibration)
                end
                obj.x = placeX
                obj.y = placeY
                obj:Upload()
                printf("FLOOR_IMPORT:: Spawned OK. obj.x=%.4f obj.y=%.4f floorIndex=%s", obj.x, obj.y, json(obj.floorIndex))
                newlySpawnedObjs[#newlySpawnedObjs+1] = obj
            else
                printf("FLOOR_IMPORT:: ERROR: SpawnObjectLocal returned nil for %s", objid)
            end
        end

        -- Wait a few frames so the spawned objects render and ObjectComponentMap.Calculate() runs.
        for i = 1, 60 do coroutine.yield(0.01) end

        -- Correct placement now that the renderer has computed the real calibration.
        -- The pre-spawn center estimate assumes a (0.5, 0.5) pivot and treats offset
        -- as a world coordinate, but the real _mapPivot can be off-center by up to a
        -- tile and world tile boundaries sit at half-integers (tile centers are at
        -- integers). Both errors made same-size imports land a full tile off.
        -- Recompute so the image's top-left corner lands exactly on tile (offsetX, offsetY).
        if not applyMatch then
            for _, obj in ipairs(newlySpawnedObjs) do
                local d = obj.mapAlignmentDiagnostic
                if d ~= nil and (d.imageWorldWidth or 0) > 0 and (d.imageWorldHeight or 0) > 0 then
                    local targetX = (offsetX - 0.5) + d.imageWorldWidth * (d.mapPivotX or 0.5)
                    local targetY = (offsetY - 0.5) + d.imageWorldHeight * (d.mapPivotY or 0.5)
                    if math.abs(obj.x - targetX) > 0.0001 or math.abs(obj.y - targetY) > 0.0001 then
                        printf("FLOOR_IMPORT:: Correcting placement from (%.4f, %.4f) to (%.4f, %.4f) using pivot=(%.6f, %.6f)",
                            obj.x, obj.y, targetX, targetY, d.mapPivotX or 0.5, d.mapPivotY or 0.5)
                        obj.x = targetX
                        obj.y = targetY
                        obj:Upload()
                    end
                else
                    printf("FLOOR_IMPORT:: No calibration available for %s; leaving at center estimate", obj.id)
                end
            end
        end

        -- Diagnostic: dump calibration for every Map LevelObject on the map (existing + new).
        printf("FLOOR_ALIGN_DIAG:: ===== Post-spawn calibration dump =====")
        map = getMap()
        if map ~= nil then
            local mapCount = 0
            for _, floor in ipairs(map.floors) do
                for _, obj in pairs(floor.objects) do
                    if obj:GetComponent("Map") ~= nil then
                        mapCount = mapCount + 1
                        local d = obj.mapAlignmentDiagnostic
                        printf("FLOOR_ALIGN_DIAG:: Post-spawn Map object [%d] floorid=%s objid=%s calibration=%s",
                            mapCount, floor.floorid, obj.id, json(d))
                    end
                end
            end
            printf("FLOOR_ALIGN_DIAG:: Total Map objects on map after spawn: %d", mapCount)
        end

        -- Pairwise alignment delta check: compare the first 'existing' Map object
        -- to each newly-spawned one in tile-space and pixel-space.
        if #newlySpawnedObjs > 0 then
            map = getMap()
            local existingDiag = nil
            local existingFloorId = nil
            local existingObjId = nil
            for _, floor in ipairs(map.floors) do
                for _, obj in pairs(floor.objects) do
                    if obj:GetComponent("Map") ~= nil then
                        local isNew = false
                        for _, n in ipairs(newlySpawnedObjs) do
                            if n.id == obj.id then isNew = true break end
                        end
                        if not isNew then
                            existingDiag = obj.mapAlignmentDiagnostic
                            existingFloorId = floor.floorid
                            existingObjId = obj.id
                            break
                        end
                    end
                end
                if existingDiag ~= nil then break end
            end

            if existingDiag ~= nil then
                printf("FLOOR_ALIGN_DIAG:: Reference (existing) Map object floorid=%s objid=%s", existingFloorId, existingObjId)
                for _, newObj in ipairs(newlySpawnedObjs) do
                    local newDiag = newObj.mapAlignmentDiagnostic
                    if newDiag == nil then
                        printf("FLOOR_ALIGN_DIAG:: New object %s had nil mapAlignmentDiagnostic", newObj.id)
                    else
                        local function get(t, k) return t[k] end
                        local exTilesX = get(existingDiag, "tilesAcross") or 0
                        local newTilesX = get(newDiag, "tilesAcross") or 0
                        local exTilesY = get(existingDiag, "tilesDown") or 0
                        local newTilesY = get(newDiag, "tilesDown") or 0
                        local exImgW = get(existingDiag, "imageWorldWidth") or 0
                        local newImgW = get(newDiag, "imageWorldWidth") or 0
                        local exImgH = get(existingDiag, "imageWorldHeight") or 0
                        local newImgH = get(newDiag, "imageWorldHeight") or 0
                        local exX1 = get(existingDiag, "areaX1") or 0
                        local exY1 = get(existingDiag, "areaY1") or 0
                        local exX2 = get(existingDiag, "areaX2") or 0
                        local exY2 = get(existingDiag, "areaY2") or 0
                        local newX1 = get(newDiag, "areaX1") or 0
                        local newY1 = get(newDiag, "areaY1") or 0
                        local newX2 = get(newDiag, "areaX2") or 0
                        local newY2 = get(newDiag, "areaY2") or 0
                        printf("FLOOR_ALIGN_DIAG:: COMPARE existing vs new:")
                        printf("FLOOR_ALIGN_DIAG::   existing: pos=(%.4f, %.4f) area=(%.4f, %.4f)-(%.4f, %.4f) imgWorld=(%.4f x %.4f) tiles=(%.4f x %.4f) tileDim=(%.6f, %.6f) pivot=(%.6f, %.6f) px/tile=(%.4f x %.4f)",
                            get(existingDiag,"x") or 0, get(existingDiag,"y") or 0,
                            exX1, exY1, exX2, exY2, exImgW, exImgH, exTilesX, exTilesY,
                            get(existingDiag,"tileDimX") or 0, get(existingDiag,"tileDimY") or 0,
                            get(existingDiag,"mapPivotX") or 0, get(existingDiag,"mapPivotY") or 0,
                            get(existingDiag,"pixelsPerTileX") or 0, get(existingDiag,"pixelsPerTileY") or 0)
                        printf("FLOOR_ALIGN_DIAG::   new     : pos=(%.4f, %.4f) area=(%.4f, %.4f)-(%.4f, %.4f) imgWorld=(%.4f x %.4f) tiles=(%.4f x %.4f) tileDim=(%.6f, %.6f) pivot=(%.6f, %.6f) px/tile=(%.4f x %.4f)",
                            get(newDiag,"x") or 0, get(newDiag,"y") or 0,
                            newX1, newY1, newX2, newY2, newImgW, newImgH, newTilesX, newTilesY,
                            get(newDiag,"tileDimX") or 0, get(newDiag,"tileDimY") or 0,
                            get(newDiag,"mapPivotX") or 0, get(newDiag,"mapPivotY") or 0,
                            get(newDiag,"pixelsPerTileX") or 0, get(newDiag,"pixelsPerTileY") or 0)
                        printf("FLOOR_ALIGN_DIAG::   delta   : pos=(%.4f, %.4f) topLeft=(%.4f, %.4f) bottomRight=(%.4f, %.4f) imgWorld=(%.4f x %.4f) tilesAcross=%.6f tilesDown=%.6f",
                            (get(newDiag,"x") or 0) - (get(existingDiag,"x") or 0),
                            (get(newDiag,"y") or 0) - (get(existingDiag,"y") or 0),
                            newX1 - exX1, newY1 - exY1, newX2 - exX2, newY2 - exY2,
                            newImgW - exImgW, newImgH - exImgH,
                            newTilesX - exTilesX, newTilesY - exTilesY)
                    end
                end
            else
                printf("FLOOR_ALIGN_DIAG:: No pre-existing Map object to compare against.")
            end
        end
        printf("FLOOR_ALIGN_DIAG:: ===== End post-spawn calibration dump =====")

        -- Final state log.
        printf("FLOOR_IMPORT:: --- Final floor state ---")
        map = getMap()
        if map ~= nil then
            for i, floor in ipairs(map.floors) do
                local objCount = 0
                for _ in pairs(floor.objects) do objCount = objCount + 1 end
                printf("FLOOR_IMPORT::   [%d] id=%s desc='%s' parentFloor=%s objects=%d", i, floor.floorid, floor.description or "", json(floor.parentFloor), objCount)
            end
        end

        printf("FLOOR_IMPORT:: ===== END FinishFloorImport =====")
    end)
end
