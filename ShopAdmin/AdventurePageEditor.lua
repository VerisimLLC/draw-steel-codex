local mod = dmhub.GetModLoading()

--Shop admin editor for an adventure's store page -- item.adventurePage. The
--page itself, and what each part of the config means, is documented at the
--top of Codex Titlescreen/AdventurePage.lua. This editor sits in the item
--editor for Module items (under Module ID) and saves itself a moment after
--the last change, like the dice banner editor.

AdventurePageEditor = {}

local g_maxArt = 3
local g_maxCast = 5
--seconds after the last change before saving; a burst of edits becomes one
--upload (each upload also makes the shop admin rebuild its item list).
local g_saveDelay = 1.0
local g_extensions = {"jpeg", "jpg", "png", "webp"}
local g_videoExtensions = {"mp4", "webm"}

--The size Optimize scales each kind of image to: the recommended size each
--section's hint gives, about twice what the page draws, so art stays sharp on
--high-resolution screens. "cover" images fill the box (cropped: key art, map
--pans, round portraits, book cards at A4), so the shorter side decides;
--"contain" images are shown whole inside it (art), so the longer side does.
AdventurePageEditor.OptimizeTargets = {
    hero = {w = 2400, h = 1120, fit = "cover"},
    book = {w = 1240, h = 1754, fit = "cover"},
    map = {w = 2560, h = 1440, fit = "cover"},
    art = {w = 1920, h = 1080, fit = "contain"},
    cast = {w = 512, h = 512, fit = "cover"},
}
--An image is only replaced when that saves at least this share of its
--pixels; a smaller trim is not worth a lossy re-encode.
AdventurePageEditor.OptimizeMinSaving = 0.25

local function NewConfig()
    return {
        heroImage = "",
        tagline = "",
        tags = {},
        publisher = "MCDM",
        aboutTitle = "",
        about = "",
        media = {book = {cover = "", pages = {}}, maps = {}, art = {}},
        cast = {},
    }
end

--Fills in any missing parts, so the editor can index freely whatever shape a
--saved config comes back in.
local function Normalize(cfg)
    cfg.tags = cfg.tags or {}
    cfg.media = cfg.media or {}
    cfg.media.book = cfg.media.book or {}
    cfg.media.book.cover = cfg.media.book.cover or ""
    cfg.media.book.pages = cfg.media.book.pages or {}
    cfg.media.maps = cfg.media.maps or {}
    for _, map in ipairs(cfg.media.maps) do
        map.pins = map.pins or {}
    end
    cfg.media.art = cfg.media.art or {}
    cfg.cast = cfg.cast or {}
    return cfg
end

local function ReadConfig(item)
    local cfg = nil
    pcall(function() cfg = item.adventurePage end)
    if type(cfg) ~= "table" then
        return nil
    end
    return Normalize(cfg)
end

--Opens a file picker and uploads each chosen image to the Core asset store
--(the shop catalog is global, so its art must be too), calling done(guid)
--once per image as it finishes.
local function PickImages(args)
    dmhub.OpenFileDialog{
        id = args.id,
        extensions = g_extensions,
        multiFiles = args.multi == true,
        prompt = args.prompt,
        open = function(path)
            assets:UploadImageAsset{
                core = true,
                path = path,
                description = string.format("AdventurePage: %s", args.itemid),
                error = function(msg)
                    printf("AdventurePageEditor: upload failed: %s", tostring(msg))
                end,
                upload = function(guid)
                    if mod.unloaded then
                        return
                    end
                    args.done(guid)
                end,
            }
        end,
    }
end

--Shows imageid on a thumbnail panel cropped to fill w x h without stretching.
local function SetThumb(panel, imageid, w, h)
    if imageid == nil or imageid == "" then
        panel.bgimage = "panels/square.png"
        panel.selfStyle.bgcolor = "#2b2d31ff"
        panel.selfStyle.imageRect = {x1 = 0, y1 = 0, x2 = 1, y2 = 1}
        return
    end
    panel.bgimage = imageid
    panel.selfStyle.bgcolor = "#2b2d31ff"
    AdventurePage.ImageDimensions(imageid, function(dims)
        if mod.unloaded or not panel.valid or panel.bgimage ~= imageid then
            return
        end
        if dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
            return
        end
        local boxAspect = w / h
        local imageAspect = dims.width / dims.height
        if imageAspect > boxAspect then
            local f = boxAspect / imageAspect
            panel.selfStyle.imageRect = {x1 = (1 - f) * 0.5, x2 = (1 + f) * 0.5, y1 = 0, y2 = 1}
        else
            local f = imageAspect / boxAspect
            panel.selfStyle.imageRect = {x1 = 0, x2 = 1, y1 = (1 - f) * 0.5, y2 = (1 + f) * 0.5}
        end
        panel.selfStyle.bgcolor = "#ffffffff"
    end)
end

local function Thumb(w, h, extra)
    local args = {
        width = w,
        height = h,
        bgimage = "panels/square.png",
        bgcolor = "#2b2d31ff",
        borderWidth = 1,
        borderColor = "#55575dff",
        cornerRadius = 4,
    }
    for k, v in pairs(extra or {}) do
        args[k] = v
    end
    return gui.Panel(args)
end

local function SmallButton(text, width, click)
    return gui.Button{
        classes = {"sizeS"},
        width = width,
        text = text,
        hmargin = 4,
        click = click,
    }
end

--A small red cross in a thumbnail's top-right corner.
local function RemoveCross(click)
    return gui.Label{
        floating = true,
        halign = "right",
        valign = "top",
        width = 20,
        height = 20,
        text = "X",
        fontSize = 12,
        textAlignment = "center",
        color = "#ffffffff",
        bgimage = "panels/square.png",
        bgcolor = "#a03a2aee",
        cornerRadius = 10,
        hmargin = 2,
        vmargin = 2,
        click = click,
    }
end

local function Hint(text)
    return gui.Label{
        text = text,
        fontSize = 13,
        color = "#9c978eff",
        width = "auto",
        height = "auto",
        halign = "left",
        vmargin = 2,
    }
end

--The recommended image size for a slot, a touch brighter than other hints.
--Sizes are about twice what the page displays, so art stays sharp on
--high-resolution screens.
local function SizeHint(text)
    return gui.Label{
        text = "Recommended: " .. text,
        fontSize = 13,
        color = "#e6d3aaff",
        width = "auto",
        height = "auto",
        halign = "left",
        vmargin = 2,
    }
end

--Collapsible sub-section with a title, open by default.
local function Section(title, hint, children)
    local m_open = true
    local content = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        lmargin = 24,
        children = children,
    }
    local arrow = gui.ExpandoArrow{
        classes = {"expanded"},
        interactable = false,
        halign = "left",
        valign = "center",
    }
    return gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        vmargin = 4,
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = 30,
            halign = "left",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            click = function(element)
                m_open = not m_open
                content:SetClass("collapsed", not m_open)
                arrow:SetClass("expanded", m_open)
            end,
            arrow,
            gui.Label{
                text = title,
                fontSize = 20,
                fontWeight = "bold",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                hmargin = 8,
                interactable = false,
            },
            gui.Label{
                text = hint or "",
                fontSize = 13,
                color = "#9c978eff",
                width = "auto",
                height = "auto",
                valign = "center",
                interactable = false,
            },
        },
        content,
    }
end

--Builds the editor. It listens for the admin's `item` event (fired down the
--item editor whenever an item is selected or changed).
function AdventurePageEditor.Create()
    local m_item = nil
    --the item whose page is loaded into m_cfg (m_item is merely the selection).
    local m_loadedItem = nil
    local m_cfg = nil
    local m_selectedMap = 1

    local root

    --Coalesce edits into one upload shortly after the last change.
    local m_saveScheduled = false
    local function Save()
        if m_saveScheduled then
            return
        end
        m_saveScheduled = true
        dmhub.Schedule(g_saveDelay, function()
            m_saveScheduled = false
            if mod.unloaded or m_item == nil then
                return
            end
            local ok = pcall(function() m_item.adventurePage = m_cfg end)
            if not ok then
                printf("AdventurePageEditor: this build has no adventurePage field; the page was not saved (rebuild + restart required).")
                return
            end
            m_item:Upload()
        end)
    end

    --Re-sync every control from the working config. Rebuilding the whole
    --editor is costly (every thumbnail, list and the map preview), so edits
    --name the one section they touch and only that is refreshed.
    local m_sections = {}
    local function Refresh(sectionName)
        local scope = sectionName ~= nil and m_sections[sectionName] or root
        scope:FireEventTree("refreshPage", m_cfg)
        --every image section's edits change what Image sizes lists.
        if sectionName ~= nil and sectionName ~= "sizes" and m_sections.sizes ~= nil then
            m_sections.sizes:FireEventTree("refreshPage", m_cfg)
        end
    end

    --Change the config, save, and re-sync the named section (or everything).
    local function Edit(f, sectionName)
        if m_cfg == nil then
            return
        end
        f(m_cfg)
        Save()
        Refresh(sectionName)
    end

    ----------------------------------------------------------------------
    --Generic controls bound to the working config.
    ----------------------------------------------------------------------
    local function TextField(label, get, set, opts)
        opts = opts or {}
        return gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = label,
                valign = "top",
            },
            gui.Input{
                classes = {"formInput"},
                width = opts.width or 460,
                height = opts.height,
                multiline = opts.multiline,
                characterLimit = opts.limit or 200,
                placeholderText = opts.placeholder,
                refreshPage = function(element, cfg)
                    if cfg ~= nil then
                        element.text = get(cfg) or ""
                    end
                end,
                change = function(element)
                    if m_cfg == nil then
                        return
                    end
                    set(m_cfg, element.text)
                    Save()
                end,
            },
        }
    end

    --An image slot: thumbnail plus Upload / Clear.
    local function ImageSlot(w, h, uploadId, prompt, get, set, sectionName)
        local thumb = Thumb(w, h, {
            refreshPage = function(element, cfg)
                if cfg ~= nil then
                    SetThumb(element, get(cfg), w, h)
                end
            end,
        })
        return gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            rmargin = 16,
            thumb,
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                vmargin = 4,
                SmallButton("Upload...", 100, function()
                    if m_cfg == nil then
                        return
                    end
                    PickImages{id = uploadId, prompt = prompt, itemid = m_item.id, done = function(guid)
                        Edit(function(cfg) set(cfg, guid) end, sectionName)
                    end}
                end),
                SmallButton("Clear", 70, function()
                    Edit(function(cfg) set(cfg, "") end, sectionName)
                end),
            },
        }
    end

    ----------------------------------------------------------------------
    --Hero
    ----------------------------------------------------------------------
    local heroSection = Section("Hero", "key art, pitch and tags over the top of the page", {
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            ImageSlot(240, 104, "AdventureHero", "Choose the key art (2400 x 1120, no text on it)",
                function(cfg) return cfg.heroImage end,
                function(cfg, v) cfg.heroImage = v end, "hero"),
            gui.Panel{
                flow = "vertical",
                width = "auto",
                height = "auto",
                valign = "top",
                TextField("Tagline:", function(cfg) return cfg.tagline end,
                    function(cfg, v) cfg.tagline = v end, {placeholder = "One line pitch"}),
                TextField("Tags:", function(cfg) return table.concat(cfg.tags or {}, ", ") end,
                    function(cfg, v)
                        local tags = {}
                        for tag in string.gmatch(v, "[^,]+") do
                            tag = tag:match("^%s*(.-)%s*$")
                            if tag ~= "" then
                                tags[#tags + 1] = tag
                            end
                        end
                        cfg.tags = tags
                    end, {placeholder = "Levels 1-3, 4-6 heroes, About 3 sessions"}),
                TextField("Publisher:", function(cfg) return cfg.publisher end,
                    function(cfg, v) cfg.publisher = v end, {width = 200}),
            },
        },
        SizeHint("2400 x 1120 (about 2.1 : 1), no text on it. The top is what shows most, so keep faces in the upper two-thirds."),
        Hint("Without key art, the page uses the widest image in the item's gallery."),
    })

    ----------------------------------------------------------------------
    --About
    ----------------------------------------------------------------------
    local aboutSection = Section("About", "heading and description", {
        TextField("Heading:", function(cfg) return cfg.aboutTitle end,
            function(cfg, v) cfg.aboutTitle = v end, {placeholder = "About this adventure"}),
        TextField("Description:", function(cfg) return cfg.about end,
            function(cfg, v) cfg.about = v end,
            {multiline = true, height = 110, limit = 4000, placeholder = "Leave empty to use the item's details text"}),
    })

    ----------------------------------------------------------------------
    --What's inside: per-kind overrides for the counts the page reads from
    --the module (cfg.counts[key]). Empty means "use the module's number".
    ----------------------------------------------------------------------
    local g_countFields = {
        {key = "pdfs", label = "PDFs:"},
        {key = "maps", label = "Battle maps:"},
        {key = "monsters", label = "Monsters:"},
        {key = "characters", label = "NPCs:"},
        {key = "treasures", label = "Treasures:"},
        {key = "titles", label = "Titles:"},
    }
    local countFields = {}
    for _, field in ipairs(g_countFields) do
        countFields[#countFields + 1] = TextField(field.label,
            function(cfg)
                local n = cfg.counts ~= nil and cfg.counts[field.key] or nil
                return n ~= nil and tostring(n) or ""
            end,
            function(cfg, v)
                cfg.counts = cfg.counts or {}
                cfg.counts[field.key] = tonumber(v)
            end, {width = 80, limit = 4, placeholder = "auto"})
    end
    countFields[#countFields + 1] = Hint("Leave empty to count from the module. 1 PDF shows as \"Full PDF included\"; 0 hides a line.")
    local insideSection = Section("What's inside", "the counts in the buy box and captions", countFields)

    ----------------------------------------------------------------------
    --The book: seven named slots laid out like the fan on the store --
    --L3 L2 L1 Cover R1 R2 R3. Pages are stored as one list in fan order
    --(L1, R1, L2, R2, L3, R3); an empty slot is "" and is skipped on the store.
    ----------------------------------------------------------------------
    local g_bookSlotOrder = {
        {name = "L3", slot = 5}, {name = "L2", slot = 3}, {name = "L1", slot = 1},
        {name = "Cover", slot = "cover"},
        {name = "R1", slot = 2}, {name = "R2", slot = 4}, {name = "R3", slot = 6},
    }

    local function GetBookSlot(cfg, slot)
        if slot == "cover" then
            return cfg.media.book.cover or ""
        end
        return cfg.media.book.pages[slot] or ""
    end

    local function SetBookSlot(cfg, slot, imageid)
        if slot == "cover" then
            cfg.media.book.cover = imageid
            return
        end
        local pages = cfg.media.book.pages
        for i = #pages + 1, slot do
            pages[i] = ""
        end
        pages[slot] = imageid
        --trailing empty slots are dropped so the saved list stays short.
        while #pages > 0 and pages[#pages] == "" do
            pages[#pages] = nil
        end
    end

    --A click on a slot's X must not also count as a click on the slot (which
    --would open the file picker).
    local m_ignoreSlotClickUntil = 0

    --A filled slot takes its image's shape at the slot's height, as the fan on
    --the store does, so what you see here is what shows there; an empty slot
    --is A4. Same clamp as the store (AdventurePage.lua g_pageAspectMin/Max).
    local function SetBookThumb(panel, imageid, w, h)
        panel.selfStyle.width = w
        SetThumb(panel, imageid, w, h)
        if imageid == nil or imageid == "" then
            return
        end
        AdventurePage.ImageDimensions(imageid, function(dims)
            if mod.unloaded or not panel.valid or panel.bgimage ~= imageid then
                return
            end
            if dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
                return
            end
            local aspect = math.max(0.5, math.min(1.0, dims.width / dims.height))
            local fitW = math.floor(h * aspect)
            panel.selfStyle.width = fitW
            SetThumb(panel, imageid, fitW, h)
        end)
    end

    --One slot: an A4-shaped panel, blank with its name until filled. Click
    --to upload into it (or replace what is there); X clears it.
    local function BookSlot(name, slot, w, h)
        local emptyLabel = gui.Label{
            text = name,
            fontSize = 14,
            color = "#8f8a82ff",
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            interactable = false,
        }
        local cross = RemoveCross(function()
            m_ignoreSlotClickUntil = dmhub.Time() + 0.3
            Edit(function(c) SetBookSlot(c, slot, "") end, "book")
        end)
        local thumb = Thumb(w, h, {
            emptyLabel,
            cross,
            click = function()
                if m_cfg == nil or dmhub.Time() < m_ignoreSlotClickUntil then
                    return
                end
                PickImages{
                    id = "AdventureBook",
                    prompt = string.format("Choose the %s image (A4 portrait, 1240 x 1754)", name),
                    itemid = m_item.id,
                    done = function(guid)
                        Edit(function(c) SetBookSlot(c, slot, guid) end, "book")
                    end,
                }
            end,
            refreshPage = function(element, cfg)
                if cfg == nil then
                    return
                end
                local imageid = GetBookSlot(cfg, slot)
                local filled = imageid ~= ""
                SetBookThumb(element, imageid, w, h)
                emptyLabel:SetClass("collapsed", filled)
                cross:SetClass("collapsed", not filled)
            end,
        })
        return gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            valign = "bottom",
            hmargin = 5,
            thumb,
            gui.Label{
                text = name,
                fontSize = 12,
                color = "#9c978eff",
                width = "auto",
                height = "auto",
                halign = "center",
                tmargin = 4,
            },
        }
    end

    local bookSlots = {}
    for _, entry in ipairs(g_bookSlotOrder) do
        if entry.slot == "cover" then
            bookSlots[#bookSlots + 1] = BookSlot(entry.name, entry.slot, 80, 113)
        else
            bookSlots[#bookSlots + 1] = BookSlot(entry.name, entry.slot, 64, 90)
        end
    end

    --Pulling pages from a PDF on disk: the cover is page 1 and the six fan
    --pages are spread evenly through the body, skipping the front and back
    --matter. Each page is rendered and uploaded as an ordinary image, so the
    --PDF itself never leaves this machine.
    local g_pdfRenderWidth = 1240
    local g_pdfBodyStart = 0.12
    local g_pdfBodyEnd = 0.88

    local function PdfPagesToPull(npages)
        local result = {{slot = "cover", page = 0}}
        local nslots = AdventurePage.maxBookPages
        if npages <= 1 then
            return result
        end
        local first = math.max(1, math.floor(npages * g_pdfBodyStart))
        local last = math.max(first, math.min(npages - 1, math.floor(npages * g_pdfBodyEnd)))
        local used = {[0] = true}
        for slot = 1, nslots do
            local t = (slot - 1) / math.max(1, nslots - 1)
            local page = math.floor(first + (last - first) * t + 0.5)
            if not used[page] then
                used[page] = true
                result[#result + 1] = {slot = slot, page = page}
            end
        end
        return result
    end

    local pullPdfButton
    local m_pulling = false

    local function PullPagesFromPdf(path)
        local doc = dmhub.OpenLocalPDF(path)
        if doc == nil then
            gui.ModalMessage{title = "Could not open PDF", message = "That PDF could not be opened."}
            return
        end
        local item = m_item
        m_pulling = true
        pullPdfButton.text = "Reading PDF..."

        local function Finish(message)
            m_pulling = false
            if pullPdfButton.valid then
                pullPdfButton.text = "Pull pages from PDF"
            end
            if message ~= nil then
                gui.ModalMessage{title = "Pull pages from PDF", message = message}
            end
        end

        --The summary is read by a worker thread; it is nil until that finishes.
        local tries = 0
        local function WaitForSummary()
            if mod.unloaded then
                return
            end
            local summary = doc.summary
            if summary == nil then
                tries = tries + 1
                if tries > 150 then
                    Finish("The PDF could not be read.")
                    return
                end
                dmhub.Schedule(0.2, WaitForSummary)
                return
            end

            local pages = PdfPagesToPull(summary.npages)
            local height = math.floor(g_pdfRenderWidth * summary.pageHeight / summary.pageWidth)

            --One page at a time: render, upload, place, then the next.
            local index = 0
            local function Next()
                if mod.unloaded then
                    return
                end
                if m_item ~= item then
                    Finish(nil)
                    return
                end
                index = index + 1
                local entry = pages[index]
                if entry == nil then
                    Finish(nil)
                    return
                end
                if pullPdfButton.valid then
                    pullPdfButton.text = string.format("Page %d of %d...", index, #pages)
                end
                doc:RenderToData(entry.page, g_pdfRenderWidth, height, {x1 = 0, y1 = 0, x2 = 1, y2 = 1}, function(data)
                    if mod.unloaded then
                        return
                    end
                    if data == nil then
                        Finish(string.format("Page %d could not be rendered.", entry.page + 1))
                        return
                    end
                    assets:UploadImageAsset{
                        core = true,
                        data = data,
                        description = string.format("AdventurePage: %s pdf page %d", item.id, entry.page + 1),
                        error = function(msg)
                            Finish(string.format("Page %d failed to upload: %s", entry.page + 1, tostring(msg)))
                        end,
                        upload = function(guid)
                            if mod.unloaded or m_item ~= item then
                                return
                            end
                            Edit(function(c) SetBookSlot(c, entry.slot, guid) end, "book")
                            Next()
                        end,
                    }
                end)
            end
            Next()
        end
        WaitForSummary()
    end

    pullPdfButton = gui.Button{
        classes = {"sizeS"},
        width = 220,
        halign = "left",
        vmargin = 4,
        text = "Pull pages from PDF",
        click = function()
            if m_cfg == nil or m_pulling then
                return
            end
            local haveApi = false
            pcall(function() haveApi = dmhub.OpenLocalPDF ~= nil end)
            if not haveApi then
                gui.ModalMessage{title = "Needs a newer build", message = "Pulling pages from a PDF needs an engine build with dmhub.OpenLocalPDF."}
                return
            end
            dmhub.OpenFileDialog{
                id = "AdventureBookPdf",
                extensions = {"pdf"},
                prompt = "Choose the adventure's PDF",
                open = function(path)
                    PullPagesFromPdf(path)
                end,
            }
        end,
    }

    --A slider bound to one number on media.book. Dragging saves but does not
    --refresh the section (that would rebuild every thumbnail per tick).
    local function BookSlider(label, field, minValue, maxValue, default)
        local slider
        slider = gui.Slider{
            style = {height = 26, width = 240, fontSize = 14},
            sliderWidth = 180,
            labelWidth = 50,
            minValue = minValue,
            maxValue = maxValue,
            value = default,
            change = function(element)
                if m_cfg == nil then
                    return
                end
                m_cfg.media.book[field] = element.value
                Save()
            end,
            refreshPage = function(element, cfg)
                if cfg == nil then
                    return
                end
                local v = tonumber(cfg.media.book[field]) or default
                if element.value ~= v then
                    element.value = v
                end
            end,
        }
        return gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = label,
            },
            slider,
            SmallButton("Reset", 60, function()
                Edit(function(c) c.media.book[field] = nil end, "book")
            end),
        }
    end

    local bookSection = Section("The book", "the cover, with pages fanned out behind it", {
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            children = bookSlots,
        },
        BookSlider("Cover size:", "coverScale", AdventurePage.coverScaleMin, AdventurePage.coverScaleMax, 1),
        BookSlider("Cover height:", "coverY", AdventurePage.coverYMin, AdventurePage.coverYMax, 0),
        Hint("Size is relative to the pages (1 = same height). Height moves the cover up (-) or down (+)."),
        SizeHint("1240 x 1754, A4 portrait (1 : 1.414), for the cover and every page. Other shapes are cropped to A4."),
        Hint("Click a slot to upload into it, X to clear it. L1 and R1 sit closest to the cover; empty slots are left out on the store."),
        pullPdfButton,
        Hint("Fills every slot from a PDF on this computer: page 1 as the cover, six pages spread through the book. The PDF itself is not uploaded."),
    })

    ----------------------------------------------------------------------
    --Maps: each is a name and a looping video (a Map Preview Video from the
    --Export Map dialog, say), plus a PNG poster pulled from the video's first
    --frame for the tab thumbnail and to show while the video loads. Maps saved
    --before videos are still images with place names; the store still pans
    --those, and here they can only be renamed, replaced or removed.
    ----------------------------------------------------------------------
    local mapListW, mapListH = 128, 72
    local previewMaxW, previewMaxH = 520, 320

    --non-nil while a map video is being read or uploaded.
    local m_mapBusy = nil

    local mapStatus = gui.Label{
        classes = {"collapsed"},
        text = "",
        fontSize = 13,
        color = "#e6d3aaff",
        width = "auto",
        height = "auto",
        halign = "left",
        vmargin = 2,
    }

    local function SetMapStatus(text)
        m_mapBusy = text
        if mapStatus.valid then
            mapStatus.text = text or ""
            mapStatus:SetClass("collapsed", text == nil)
        end
    end

    local function MapVideo(map)
        if type(map.video) == "string" and map.video ~= "" then
            return map.video
        end
        return nil
    end

    --Opens a file picker for a map video, pulls a PNG poster from its first
    --frame, and uploads both to the Core asset store. done(fields) gets
    --{video, image, width, height, duration} once both are up.
    local function PickMapVideo(prompt, done)
        if m_cfg == nil or m_mapBusy ~= nil then
            return
        end
        local haveApi = false
        pcall(function() haveApi = assets.ExtractVideoFrame ~= nil end)
        if not haveApi then
            gui.ModalMessage{title = "Needs a newer build", message = "Map videos need an engine build with assets:ExtractVideoFrame."}
            return
        end
        local item = m_item
        dmhub.OpenFileDialog{
            id = "AdventureMapVideo",
            extensions = g_videoExtensions,
            prompt = prompt,
            open = function(path)
                local failed = false
                local function Fail(message)
                    if failed or mod.unloaded then
                        return
                    end
                    failed = true
                    SetMapStatus(nil)
                    gui.ModalMessage{title = "Map video", message = message}
                end

                SetMapStatus("Reading the video...")
                local target = AdventurePageEditor.OptimizeTargets.map
                assets:ExtractVideoFrame{
                    path = path,
                    maxWidth = target.w,
                    maxHeight = target.h,
                    error = function(msg)
                        Fail("That video could not be read: " .. tostring(msg))
                    end,
                    done = function(frame)
                        if mod.unloaded then
                            return
                        end
                        local fields = {width = frame.videoWidth, height = frame.videoHeight, duration = frame.duration}
                        local function Uploaded(key, guid)
                            if failed or mod.unloaded then
                                return
                            end
                            fields[key] = guid
                            if fields.video == nil or fields.image == nil then
                                return
                            end
                            SetMapStatus(nil)
                            if m_item == item then
                                done(fields)
                            end
                        end

                        SetMapStatus("Uploading the video...")
                        assets:UploadImageAsset{
                            core = true,
                            data = frame.data,
                            description = string.format("AdventurePage: %s map preview", item.id),
                            error = function(msg)
                                Fail("The preview image failed to upload: " .. tostring(msg))
                            end,
                            upload = function(guid)
                                Uploaded("image", guid)
                            end,
                        }
                        assets:UploadImageAsset{
                            core = true,
                            path = path,
                            description = string.format("AdventurePage: %s map video", item.id),
                            error = function(msg)
                                Fail("The video failed to upload: " .. tostring(msg))
                            end,
                            upload = function(guid)
                                Uploaded("video", guid)
                            end,
                        }
                    end,
                }
            end,
        }
    end

    local mapList = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        valign = "top",
        rmargin = 16,
        refreshPage = function(element, cfg)
            if cfg == nil then
                return
            end
            local children = {}
            for i, map in ipairs(cfg.media.maps) do
                local thumb = Thumb(mapListW, mapListH, {
                    bmargin = 8,
                    borderWidth = cond(i == m_selectedMap, 2, 1),
                    borderColor = cond(i == m_selectedMap, "#f6ddb6ff", "#55575dff"),
                    click = function()
                        m_selectedMap = i
                        Refresh("maps")
                    end,
                })
                SetThumb(thumb, map.image, mapListW, mapListH)
                children[#children + 1] = thumb
            end
            children[#children + 1] = Thumb(mapListW, mapListH, {
                borderColor = "#77736cff",
                bgcolor = "#ffffff08",
                gui.Label{
                    text = "+ Add map video",
                    fontSize = 12,
                    color = "#cfc9bdff",
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    interactable = false,
                },
                click = function()
                    PickMapVideo("Choose a map video (MP4 or WebM, 16 : 9)", function(fields)
                        Edit(function(c)
                            local map = {name = "", pins = {}}
                            for k, v in pairs(fields) do
                                map[k] = v
                            end
                            table.insert(c.media.maps, map)
                            m_selectedMap = #c.media.maps
                        end, "maps")
                    end)
                end,
            })
            element.children = children
        end,
    }

    --The selected map shown whole at its own aspect: its video playing on a
    --loop over the poster (which shows until the video starts), or the still
    --image of an older map. mapVideo has no placeholder bgimage: a video draws
    --nothing until its first frame, so the poster shows through meanwhile.
    local mapVideo = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "100%",
        interactable = false,
        bgcolor = "#ffffffff",
    }

    local mapPreview = gui.Panel{
        flow = "none",
        width = previewMaxW,
        height = previewMaxH,
        valign = "top",
        bgimage = "panels/square.png",
        bgcolor = "#2b2d31ff",
        mapVideo,
        gui.Panel{
            classes = {"collapsed"},
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            Hint("Add a map video to see it here."),
            refreshPage = function(element, cfg)
                element:SetClass("collapsed", cfg ~= nil and cfg.media.maps[m_selectedMap] ~= nil)
            end,
        },

        refreshPage = function(element, cfg)
            local map = cfg ~= nil and cfg.media.maps[m_selectedMap] or nil
            local video = map ~= nil and MapVideo(map) or nil
            mapVideo:SetClass("collapsed", video == nil)
            if video ~= nil then
                mapVideo.bgimage = video
            end
            if map == nil then
                element.bgimage = "panels/square.png"
                element.selfStyle.bgcolor = "#2b2d31ff"
                element.selfStyle.width = previewMaxW
                element.selfStyle.height = previewMaxH
                return
            end

            local function Fit(w, h)
                local scale = math.min(previewMaxW / w, previewMaxH / h)
                element.selfStyle.width = math.floor(w * scale)
                element.selfStyle.height = math.floor(h * scale)
                element.selfStyle.bgcolor = "#ffffffff"
            end

            local imageid = map.image
            element.bgimage = imageid
            element.selfStyle.imageRect = {x1 = 0, y1 = 0, x2 = 1, y2 = 1}
            if (tonumber(map.width) or 0) > 0 and (tonumber(map.height) or 0) > 0 then
                Fit(map.width, map.height)
                return
            end
            AdventurePage.ImageDimensions(imageid, function(dims)
                if mod.unloaded or not element.valid or element.bgimage ~= imageid then
                    return
                end
                if dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
                    return
                end
                Fit(dims.width, dims.height)
            end)
        end,
    }

    local mapDetails = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        valign = "top",
        lmargin = 16,
        refreshPage = function(element, cfg)
            local map = cfg ~= nil and cfg.media.maps[m_selectedMap] or nil
            element:SetClass("collapsed", map == nil)
            if map == nil then
                return
            end

            local about
            if MapVideo(map) == nil then
                about = "A still image, from before map videos: the store pans it with its place names. Replace it with a video."
            else
                about = string.format("%d x %d video", tonumber(map.width) or 0, tonumber(map.height) or 0)
                if (tonumber(map.duration) or 0) > 0 then
                    about = about .. string.format(", %d second loop", math.floor(map.duration + 0.5))
                end
            end

            element.children = {
                gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{classes = {"formLabel"}, text = "Map name:", valign = "top"},
                    gui.Input{
                        classes = {"formInput"},
                        width = 240,
                        characterLimit = 80,
                        text = map.name or "",
                        placeholderText = "Shown under the map",
                        change = function(input)
                            map.name = input.text
                            Save()
                        end,
                    },
                },
                gui.Label{
                    text = about,
                    fontSize = 13,
                    color = "#9c978eff",
                    width = 300,
                    height = "auto",
                    halign = "left",
                    vmargin = 2,
                },
                gui.Panel{
                    flow = "horizontal",
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    tmargin = 12,
                    SmallButton("Replace video...", 140, function()
                        PickMapVideo("Choose a new video for this map (MP4 or WebM, 16 : 9)", function(fields)
                            Edit(function()
                                for k, v in pairs(fields) do
                                    map[k] = v
                                end
                                --place names were for the still image.
                                map.pins = {}
                            end, "maps")
                        end)
                    end),
                    SmallButton("Remove map", 120, function()
                        Edit(function(c)
                            table.remove(c.media.maps, m_selectedMap)
                            m_selectedMap = math.max(1, math.min(m_selectedMap, #c.media.maps))
                        end, "maps")
                    end),
                },
            }
        end,
    }

    local mapsSection = Section("Maps", "each map's video plays on a loop; with several, the next fades in after it", {
        SizeHint("a looping MP4 or WebM, 16 : 9, 1920 x 1080 or more -- such as a Map Preview Video from the Export Map dialog."),
        Hint("The first frame is saved as a PNG preview, shown on the Maps tab and while the video loads."),
        mapStatus,
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            mapList,
            mapPreview,
            mapDetails,
        },
    })

    ----------------------------------------------------------------------
    --Art and cast: short lists of image + text rows.
    ----------------------------------------------------------------------
    local function ListEditor(args)
        return gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            halign = "left",
            refreshPage = function(element, cfg)
                if cfg == nil then
                    return
                end
                local list = args.list(cfg)
                local rows = {}
                for i, entry in ipairs(list) do
                    local thumb = Thumb(args.w, args.h, {valign = "top", rmargin = 12})
                    SetThumb(thumb, entry.image, args.w, args.h)
                    local fields = {}
                    for _, field in ipairs(args.fields) do
                        fields[#fields + 1] = gui.Panel{
                            classes = {"formPanel"},
                            gui.Label{classes = {"formLabel"}, text = field.label, valign = "top"},
                            gui.Input{
                                classes = {"formInput"},
                                width = 300,
                                characterLimit = 80,
                                text = entry[field.key] or "",
                                placeholderText = field.placeholder,
                                change = function(input)
                                    entry[field.key] = input.text
                                    Save()
                                end,
                            },
                        }
                    end
                    fields[#fields + 1] = gui.Panel{
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        SmallButton("Replace image...", 140, function()
                            PickImages{id = args.uploadId, prompt = args.prompt, itemid = m_item.id, done = function(guid)
                                Edit(function() entry.image = guid end, args.section)
                            end}
                        end),
                        SmallButton("Remove", 80, function()
                            Edit(function(c) table.remove(args.list(c), i) end, args.section)
                        end),
                    }
                    rows[#rows + 1] = gui.Panel{
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        vmargin = 6,
                        thumb,
                        gui.Panel{flow = "vertical", width = "auto", height = "auto", valign = "top", children = fields},
                    }
                end
                if #list < args.max then
                    rows[#rows + 1] = gui.Panel{
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        vmargin = 4,
                        SmallButton(args.addText, 180, function()
                            if m_cfg == nil then
                                return
                            end
                            PickImages{id = args.uploadId, prompt = args.prompt, itemid = m_item.id, done = function(guid)
                                Edit(function(c)
                                    local l = args.list(c)
                                    if #l < args.max then
                                        local entry = {image = guid}
                                        for _, field in ipairs(args.fields) do
                                            entry[field.key] = ""
                                        end
                                        table.insert(l, entry)
                                    end
                                end, args.section)
                            end}
                        end),
                    }
                end
                element.children = rows
            end,
        }
    end

    local artSection = Section("Art", string.format("up to %d pieces, each shown whole", g_maxArt), {
        SizeHint("1920 x 1080 (16 : 9). Other shapes are shown whole, with dark bars at the sides or top."),
        ListEditor{
            list = function(cfg) return cfg.media.art end,
            section = "art",
            max = g_maxArt,
            w = 160,
            h = 90,
            uploadId = "AdventureArt",
            prompt = "Choose art (1920 x 1080)",
            addText = "+ Add art...",
            fields = {
                {key = "caption", label = "Caption:", placeholder = "Shown under the art"},
                {key = "label", label = "Tab label:", placeholder = "Art"},
            },
        },
    })

    --The adventure's bestiary monsters, as cast entries. The module record
    --lists them by name only, so they are matched against this game's
    --bestiary: they show only where the adventure is installed.
    local function AdventureMonsters(moduleid, done)
        module.DownloadModuleInfo{
            moduleid = moduleid,
            failure = function()
                done({})
            end,
            success = function(info)
                local wanted = {}
                local summary = nil
                pcall(function() summary = info.contentSummary end)
                for _, entry in ipairs(summary or {}) do
                    --the Thorn Dragon is listed as a monster group, not a monster.
                    local kind = string.lower(tostring(entry.type or ""))
                    if kind == "monster" or kind == "object:monstergroup" then
                        for _, name in ipairs(entry.items or {}) do
                            wanted[name] = true
                        end
                    end
                end
                local members = {}
                for _, monster in pairs(assets.monsters) do
                    local name, tok = nil, nil
                    pcall(function() name = monster.name end)
                    pcall(function() tok = monster.info end)
                    if name ~= nil and wanted[name] and tok ~= nil then
                        local member = AdventurePage.CastFromToken(tok, name)
                        if member ~= nil then
                            members[#members + 1] = member
                        end
                    end
                end
                done(members)
            end,
        }
    end

    --Lists the adventure's own tokens and monsters (one per name) in a modal;
    --clicking one adds it to the cast, drawn as it looks in game in the ring.
    local function PickCastFromAdventure()
        if m_item == nil or m_cfg == nil or module.DownloadModuleSnapshot == nil then
            return
        end
        local moduleid = m_item.assetid
        local status = gui.Label{
            text = "Loading the adventure's tokens...",
            fontSize = 14,
            width = "auto",
            height = "auto",
            halign = "center",
            vmargin = 12,
        }
        local grid = gui.Panel{
            flow = "horizontal",
            wrap = true,
            width = 760,
            height = "auto",
            halign = "center",
            valign = "top",
        }
        gui.ShowModal(gui.Panel{
            flow = "vertical",
            width = 800,
            height = 600,
            halign = "center",
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = "#111113ff",
            borderWidth = 1,
            borderColor = "#f6ddb680",
            cornerRadius = 8,
            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = 44,
                gui.Label{
                    text = "Add a cast member from the adventure",
                    fontSize = 16,
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    hmargin = 16,
                },
                gui.Button{
                    classes = {"sizeS"},
                    text = "Close",
                    width = 90,
                    halign = "right",
                    valign = "center",
                    hmargin = 12,
                    click = function()
                        gui.CloseModal()
                    end,
                },
            },
            status,
            gui.Panel{
                width = 780,
                height = 520,
                halign = "center",
                vscroll = true,
                grid,
            },
        })

        module.DownloadModuleSnapshot{
            moduleid = moduleid,
            failure = function()
                if mod.unloaded or not status.valid then
                    return
                end
                status.text = "Could not load the adventure's tokens."
            end,
            success = function(snapshot)
                AdventureMonsters(moduleid, function(monsters)
                    if mod.unloaded or not grid.valid then
                        return
                    end
                    local seen = {}
                    local members = {}
                    local function Add(member)
                        if member ~= nil and not seen[member.name] then
                            seen[member.name] = true
                            members[#members + 1] = member
                        end
                    end
                    for _, tok in pairs(snapshot.characters or {}) do
                        Add(AdventurePage.CastFromToken(tok))
                    end
                    for _, member in ipairs(monsters) do
                        Add(member)
                    end
                    table.sort(members, function(a, b) return a.name < b.name end)
                    status.text = cond(#members == 0, "This adventure has no named tokens.",
                        "Click one to add it. Monsters show only if the adventure is installed in this game.")
                    local cells = {}
                    for _, member in ipairs(members) do
                        --drawn as it will look on the page, frame and all.
                        local thumb = AdventurePage.MakeCastPortrait(96, {interactable = false, tmargin = 4})
                        thumb:FireEvent("showMember", member)
                        cells[#cells + 1] = gui.Panel{
                            flow = "vertical",
                            width = 120,
                            height = "auto",
                            margin = 6,
                            bgimage = "panels/square.png",
                            bgcolor = "clear",
                            classes = {"hoverable"},
                            thumb,
                            gui.Label{
                                text = member.name,
                                fontSize = 13,
                                width = 120,
                                height = "auto",
                                textAlignment = "center",
                                tmargin = 4,
                                interactable = false,
                            },
                            click = function()
                                --the token's art id only resolves where the adventure's
                                --images are loaded; store the public blob id instead. The
                                --snapshot download registers those images in the background.
                                local image = AdventurePage.PortableImageId(member.image)
                                if image:sub(1, 4) ~= "md5:" then
                                    status.text = "That art is still loading. Try again in a moment."
                                    return
                                end
                                member.image = image
                                gui.CloseModal()
                                Edit(function(c)
                                    if #c.cast < g_maxCast then
                                        table.insert(c.cast, member)
                                    end
                                end, "cast")
                            end,
                        }
                    end
                    grid.children = cells
                end)
            end,
        }
    end

    ----------------------------------------------------------------------
    --Cast rows: a live preview drawn exactly like the store page. Drag it to
    --move the art; the slider zooms regular art or resizes popout art.
    --"Choose from gallery..." opens the normal token (Avatar) gallery.
    ----------------------------------------------------------------------
    local g_castPreview = 120

    --Regular art becomes placeable (zoom + center) the first time it is
    --adjusted, starting from wherever it currently sits.
    local function StartPlacement(entry, dims)
        if entry.popout or entry.zoom ~= nil or dims == nil
            or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
            return
        end
        local side = math.min(dims.width, dims.height)
        if entry.token and entry.rect ~= nil then
            local r = entry.rect
            entry.zoom = math.max(1, side / math.max(1, (r.x2 - r.x1) * dims.width))
            entry.center = {x = (r.x1 + r.x2) / 2, y = 1 - (r.y1 + r.y2) / 2}
        else
            --plain art was shown cover-cropped from the top.
            entry.zoom = 1
            entry.center = {x = 0.5, y = side / dims.height / 2}
        end
        entry.token = true
        entry.popout = false
    end

    local function CastRow(entry, index)
        local m_dims = nil
        local preview
        local dragging, anchor, start = false, nil, nil
        preview = AdventurePage.MakeCastPortrait(g_castPreview, {
            bgimage = "panels/square.png",
            bgcolor = "clear",
            valign = "top",
            rmargin = 16,
            vmargin = 8,
            press = function(element)
                StartPlacement(entry, m_dims)
                dragging = true
                anchor = element.mousePoint
                if entry.popout then
                    local o = entry.offset or {x = 0, y = 0}
                    start = {x = o.x or 0, y = o.y or 0}
                else
                    local c = entry.center or {x = 0.5, y = 0.5}
                    start = {x = c.x, y = c.y}
                end
                element.thinkTime = 0.02
            end,
            unpress = function(element)
                dragging = false
                element.thinkTime = nil
                Save()
            end,
            think = function(element)
                if not dragging then
                    return
                end
                local mp = element.mousePoint
                --(0, 0) means the mouse has left the panel.
                if mp.x == 0 and mp.y == 0 then
                    return
                end
                local dx, dy = mp.x - anchor.x, mp.y - anchor.y
                if entry.popout then
                    entry.offset = {x = start.x + dx, y = start.y - dy}
                else
                    --the art follows the mouse, so the window moves the other way.
                    local r = AdventurePage.CastRect(entry, m_dims)
                    entry.center = {
                        x = start.x - dx * (r.x2 - r.x1),
                        y = start.y + dy * (r.y2 - r.y1),
                    }
                end
                element:FireEvent("showMember", entry)
            end,
        })
        preview:FireEvent("showMember", entry)
        AdventurePage.ImageDimensions(entry.image, function(dims)
            m_dims = dims
        end)

        local slider = gui.Slider{
            style = {height = 26, width = 240, fontSize = 14},
            lmargin = 10,
            sliderWidth = 180,
            labelWidth = 50,
            minValue = cond(entry.popout, 0.5, 1),
            maxValue = cond(entry.popout, 3, 4),
            value = cond(entry.popout, 1 / (entry.popoutScale or 1), entry.zoom or 1),
            change = function(element)
                if entry.popout then
                    entry.popoutScale = 1 / math.max(0.1, element.value)
                else
                    StartPlacement(entry, m_dims)
                    entry.zoom = element.value
                end
                preview:FireEvent("showMember", entry)
            end,
            confirm = function(element)
                Save()
            end,
        }

        --The gallery is the standard IconEditor picker; a button opens it.
        local gallery = gui.IconEditor{
            library = "Avatar",
            restrictImageType = "Avatar",
            allowPaste = true,
            hideIcon = true,
            width = 1,
            height = 1,
            value = entry.image,
            change = function(element)
                local image = element.value
                if image == nil or image == "" then
                    return
                end
                Edit(function()
                    entry.image = image
                    entry.token = true
                    entry.popout = (assets.imagesByTypeTable.AvatarPopout or {})[image] ~= nil
                    entry.rect, entry.zoom, entry.center = nil, nil, nil
                    entry.offset, entry.popoutScale = nil, nil
                end, "cast")
            end,
        }

        local fields = {}
        for _, field in ipairs({
            {key = "name", label = "Name:", placeholder = "Captain Moon"},
            {key = "role", label = "Role:", placeholder = "Ally, Villain, Monster..."},
        }) do
            fields[#fields + 1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{classes = {"formLabel"}, text = field.label, valign = "top"},
                gui.Input{
                    classes = {"formInput"},
                    width = 300,
                    characterLimit = 80,
                    text = entry[field.key] or "",
                    placeholderText = field.placeholder,
                    change = function(input)
                        entry[field.key] = input.text
                        Save()
                    end,
                },
            }
        end
        fields[#fields + 1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{classes = {"formLabel"}, text = cond(entry.popout, "Size:", "Zoom:")},
            slider,
        }
        local buttons = {
            gallery,
            SmallButton("Choose from gallery...", 180, function()
                gallery:FireEvent("press")
            end),
            SmallButton("Upload...", 90, function()
                PickImages{id = "AdventureCast", prompt = "Choose a portrait", itemid = m_item.id, done = function(guid)
                    Edit(function()
                        entry.image = guid
                        entry.token, entry.popout = nil, nil
                        entry.rect, entry.zoom, entry.center = nil, nil, nil
                        entry.offset, entry.popoutScale = nil, nil
                    end, "cast")
                end}
            end),
            SmallButton("Reset placement", 140, function()
                Edit(function()
                    entry.zoom, entry.center, entry.offset = nil, nil, nil
                    if entry.popout then
                        entry.popoutScale = nil
                    end
                end, "cast")
            end),
            SmallButton("Remove", 80, function()
                Edit(function(c) table.remove(c.cast, index) end, "cast")
            end),
        }
        --The store page shows the cast in list order.
        if index > 1 then
            buttons[#buttons + 1] = SmallButton("Move to Top", 110, function()
                Edit(function(c)
                    table.insert(c.cast, 1, table.remove(c.cast, index))
                end, "cast")
            end)
        end
        fields[#fields + 1] = gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            children = buttons,
        }

        return gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            vmargin = 6,
            preview,
            gui.Panel{flow = "vertical", width = "auto", height = "auto", valign = "top", children = fields},
        }
    end

    local function CastEditor()
        return gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            halign = "left",
            refreshPage = function(element, cfg)
                if cfg == nil then
                    return
                end
                local rows = {}
                for i, entry in ipairs(cfg.cast) do
                    rows[#rows + 1] = CastRow(entry, i)
                end
                if #cfg.cast < g_maxCast then
                    rows[#rows + 1] = gui.Panel{
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        vmargin = 4,
                        SmallButton("+ Add cast member...", 180, function()
                            if m_cfg == nil then
                                return
                            end
                            PickImages{id = "AdventureCast", prompt = "Choose a portrait", itemid = m_item.id, done = function(guid)
                                Edit(function(c)
                                    if #c.cast < g_maxCast then
                                        table.insert(c.cast, {image = guid, name = "", role = ""})
                                    end
                                end, "cast")
                            end}
                        end),
                    }
                end
                element.children = rows
            end,
        }
    end

    local castSection = Section("Cast", string.format("up to %d, shown as round portraits", g_maxCast), {
        SizeHint("512 x 512 square, face near the top. Shown as a circle, cropped from the top of taller art."),
        Hint("Or pick a token from the adventure or the gallery. Drag a preview to move its art."),
        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "left",
            vmargin = 4,
            SmallButton("Pick from adventure...", 200, PickCastFromAdventure),
        },
        CastEditor(),
    })

    ----------------------------------------------------------------------
    --Image sizes: what each image on the page costs to load against what
    --the page needs, and an Optimize button that swaps oversized images for
    --scaled-down copies. Loading cost is set by pixels, not file size: a
    --1 MB WebP at 6000 x 3100 decodes to 74 MB.
    ----------------------------------------------------------------------

    --Every image slot on the page. get/set read and write the slot on a
    --config, so an optimized copy lands in the same slot even if the lists
    --were edited while it uploaded.
    local function ImageSlots(cfg)
        local slots = {}
        local function Add(kind, label, get, set)
            local id = get(cfg)
            if type(id) == "string" and id ~= "" then
                slots[#slots + 1] = {kind = kind, label = label, id = id, get = get, set = set}
            end
        end
        Add("hero", "Key art", function(c) return c.heroImage end, function(c, v) c.heroImage = v end)
        for _, entry in ipairs(g_bookSlotOrder) do
            local slot = entry.slot
            Add("book", cond(slot == "cover", "Book cover", "Book page " .. entry.name),
                function(c) return GetBookSlot(c, slot) end,
                function(c, v) SetBookSlot(c, slot, v) end)
        end
        for _, list in ipairs({
            {kind = "map", items = cfg.media.maps, path = function(c) return c.media.maps end, name = "name", fallback = "Map"},
            {kind = "art", items = cfg.media.art, path = function(c) return c.media.art end, name = "caption", fallback = "Art"},
            {kind = "cast", items = cfg.cast, path = function(c) return c.cast end, name = "name", fallback = "Cast"},
        }) do
            for i, item in ipairs(list.items) do
                local name = item[list.name]
                local label = cond(type(name) == "string" and name ~= "", name, string.format("%s %d", list.fallback, i))
                Add(list.kind, label,
                    function(c) local e = list.path(c)[i]; return e and e.image end,
                    function(c, v) local e = list.path(c)[i]; if e ~= nil then e.image = v end end)
            end
        end
        return slots
    end

    local g_optimizeSizes = AdventurePageEditor.OptimizeTargets

    --The size to scale an image of dims to, or nil if it is fine as it is.
    local function OptimizedSize(dims, kind)
        local target = g_optimizeSizes[kind]
        if target == nil or dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
            return nil
        end
        local sx, sy = target.w / dims.width, target.h / dims.height
        local s = cond(target.fit == "cover", math.max(sx, sy), math.min(sx, sy))
        if s * s > 1 - AdventurePageEditor.OptimizeMinSaving then
            return nil
        end
        --multiples of 4, so the engine can GPU-compress and disk-cache the result.
        local w = math.max(4, math.floor(dims.width * s / 4 + 0.5) * 4)
        local h = math.max(4, math.floor(dims.height * s / 4 + 0.5) * 4)
        return w, h
    end

    local function MegaBytes(w, h)
        return w * h * 4 / (1024 * 1024)
    end

    local m_sizeRows = {}
    local m_sizeGeneration = 0
    local m_optimizing = false
    local sizesSummary
    local optimizeButton

    local function UpdateSizesSummary()
        local count, pending, before, after, oversized = #m_sizeRows, 0, 0, 0, 0
        for _, row in ipairs(m_sizeRows) do
            if row.dims == nil then
                pending = pending + 1
            else
                local mb = MegaBytes(row.dims.width, row.dims.height)
                before = before + mb
                if row.targetW ~= nil then
                    oversized = oversized + 1
                    after = after + MegaBytes(row.targetW, row.targetH)
                else
                    after = after + mb
                end
            end
        end
        local text
        if count == 0 then
            text = "No images on the page yet."
        else
            text = string.format("%d images, about %d MB once loaded.", count, math.floor(before + 0.5))
            if oversized > 0 then
                text = text .. string.format(" Optimizing %d of them brings that to about %d MB.", oversized, math.floor(after + 0.5))
            else
                text = text .. " Every image is already a sensible size."
            end
            if pending > 0 then
                text = text .. string.format(" (%d still loading.)", pending)
            end
        end
        sizesSummary.text = text
        if not m_optimizing then
            optimizeButton:SetClass("collapsed", oversized == 0)
            optimizeButton.text = string.format("Optimize %d %s", oversized, cond(oversized == 1, "image", "images"))
        end
    end

    local function SizeRow(slot, generation)
        local row = {slot = slot, dims = nil, targetW = nil, targetH = nil}
        local now = gui.Label{fontSize = 13, width = 150, height = "auto", valign = "center", text = "loading..."}
        local target = gui.Label{fontSize = 13, width = 260, height = "auto", valign = "center", text = ""}
        local thumb = Thumb(56, 36, {valign = "center", rmargin = 10})
        SetThumb(thumb, slot.id, 56, 36)
        row.panel = gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            vmargin = 2,
            thumb,
            gui.Label{fontSize = 13, width = 200, height = "auto", valign = "center", text = slot.label},
            now,
            target,
        }
        AdventurePage.ImageDimensions(slot.id, function(dims)
            if mod.unloaded or generation ~= m_sizeGeneration or not now.valid then
                return
            end
            if dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
                now.text = "unknown size"
                return
            end
            row.dims = dims
            now.text = string.format("%d x %d", dims.width, dims.height)
            row.targetW, row.targetH = OptimizedSize(dims, slot.kind)
            if row.targetW ~= nil then
                target.text = string.format("Oversized: %d x %d is enough", row.targetW, row.targetH)
                target.selfStyle.color = "#e6d3aaff"
            else
                target.text = "OK"
                target.selfStyle.color = "#9c978eff"
            end
            UpdateSizesSummary()
        end)
        return row
    end

    --Scales each oversized image, uploads the copy to the Core asset store
    --and puts it in its slot, one at a time. The originals stay in the store.
    local function Optimize()
        if m_optimizing or m_item == nil then
            return
        end
        local haveApi = false
        pcall(function() haveApi = assets.ResizeCachedImage ~= nil end)
        if not haveApi then
            gui.ModalMessage{title = "Needs a newer build", message = "Optimizing images needs an engine build with assets:ResizeCachedImage."}
            return
        end
        local jobs = {}
        for _, row in ipairs(m_sizeRows) do
            if row.targetW ~= nil then
                jobs[#jobs + 1] = row
            end
        end
        if #jobs == 0 then
            return
        end

        local item = m_item
        local failures = {}
        m_optimizing = true
        local index = 0
        local function Finish()
            m_optimizing = false
            if #failures > 0 then
                gui.ModalMessage{title = "Optimize images", message = "Some images were not optimized:\n" .. table.concat(failures, "\n")}
            end
            if root.valid and m_cfg ~= nil then
                Refresh()
            end
        end
        local function Next()
            if mod.unloaded then
                return
            end
            if m_item ~= item then
                Finish()
                return
            end
            index = index + 1
            local row = jobs[index]
            if row == nil then
                Finish()
                return
            end
            if optimizeButton.valid then
                optimizeButton.text = string.format("Optimizing %d of %d...", index, #jobs)
            end
            local slot = row.slot
            local resized = assets:ResizeCachedImage(slot.id, row.targetW, row.targetH)
            if resized == nil then
                failures[#failures + 1] = string.format("%s: not downloaded on this machine yet, or could not be decoded.", slot.label)
                dmhub.Schedule(0.05, Next)
                return
            end
            assets:UploadImageAsset{
                core = true,
                data = resized.data,
                description = string.format("AdventurePage: %s optimized %s", item.id, slot.label),
                error = function(msg)
                    failures[#failures + 1] = string.format("%s: upload failed: %s", slot.label, tostring(msg))
                    dmhub.Schedule(0.05, Next)
                end,
                upload = function(guid)
                    if mod.unloaded then
                        return
                    end
                    --only if the slot still holds the image that was scaled.
                    if m_item == item and m_cfg ~= nil and slot.get(m_cfg) == slot.id then
                        slot.set(m_cfg, guid)
                        Save()
                    end
                    --a frame between images: each resize is a main-thread stall.
                    dmhub.Schedule(0.05, Next)
                end,
            }
        end
        Next()
    end

    sizesSummary = gui.Label{
        fontSize = 14,
        width = 900,
        height = "auto",
        halign = "left",
        vmargin = 4,
        text = "",
    }

    optimizeButton = gui.Button{
        classes = {"sizeS", "collapsed"},
        width = 220,
        halign = "left",
        vmargin = 4,
        text = "Optimize",
        click = function()
            if m_optimizing then
                return
            end
            DTConfirmationDialog.ShowModal(
                "Optimize images?",
                "Oversized images are replaced on this page with scaled-down copies, uploaded to the asset store. The originals stay in the asset store and in the module.",
                "Optimize",
                "Cancel",
                Optimize,
                function() end)
        end,
    }

    local sizesSection = Section("Image sizes", "what the page loads", {
        Hint("Load time and memory follow an image's pixel count, not its file size. Targets are the recommended sizes above."),
        sizesSummary,
        optimizeButton,
        gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            halign = "left",
            refreshPage = function(element, cfg)
                if m_optimizing then
                    return
                end
                m_sizeGeneration = m_sizeGeneration + 1
                m_sizeRows = {}
                local children = {}
                if cfg ~= nil then
                    for _, slot in ipairs(ImageSlots(cfg)) do
                        local row = SizeRow(slot, m_sizeGeneration)
                        m_sizeRows[#m_sizeRows + 1] = row
                        children[#children + 1] = row.panel
                    end
                end
                element.children = children
                UpdateSizesSummary()
            end,
        },
    })

    ----------------------------------------------------------------------
    --Preview: the real store page, in a modal.
    ----------------------------------------------------------------------
    local function ShowPreview()
        if m_item == nil or m_cfg == nil or ShowShopItemDetails == nil then
            return
        end
        --the page reads item.adventurePage, so push the working config first.
        pcall(function() m_item.adventurePage = m_cfg end)
        local item = m_item
        local details = ShowShopItemDetails{halign = "center", valign = "top"}
        details:FireEventTree("showProductDetails", item)
        details:FireEventTree("refreshItem", item)
        details:FireEventTree("refreshCart", {})
        gui.ShowModal(gui.Panel{
            flow = "vertical",
            width = 1240,
            height = 1000,
            halign = "center",
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = "#111113ff",
            borderWidth = 1,
            borderColor = "#f6ddb680",
            cornerRadius = 8,
            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = 44,
                gui.Label{
                    text = "Store page preview",
                    fontSize = 16,
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    hmargin = 16,
                },
                gui.Button{
                    classes = {"sizeS"},
                    text = "Close",
                    width = 90,
                    halign = "right",
                    valign = "center",
                    hmargin = 12,
                    click = function()
                        gui.CloseModal()
                    end,
                },
            },
            gui.Panel{
                width = 1200,
                height = 940,
                halign = "center",
                vscroll = true,
                details,
            },
        })
    end

    ----------------------------------------------------------------------

    m_sections = {
        hero = heroSection,
        book = bookSection,
        maps = mapsSection,
        art = artSection,
        cast = castSection,
        sizes = sizesSection,
    }

    local body = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        heroSection,
        aboutSection,
        insideSection,
        bookSection,
        mapsSection,
        artSection,
        castSection,
        sizesSection,
    }

    local enableCheck = gui.Check{
        text = "Use adventure page",
        tooltip = "Give this adventure the full store page. Turning it off deletes the page settings and the item goes back to the plain details layout.",
        change = function(element)
            if m_item == nil then
                return
            end
            if element.value then
                m_cfg = ReadConfig(m_item) or NewConfig()
                Save()
                Refresh()
                return
            end

            --Turning the page off deletes everything set up for it, so keep
            --the box ticked until that is confirmed.
            element.value = true
            DTConfirmationDialog.ShowModal(
                "Turn off the adventure page?",
                "This deletes all of this item's adventure page settings (art, maps, places, cast). The images stay in the asset store.",
                "Delete page",
                "Cancel",
                function()
                    m_cfg = nil
                    Save()
                    Refresh()
                end,
                function() end)
        end,
    }

    local previewButton = gui.Button{
        classes = {"sizeS"},
        text = "Preview page",
        width = 140,
        hmargin = 16,
        click = function()
            ShowPreview()
        end,
    }

    --Drafts the whole page from the module (see AdventurePage.AutoFill),
    --replacing what is there after a confirmation. Takes a few seconds while
    --the module's images are looked up.
    local fillButton
    fillButton = gui.Button{
        classes = {"sizeS"},
        text = "Fill from adventure",
        width = 170,
        click = function()
            if m_item == nil then
                return
            end
            local item = m_item
            local function Run()
                fillButton.text = "Filling..."
                AdventurePage.AutoFill(item, function(cfg, err)
                    if mod.unloaded or not fillButton.valid then
                        return
                    end
                    fillButton.text = "Fill from adventure"
                    if cfg == nil then
                        printf("AdventurePageEditor: %s", tostring(err))
                        return
                    end
                    if m_item ~= item then
                        return
                    end
                    m_cfg = Normalize(cfg)
                    m_selectedMap = 1
                    Save()
                    Refresh()
                end)
            end
            if m_cfg == nil then
                Run()
                return
            end
            DTConfirmationDialog.ShowModal(
                "Replace the adventure page?",
                "This replaces everything on the page with a fresh draft built from the module.",
                "Replace",
                "Cancel",
                Run,
                function() end)
        end,
    }

    root = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        vmargin = 8,

        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            gui.Label{
                text = "Adventure page",
                fontSize = 24,
                fontWeight = "bold",
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 24,
            },
            enableCheck,
            previewButton,
            fillButton,
        },
        body,

        refreshPage = function(element, cfg)
            enableCheck.value = cfg ~= nil
            body:SetClass("collapsed", cfg == nil)
            previewButton:SetClass("collapsed", cfg == nil)
        end,

        item = function(element, item)
            m_item = item
            element:SetClass("collapsed", item == nil or item.itemType ~= "Module")
            if item == nil or item.itemType ~= "Module" then
                --forget it, so switching this item to Module loads it fresh.
                m_loadedItem = nil
                return
            end
            local changed = m_loadedItem ~= item
            m_loadedItem = item
            --The admin fires `item` after every edit to the item (price, type,
            --...). Only re-read the saved page when a different item is picked:
            --re-reading on the same item would drop an edit still waiting in
            --the save delay. Nothing on the page changed either, so there is
            --nothing to redraw (the full rebuild is the editor's costliest step).
            if not changed then
                return
            end
            m_selectedMap = 1
            m_cfg = ReadConfig(item)
            Refresh()
        end,
    }

    return root
end
