local mod = dmhub.GetModLoading()

--The store page for an adventure (a Module shop item with an adventure page
--config). Replaces the generic details layout for those items with the
--storefront pattern: a full-bleed hero, one media viewer with a filmstrip,
--then a two-column body (about + cast on the left, the buy box on the right).
--See ADVENTURE_SHOP_BRIEF.md.
--
--Page config shape:
--  {
--      heroImage = "<image guid>",   --key art; defaults to the widest gallery image
--      tagline = "One line pitch.",
--      tags = {"Levels 1-3", "4-6 heroes"},
--      publisher = "MCDM",
--      aboutTitle = "A hunt through the snow",
--      about = "Longer description.",  --defaults to the item's details text
--      media = {
--          --tab 1: the cover with sample pages fanned out behind it.
--          book = {cover = "<guid>", pages = {"<guid>", ...}},
--          --tab 2: every map in turn. A map is a looping video plus a PNG
--          --poster (its first frame: the tab thumbnail, shown until the video
--          --plays); width/height/duration are the video's.
--          maps = {
--              {video = "<guid>", image = "<poster guid>", name = "Temple Olea",
--               width = 1920, height = 1080, duration = 24},
--          },
--          --Maps saved before videos have only an image, which pans slowly with
--          --place names over it; a pin's x/y are fractions of the image from its
--          --TOP-left: pins = {{label = "The ford", x = 0.4, y = 0.7}}.
--          --tabs 3-5: art, each shown whole.
--          art = { {image = "<guid>", caption = "The winter wood", label = "Art"} },
--      },
--      cast = { {image = "<guid>", name = "Captain Moon", role = "Ally"} },
--  }
--The config is stored on the shop item as item.adventurePage (authored in the
--shop admin, ShopAdmin/AdventurePageEditor.lua). AdventurePage.SetDevFixture
--holds sample configs in memory, used when an item has none saved, so the page
--can be reviewed without saving anything.

AdventurePage = {}

local g_devFixtures = {}

function AdventurePage.SetDevFixture(itemid, cfg)
    g_devFixtures[itemid] = cfg
end

--The page config for a shop item, or nil. The engine field is read through
--pcall: an unknown member on engine userdata raises on older engines.
function AdventurePage.Read(item)
    if item == nil or item.itemType ~= "Module" then
        return nil
    end
    local cfg = nil
    pcall(function() cfg = item.adventurePage end)
    if type(cfg) ~= "table" then
        cfg = g_devFixtures[item.id]
    end
    return cfg
end

function AdventurePage.Has(item)
    return AdventurePage.Read(item) ~= nil
end

--The book fan shows the cover plus at most this many sample pages, three each
--side, in fixed slots the editor names L1-L3 and R1-R3.
AdventurePage.maxBookPages = 6

--Image size lookups for any image id a page stores: asset guids, and the
--"md5:<blob>" ids Fill from adventure writes. Two engine details this covers:
--the size lookup wants a blob id WITHOUT the "md5:" prefix (bgimage wants it
--WITH), and a lookup gives up silently after ~1000 frames, which a large image
--on a slow connection can outlast -- so it is retried a few times.
--Calls callback(dims) at most once. Something must be showing the image (a
--panel's bgimage) for it to download; the lookup alone does not fetch it.
local g_dimsRetries = 4
local g_dimsRetrySeconds = 12

function AdventurePage.ImageDimensions(imageid, callback)
    if type(imageid) ~= "string" or imageid == "" then
        return
    end
    local lookup = imageid
    if lookup:sub(1, 4) == "md5:" then
        lookup = lookup:sub(5)
    end
    local answered = false
    local function Try(attempt)
        gui.GetImageDimensionsCallback(lookup, function(dims)
            if answered then
                return
            end
            answered = true
            callback(dims)
        end)
        dmhub.Schedule(g_dimsRetrySeconds, function()
            if mod.unloaded or answered or attempt >= g_dimsRetries then
                return
            end
            Try(attempt + 1)
        end)
    end
    Try(1)
end

--------------------------------------------------------------------------------
--Fill from adventure: builds a first-draft page config from the module
--itself, for the admin to review and adjust. Reads the module record
--(description, and the image assets it ships -- publishingProperties'
--included/published assets) and the module snapshot (its characters), none
--of which installs anything. Picks by shape and size:
--  key art   -- the largest wide image
--  art tabs  -- the next largest wide images
--  book      -- the shop item's portrait gallery image as the cover, with
--               the module's page-shaped (tall, ~0.7 aspect) images fanned
--               behind it
--  cast      -- named characters, one per portrait, off-token art preferred
--  text      -- the module description; tagline and tags picked out of it
--Adventure maps are usually built from placed objects rather than one image,
--so maps are left for the admin to add.
--------------------------------------------------------------------------------
local g_autoFillMinSide = 1500     --images smaller than this are tokens/icons
local g_autoFillWaitSeconds = 20   --give up on images that never resolve

local g_numberWords = {one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7, eight = 8, nine = 9, ten = 10}

local function WordNumber(word)
    if word == nil then
        return nil
    end
    return tonumber(word) or g_numberWords[string.lower(word)]
end

--Tags from the usual adventure blurb: "a quest for 2nd-level heroes",
--"one to two session", "up to six Victories". Anything not found is skipped.
local function TagsFromDetails(details)
    local tags = {}
    local level = details:match("(%d+)%a%a%-level")
    if level ~= nil then
        tags[#tags + 1] = "Level " .. level
    end
    local a, b = details:match("(%w+) to (%w+)[%s%-]+sessions?")
    if a == nil then
        a, b = details:match("(%w+) or (%w+)[%s%-]+sessions?")
    end
    if WordNumber(a) ~= nil and WordNumber(b) ~= nil then
        tags[#tags + 1] = string.format("%d-%d sessions", WordNumber(a), WordNumber(b))
    else
        local one = details:match("(%w+)[%s%-]+sessions?")
        if WordNumber(one) ~= nil then
            tags[#tags + 1] = string.format("%d %s", WordNumber(one), cond(WordNumber(one) == 1, "session", "sessions"))
        end
    end
    local victories = details:match("[Uu]p to (%w+) [Vv]ictories")
    if WordNumber(victories) ~= nil then
        tags[#tags + 1] = string.format("Up to %d Victories", WordNumber(victories))
    end
    return tags
end

--Sentences that describe the product rather than the story.
local g_blurbWords = {"level", "session", "intended", "director", "assumes", "players", "adventure for"}
local g_taglineMaxLength = 140

--A one-line pitch: the first short sentence that tells the story rather than
--the format, looking past the first paragraph (usually the level/format
--blurb) before falling back to it. Empty when nothing qualifies.
local function TaglineFromDetails(details)
    local paragraphs = {}
    for para in (details .. "\n\n"):gmatch("(.-)\r?\n%s*\r?\n") do
        para = para:match("^%s*(.-)%s*$")
        if para ~= "" then
            paragraphs[#paragraphs + 1] = para
        end
    end
    local order = {}
    for i = 2, #paragraphs do
        order[#order + 1] = paragraphs[i]
    end
    order[#order + 1] = paragraphs[1]

    for _, para in ipairs(order) do
        for sentence in (para .. " "):gmatch("(.-[%.!%?])%s") do
            sentence = sentence:match("^%s*(.-)%s*$")
            local lower = string.lower(sentence)
            local blurb = false
            for _, word in ipairs(g_blurbWords) do
                if lower:find(word, 1, true) then
                    blurb = true
                end
            end
            if not blurb and #sentence <= g_taglineMaxLength then
                return sentence
            end
        end
    end
    return ""
end

--Looks up the size of every id; calls done(list of {id, w, h}) once all have
--answered or the wait runs out. Ids that are not images never answer.
local function ResolveImages(ids, done)
    local found = {}
    local pending = #ids
    local finished = false
    local function Finish()
        if finished then
            return
        end
        finished = true
        done(found)
    end
    if pending == 0 then
        Finish()
        return
    end
    for _, id in ipairs(ids) do
        gui.GetImageDimensionsCallback(id, function(dims)
            if dims ~= nil and (dims.width or 0) > 0 and (dims.height or 0) > 0 then
                found[#found + 1] = {id = id, w = dims.width, h = dims.height}
            end
            pending = pending - 1
            if pending == 0 then
                Finish()
            end
        end)
    end
    dmhub.Schedule(g_autoFillWaitSeconds, function()
        if not mod.unloaded then
            Finish()
        end
    end)
end

--The module's image ids only resolve on a machine that has its snapshot, so a
--shopper who has not bought it could never see them. Every image asset is
--also a public, content-addressed blob, which any client loads through an
--"md5:<blob>" id with no asset record needed (as chat attachments do). Swap
--each asset id for that form; ids it cannot resolve are left as they are.
--The editor's cast picker uses it too.
function AdventurePage.PortableImageId(id)
    if type(id) ~= "string" or id == "" or id:sub(1, 4) == "md5:" then
        return id
    end
    local blob = nil
    pcall(function()
        local asset = assets.imagesTable[id]
        if asset ~= nil then
            blob = asset.imageid
        end
    end)
    if type(blob) == "string" and blob ~= "" then
        return "md5:" .. blob
    end
    return id
end
local PortableImageId = AdventurePage.PortableImageId

local function PortableConfig(cfg)
    cfg.heroImage = PortableImageId(cfg.heroImage)
    cfg.media.book.cover = PortableImageId(cfg.media.book.cover)
    for i, page in ipairs(cfg.media.book.pages) do
        cfg.media.book.pages[i] = PortableImageId(page)
    end
    for _, list in ipairs({cfg.media.maps, cfg.media.art, cfg.cast}) do
        for _, entry in ipairs(list) do
            entry.image = PortableImageId(entry.image)
        end
    end
    return cfg
end

--Builds the draft and calls callback(cfg), or callback(nil, errorMessage).
--A cast entry drawn from one of the adventure's tokens: the token art plus
--everything that decides how the token looks in game (its crop, or popout art
--and scale, and its frame and the frame's hue shift), so the page can draw it
--exactly as the token looks. Returns nil for a token with no name or only the
--default avatar. nameOverride names a bestiary monster's token, which carries
--no name of its own.
function AdventurePage.CastFromToken(tok, nameOverride)
    local name, portrait, rect, popout, popoutScale = nameOverride, nil, nil, false, 1
    local frame, frameHue = nil, 0
    if name == nil then
        pcall(function() name = tok.name end)
    end
    pcall(function() portrait = tok.portrait end)
    pcall(function() popout = tok.popoutPortrait == true end)
    pcall(function() popoutScale = tok.popoutScale or 1 end)
    pcall(function() frame = tok.portraitFrame end)
    pcall(function() frameHue = tok.portraitFrameHueShift or 0 end)
    pcall(function()
        local r = tok.portraitRect
        rect = {x1 = r.x1, y1 = r.y1, x2 = r.x2, y2 = r.y2}
    end)
    --"High Elf Quiver 3" and its siblings are one cast member.
    if type(name) == "string" then
        name = name:gsub("%s+%d+$", "")
    end
    if type(name) ~= "string" or name == "" or type(portrait) ~= "string"
        or portrait == "" or portrait:find("DEFAULT") then
        return nil
    end
    if type(frame) ~= "string" or frame == "" then
        frame = nil
    end
    return {image = portrait, name = name, role = "", token = true, rect = rect,
        popout = popout, popoutScale = popoutScale, frame = frame, frameHue = frameHue}
end

function AdventurePage.AutoFill(item, callback)
    local moduleid = item.assetid
    if item.itemType ~= "Module" or moduleid == nil or moduleid == "" then
        callback(nil, "This item is not linked to a module.")
        return
    end

    module.DownloadModuleInfo{
        moduleid = moduleid,
        failure = function(msg)
            callback(nil, "Could not read the module: " .. tostring(msg))
        end,
        success = function(info)
            local details, props = "", nil
            pcall(function() details = info.details or "" end)
            pcall(function() props = info.publishingProperties end)

            local idSet, ids = {}, {}
            for _, key in ipairs({"includedAssets", "publishedAssets"}) do
                if type(props) == "table" and type(props[key]) == "table" then
                    for id, _ in pairs(props[key]) do
                        if not idSet[id] then
                            idSet[id] = true
                            ids[#ids + 1] = id
                        end
                    end
                end
            end

            local cfg = {
                heroImage = "",
                tagline = TaglineFromDetails(details),
                tags = TagsFromDetails(details),
                publisher = "MCDM",
                aboutTitle = "",
                about = details,
                media = {book = {cover = "", pages = {}}, maps = {}, art = {}},
                cast = {},
            }

            local function FillImages(nextStep)
                ResolveImages(ids, function(images)
                    local wide, tall = {}, {}
                    for _, image in ipairs(images) do
                        local aspect = image.w / image.h
                        if math.max(image.w, image.h) >= g_autoFillMinSide then
                            if aspect >= 1.3 then
                                wide[#wide + 1] = image
                            elseif aspect >= 0.6 and aspect <= 0.8 then
                                tall[#tall + 1] = image
                            end
                        end
                    end
                    --largest first; ties by id so the result is repeatable.
                    local function Bigger(a, b)
                        if a.w * a.h ~= b.w * b.h then
                            return a.w * a.h > b.w * b.h
                        end
                        return a.id < b.id
                    end
                    table.sort(wide, Bigger)
                    table.sort(tall, Bigger)

                    if wide[1] ~= nil then
                        cfg.heroImage = wide[1].id
                    end
                    for i = 2, math.min(#wide, 4) do
                        cfg.media.art[#cfg.media.art + 1] = {image = wide[i].id, caption = "", label = "Art"}
                    end
                    --a single page-shaped image is usually another copy of the
                    --cover; fanning needs at least two real pages.
                    if #tall >= 2 then
                        for i = 1, math.min(#tall, AdventurePage.maxBookPages) do
                            cfg.media.book.pages[#cfg.media.book.pages + 1] = tall[i].id
                        end
                    end

                    --the cover: the shop item's own portrait-shaped image.
                    local gallery = item.images or {}
                    local candidates = #gallery
                    if candidates == 0 then
                        nextStep()
                        return
                    end
                    for _, imageid in ipairs(gallery) do
                        AdventurePage.ImageDimensions(imageid, function(dims)
                            if cfg.media.book.cover == "" and dims ~= nil and (dims.height or 0) > 0 and dims.width / dims.height < 1 then
                                cfg.media.book.cover = imageid
                            end
                            candidates = candidates - 1
                            if candidates == 0 then
                                nextStep()
                            end
                        end)
                    end
                end)
            end

            local function FillCast(nextStep)
                if module.DownloadModuleSnapshot == nil then
                    nextStep()
                    return
                end
                module.DownloadModuleSnapshot{
                    moduleid = moduleid,
                    failure = function()
                        nextStep()
                    end,
                    success = function(snapshot)
                        local seen = {}
                        local members = {}
                        for _, tok in pairs(snapshot.characters or {}) do
                            local member = AdventurePage.CastFromToken(tok)
                            if member ~= nil and not seen[member.name] and not seen[member.image] then
                                seen[member.name] = true
                                seen[member.image] = true
                                members[#members + 1] = member
                            end
                        end
                        table.sort(members, function(a, b) return a.name < b.name end)
                        for i = 1, math.min(#members, 5) do
                            cfg.cast[#cfg.cast + 1] = members[i]
                        end
                        nextStep()
                    end,
                }
            end

            --The snapshot goes first: besides the cast, downloading it is what
            --makes the module's own images resolvable on this machine.
            FillCast(function()
                FillImages(function()
                    if not mod.unloaded then
                        callback(PortableConfig(cfg))
                    end
                end)
            end)
        end,
    }
end

--Palette and type. Gold is the shop's own accent (its checkout button).
local g_accent = "srgb:#f6ddb6"
local g_textStrong = "#f3ecdfff"
local g_textBody = "#d9d2c5ff"
local g_textMuted = "#9a958cff"
local g_pageBg = "#1c1c1eff"
local g_serif = "Berling"

local function ReduceMotion()
    local access = nil
    pcall(function() access = ThemeEngine.GetAccessibility() end)
    return access ~= nil and access.reduceMotion == true
end

local function PriceText(item)
    if item.price <= 0 then
        return "Free"
    end
    return string.format("$%d.%02d", math.tointeger(math.floor(item.price / 100)), math.tointeger(item.price % 100))
end

--The image window that COVERS a box of boxW x boxH, zoomed in by `zoom`
--(1 = plain cover) and positioned by u/v (0..1 across the spare travel).
--The window's aspect always equals the box's, so art is never stretched.
--Returns the imageRect (engine y is bottom-up) and the window's top-left and
--size as top-down fractions of the image, for placing things on the art.
local function CoverWindow(boxW, boxH, imageW, imageH, zoom, u, v)
    local boxAspect = boxW / boxH
    local imageAspect = imageW / imageH
    local wFrac, hFrac
    if imageAspect > boxAspect then
        hFrac = 1
        wFrac = boxAspect / imageAspect
    else
        wFrac = 1
        hFrac = imageAspect / boxAspect
    end
    wFrac = wFrac / zoom
    hFrac = hFrac / zoom
    local left = (1 - wFrac) * u
    local top = (1 - hFrac) * v
    return {x1 = left, x2 = left + wFrac, y1 = 1 - top - hFrac, y2 = 1 - top}, left, top, wFrac, hFrac
end

--Shows `imageid` on `element` cover-cropped to boxW x boxH once its size is
--known; v = 0 keeps the top of the art (faces), 0.5 centres it.
local function ShowCovered(element, imageid, boxW, boxH, v)
    element.bgimage = imageid
    AdventurePage.ImageDimensions(imageid, function(dims)
        if mod.unloaded or not element.valid or element.bgimage ~= imageid then
            return
        end
        if dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
            return
        end
        local rect = CoverWindow(boxW, boxH, dims.width, dims.height, 1, 0.5, v or 0.5)
        element.selfStyle.imageRect = rect
        element.selfStyle.bgcolor = "#ffffffff"
    end)
end

--Add to Cart / Remove from Cart / Add as Gift, in the shop's gold. Reacts to
--the same refreshItem / refreshCart events the shop fires down the details
--page, and hands presses up with the same addToCart / removeFromCart events.
local function MakeBuyButton(width, showPrice)
    return gui.Label{
        classes = {"itemButton", "checkoutButton", "collapsedWhenInventory", "collapseOnGift", "collapseOnNoCommerce"},
        width = width,
        height = 44,
        fontSize = 15,
        fontWeight = "semibold",
        --dark on the gold fill; the shop style leaves it too faint to read.
        color = "#1c1c1eff",
        vmargin = 0,
        data = {item = nil, inCart = false},

        refreshItem = function(element, item)
            element.data.item = item
        end,

        refreshCart = function(element, shoppingCart)
            local item = element.data.item
            if item == nil then
                return
            end
            local inCart = shoppingCart[item.id] == true
            element.data.inCart = inCart
            if inCart then
                element.text = "Remove from Cart"
            elseif shop:ItemInInventory(item.id) then
                element.text = cond(showPrice, "Add as Gift - " .. PriceText(item), "Add as Gift")
            else
                element.text = cond(showPrice, "Add to Cart - " .. PriceText(item), "Add to Cart")
            end
        end,

        press = function(element)
            local item = element.data.item
            if item == nil then
                return
            end
            if element.data.inCart then
                element:FireEventOnParents("removeFromCart", item)
            else
                element:FireEventOnParents("addToCart", item)
                analytics.Event{type = "shopAddCart", itemid = item.id}
            end
        end,
    }
end

--The default key art: the widest gallery image, since hero art is landscape.
local function PickHeroImage(item, cfg, callback)
    if type(cfg.heroImage) == "string" and cfg.heroImage ~= "" then
        callback(cfg.heroImage)
        return
    end
    local images = item.images or {}
    local best, bestAspect, pending = images[1], 0, #images
    if pending == 0 then
        callback(nil)
        return
    end
    for _, imageid in ipairs(images) do
        AdventurePage.ImageDimensions(imageid, function(dims)
            if dims ~= nil and (dims.height or 0) > 0 and dims.width / dims.height > bestAspect then
                best = imageid
                bestAspect = dims.width / dims.height
            end
            pending = pending - 1
            if pending == 0 then
                callback(best)
            end
        end)
    end
end

--The rule under the hero title, after the dividers on the book covers: a thin
--line with a diamond at its left end.
local g_ruleWidth = 520
local g_ruleDiamond = 10

local function MakeTitleRule()
    return gui.Panel{
        flow = "none",
        width = g_ruleWidth,
        height = 16,
        tmargin = 10,
        --sits a little left of the title, like the cover rules overhang their text.
        x = -10,
        interactable = false,

        --starts under the diamond's centre so the two read as one piece.
        gui.Panel{
            floating = true,
            halign = "left",
            valign = "center",
            x = g_ruleDiamond / 2,
            width = g_ruleWidth - g_ruleDiamond / 2,
            height = 2,
            bgimage = "panels/square.png",
            bgcolor = g_textBody,
            --solid from the diamond, fading out over the right-hand stretch.
            gradient = gui.Gradient{
                point_a = {x = 0, y = 0.5},
                point_b = {x = 1, y = 0.5},
                stops = {
                    {position = 0, color = core.Color{r = 1, g = 1, b = 1, a = 1}},
                    {position = 0.55, color = core.Color{r = 1, g = 1, b = 1, a = 1}},
                    {position = 1, color = core.Color{r = 1, g = 1, b = 1, a = 0}},
                },
            },
        },

        gui.Panel{
            floating = true,
            halign = "left",
            valign = "center",
            width = g_ruleDiamond,
            height = g_ruleDiamond,
            rotate = 45,
            bgimage = "panels/square.png",
            bgcolor = g_textStrong,
        },
    }
end

--------------------------------------------------------------------------------
--Hero: full-bleed key art (still), a left-hand scrim, and the
--title, pitch, tags and buy button over it.
--------------------------------------------------------------------------------
local function MakeHero(width, height)
    --A still image, cover-cropped to the strip. v keeps the upper part of the
    --art: key art is usually taller than this strip, and faces sit high.
    local art = gui.Panel{
        floating = true,
        width = width,
        height = height,
        bgimage = "panels/square.png",
        bgcolor = "#ffffff00",
        interactable = false,

        showArt = function(element, imageid)
            element.selfStyle.bgcolor = "#ffffff00"
            if imageid == nil then
                return
            end
            element.bgimage = imageid
            AdventurePage.ImageDimensions(imageid, function(dims)
                if mod.unloaded or not element.valid or element.bgimage ~= imageid then
                    return
                end
                if dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
                    return
                end
                element.selfStyle.imageRect = CoverWindow(width, height, dims.width, dims.height, 1, 0.5, 0.25)
                element.selfStyle.bgcolor = "#ffffffff"
            end)
        end,
    }

    --Dark from the left edge so the copy always reads, clear by the right
    --third so the art carries the page. bgcolor gives the hue, the gradient
    --the alpha.
    local sideScrim = gui.Panel{
        floating = true,
        width = width,
        height = height,
        interactable = false,
        bgimage = "panels/square.png",
        bgcolor = g_pageBg,
        gradient = gui.Gradient{
            point_a = {x = 0, y = 0.5},
            point_b = {x = 1, y = 0.5},
            stops = {
                {position = 0, color = core.Color{r = 1, g = 1, b = 1, a = 0.97}},
                {position = 0.35, color = core.Color{r = 1, g = 1, b = 1, a = 0.88}},
                {position = 0.6, color = core.Color{r = 1, g = 1, b = 1, a = 0.35}},
                {position = 0.8, color = core.Color{r = 1, g = 1, b = 1, a = 0}},
            },
        },
    }

    --Melts the hero's bottom edge into the page instead of a hard line.
    --Gradient position 0 is the BOTTOM of the panel.
    local bottomScrim = gui.Panel{
        floating = true,
        width = width,
        height = math.floor(height * 0.35),
        valign = "bottom",
        interactable = false,
        bgimage = "panels/square.png",
        bgcolor = g_pageBg,
        gradient = gui.Gradient{
            point_a = {x = 0.5, y = 0},
            point_b = {x = 0.5, y = 1},
            stops = {
                {position = 0, color = core.Color{r = 1, g = 1, b = 1, a = 1}},
                {position = 1, color = core.Color{r = 1, g = 1, b = 1, a = 0}},
            },
        },
    }

    --the MCDM display face, as on the book covers.
    local title = gui.Label{
        fontFace = "display",
        fontSize = 56,
        --nudged down toward the rule; a pure offset, so nothing else moves.
        y = 8,
        color = g_textStrong,
        width = 560,
        height = "auto",
        textAlignment = "left",
    }

    local tagline = gui.Label{
        fontSize = 18,
        fontWeight = "light",
        color = g_textBody,
        width = 520,
        height = "auto",
        textAlignment = "left",
        tmargin = 8,
    }

    local tagsRow = gui.Panel{
        flow = "horizontal",
        width = 560,
        height = "auto",
        tmargin = 18,
    }

    local publisher = gui.Label{
        fontSize = 14,
        color = g_textMuted,
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 18,
    }

    return gui.Panel{
        width = width,
        height = height,
        flow = "none",
        clip = true,
        bgimage = "panels/square.png",
        bgcolor = g_pageBg,

        art,
        sideScrim,
        bottomScrim,

        gui.Panel{
            floating = true,
            flow = "vertical",
            width = 600,
            height = "auto",
            halign = "left",
            valign = "bottom",
            x = 56,
            y = -52,

            title,
            MakeTitleRule(),
            tagline,
            tagsRow,
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                tmargin = 26,
                MakeBuyButton(280, true),
                publisher,
            },
        },

        showPage = function(element, item, cfg)
            title.text = item.name or ""
            tagline.text = cfg.tagline or ""
            tagline:SetClass("collapsed", (cfg.tagline or "") == "")
            publisher.text = cond((cfg.publisher or "") ~= "", "By " .. (cfg.publisher or ""), "")

            local chips = {}
            for i, tag in ipairs(cfg.tags or {}) do
                chips[#chips + 1] = gui.Label{
                    text = tag,
                    fontSize = 13,
                    color = g_textBody,
                    width = "auto",
                    height = 28,
                    hpad = 14,
                    borderBox = true,
                    textAlignment = "center",
                    lmargin = cond(i == 1, 0, 8),
                    bgimage = "panels/square.png",
                    bgcolor = "#00000059",
                    borderWidth = 1,
                    borderColor = "#ffffff38",
                    cornerRadius = 14,
                }
            end
            tagsRow.children = chips
            tagsRow:SetClass("collapsed", #chips == 0)

            PickHeroImage(item, cfg, function(imageid)
                if mod.unloaded or not art.valid then
                    return
                end
                art:FireEvent("showArt", imageid)
            end)
        end,
    }
end

--------------------------------------------------------------------------------
--Content counts: the module's contentSummary, fetched once per module with
--module.DownloadModuleInfo (the module record only -- nothing is downloaded
--or installed). Shared by the media captions and the buy box.
--------------------------------------------------------------------------------

--Counts by module id: {lowercased summary type = item count} once fetched,
--false while a fetch is in flight. A failed fetch clears the entry so the
--next open retries.
local g_countsCache = {}
local g_countsWaiting = {}

--Calls callback(counts) once the module's counts are known. Callers check
--their own panel is still valid inside the callback.
local function FetchCounts(moduleid, callback)
    if moduleid == nil or moduleid == "" or module.DownloadModuleInfo == nil then
        return
    end
    local cached = g_countsCache[moduleid]
    if type(cached) == "table" then
        callback(cached)
        return
    end
    g_countsWaiting[moduleid] = g_countsWaiting[moduleid] or {}
    table.insert(g_countsWaiting[moduleid], callback)
    if cached == false then
        return
    end
    g_countsCache[moduleid] = false
    module.DownloadModuleInfo{
        moduleid = moduleid,
        success = function(info)
            local summary = nil
            pcall(function() summary = info.contentSummary end)
            local counts = {}
            for _, entry in ipairs(summary or {}) do
                local kind = string.lower(tostring(entry.type or ""))
                local n = 0
                for _ in ipairs(entry.items or {}) do
                    n = n + 1
                end
                counts[kind] = (counts[kind] or 0) + n
            end
            g_countsCache[moduleid] = counts
            local waiting = g_countsWaiting[moduleid] or {}
            g_countsWaiting[moduleid] = nil
            if mod.unloaded then
                return
            end
            for _, f in ipairs(waiting) do
                f(counts)
            end
        end,
        failure = function(msg)
            g_countsCache[moduleid] = nil
            g_countsWaiting[moduleid] = nil
        end,
    }
end

local function CountOf(counts, types)
    local total = 0
    for _, kind in ipairs(types) do
        total = total + (counts[kind] or 0)
    end
    return total
end

local function Plural(n, one, many)
    return string.format("%d %s", n, cond(n == 1, one, many))
end

local g_mapTypes = {"map", "maps"}
local g_pdfTypes = {"pdfdocument"}

--The kinds of content the page counts, keyed as cfg.counts stores them.
AdventurePage.countTypes = {
    maps = g_mapTypes,
    monsters = {"monster"},
    characters = {"character"},
    treasures = {"object:tbl_gear"},
    titles = {"object:titles"},
    pdfs = g_pdfTypes,
}

--The module's counts with the editor's cfg.counts overrides applied. An
--override replaces the module's number for that kind; a missing one keeps it.
local function ApplyCountOverrides(counts, cfg)
    local overrides = type(cfg) == "table" and cfg.counts or nil
    if type(overrides) ~= "table" then
        return counts
    end
    local result = {}
    for kind, n in pairs(counts) do
        result[kind] = n
    end
    for key, types in pairs(AdventurePage.countTypes) do
        local n = tonumber(overrides[key])
        if n ~= nil then
            for _, kind in ipairs(types) do
                result[kind] = nil
            end
            result[types[1]] = math.max(0, math.floor(n))
        end
    end
    return result
end

--------------------------------------------------------------------------------
--Media viewer: a stage plus a row of labelled tabs, one per slide:
--  the book -- the cover, with pages fanned out behind it ("1 PDF included")
--  maps     -- a slow pan over each map in turn, crossfading between them
--  art      -- up to three pieces, each shown whole (letterboxed, never cropped)
--------------------------------------------------------------------------------
local g_panPeriod = 40          --seconds for one sweep across a map and back
local g_panVerticalRatio = 0.63 --vertical drift rate, so the path wanders
local g_panZoom = 1.3           --past a plain cover fit, so there is room to drift
local g_mapHoldTime = 9         --seconds each map shows before the next fades in
local g_mapFadeTime = 1.5
local g_pinInset = 0.1          --pins show only inside this margin of the frame
local g_maxArt = 3

--The caption band along the stage's bottom: a scrim that melts into the art,
--a headline ("3 maps included") and an optional smaller line under it.
--plain = true drops the scrim, for a slide with no art behind its caption.
local function MakeCaption(width, stageH, plain)
    local headline = gui.Label{
        fontFace = g_serif,
        fontSize = 24,
        color = g_textStrong,
        width = "auto",
        height = "auto",
        halign = "center",
    }
    local subline = gui.Label{
        fontSize = 14,
        color = g_textBody,
        width = "auto",
        height = "auto",
        halign = "center",
        tmargin = 2,
    }
    return gui.Panel{
        floating = true,
        flow = "vertical",
        width = width,
        height = 170,
        valign = "bottom",
        interactable = false,
        bgimage = "panels/square.png",
        bgcolor = cond(plain, "#00000000", "#000000ff"),
        --position 0 is the BOTTOM of the panel.
        gradient = cond(plain, nil, gui.Gradient{
            point_a = {x = 0.5, y = 0},
            point_b = {x = 0.5, y = 1},
            stops = {
                {position = 0, color = core.Color{r = 1, g = 1, b = 1, a = 0.92}},
                {position = 0.45, color = core.Color{r = 1, g = 1, b = 1, a = 0.72}},
                {position = 1, color = core.Color{r = 1, g = 1, b = 1, a = 0}},
            },
        }),
        gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "bottom",
            bmargin = cond(plain, 0, 22),
            headline,
            subline,
        },
        setCaption = function(element, main, sub)
            headline.text = main or ""
            subline.text = sub or ""
            subline:SetClass("collapsed", (sub or "") == "")
            element:SetClass("collapsed", (main or "") == "" and (sub or "") == "")
        end,
    }
end

--The cover card's size and height in the fan, set by sliders in the editor
--and stored on media.book: coverScale (1 = same height as the pages) and
--coverY (a fraction of a page's height, + moves it down). Takes the book
--table, or the book slide, which carries both fields over.
AdventurePage.coverScaleMin = 0.7
AdventurePage.coverScaleMax = 1.4
AdventurePage.coverYMin = -0.3
AdventurePage.coverYMax = 0.3

function AdventurePage.CoverScale(book)
    local v = tonumber(book and book.coverScale) or 1
    return math.max(AdventurePage.coverScaleMin, math.min(AdventurePage.coverScaleMax, v))
end

function AdventurePage.CoverY(book)
    local v = tonumber(book and book.coverY) or 0
    return math.max(AdventurePage.coverYMin, math.min(AdventurePage.coverYMax, v))
end

--The book fan: every card is the same height and takes its own image's
--shape, so a page is always shown whole (US Letter PDFs, A4, odd scans alike).
--A card starts as A4 (1 : sqrt 2, the recommended size) until its image's size
--is known. The fan turns each card about a shared point below the cards' bottom
--edge, so the pages spread like a hand of cards. Angle per step out from the
--cover, and where the pivot sits (fraction of a card's height below its bottom edge).
local g_pageAspect = 1 / math.sqrt(2)
--shapes outside this range (a panorama, a strip) are cropped to its edge
--rather than making a card absurdly wide or thin.
local g_pageAspectMin = 0.5
local g_pageAspectMax = 1.0
local g_fanStepDegrees = 9
--sideways shift per step out from the cover, so the fan is wide without
--leaning further.
local g_fanStepSpread = 70
local g_fanPivotBelow = 0.25

--Tab 1: the cover front and centre with the pages fanned out behind it,
--alternating left and right, each step further out, tilted and darker. No
--frame or background: the fan stands on the page and may overhang the stage.
local function MakeBookSlide(width, stageH)
    local caption = MakeCaption(width, stageH, true)
    local spread = gui.Panel{
        floating = true,
        flow = "none",
        width = width,
        height = stageH,
        interactable = false,
    }

    return gui.Panel{
        floating = true,
        flow = "none",
        width = width,
        height = stageH,

        spread,
        caption,

        showSlide = function(element, slide, counts)
            local pdfs = CountOf(counts or {}, g_pdfTypes)
            if pdfs > 0 then
                --A single PDF is the adventure book itself, so it reads "Full PDF".
                local headline = cond(pdfs == 1, "Full PDF", Plural(pdfs, "PDF", "PDFs"))
                caption:FireEvent("setCaption", headline .. " included", slide.subtitle)
            else
                caption:FireEvent("setCaption", slide.subtitle or "", nil)
            end
        end,

        buildSlide = function(element, slide)
            local cover = slide.cover
            --the spread is sized from the cover, but nothing shows the cover
            --until then; an invisible bgimage starts its download.
            spread.bgimage = cover
            spread.selfStyle.bgcolor = "#ffffff00"
            AdventurePage.ImageDimensions(cover, function(dims)
                if mod.unloaded or not spread.valid then
                    return
                end
                if dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
                    return
                end
                --cards sized so the fan sits above the caption.
                local pageH = math.floor(stageH * 0.74)
                local pageW = math.floor(pageH * g_pageAspect)
                local lift = -40
                local pivot = {x = 0.5, y = -g_fanPivotBelow}

                --a card and its shadow, returned shadow first (it draws
                --underneath). Both are A4 until the image's size arrives, then
                --both take its width.
                --scale and dy (pixels, + is down) are only used for the cover,
                --which the editor can resize and move.
                local function Card(imageid, x, rotate, brightness, shadowAlpha, scale, dy)
                    local cardH = math.floor(pageH * (scale or 1))
                    local cardW = math.floor(cardH * g_pageAspect)
                    local cardY = lift + (dy or 0)
                    local shadow = gui.Panel{
                        floating = true,
                        halign = "center",
                        valign = "center",
                        x = x + 8,
                        y = cardY + 10,
                        width = cardW,
                        height = cardH,
                        pivot = pivot,
                        rotate = rotate,
                        bgimage = "panels/square.png",
                        bgcolor = string.format("#000000%02x", math.floor(shadowAlpha * 255)),
                        cornerRadius = 4,
                        interactable = false,
                    }
                    local page = gui.Panel{
                        floating = true,
                        halign = "center",
                        valign = "center",
                        x = x,
                        y = cardY,
                        width = cardW,
                        height = cardH,
                        pivot = pivot,
                        rotate = rotate,
                        bgimage = "panels/square.png",
                        bgcolor = "#ffffff10",
                        interactable = false,
                    }
                    --set through selfStyle: brightness given at construction does not stick.
                    page.selfStyle.brightness = brightness
                    page.selfStyle.saturation = 0.6 + 0.4 * brightness
                    page.bgimage = imageid
                    AdventurePage.ImageDimensions(imageid, function(d)
                        if mod.unloaded or not page.valid or page.bgimage ~= imageid then
                            return
                        end
                        if d == nil or (d.width or 0) <= 0 or (d.height or 0) <= 0 then
                            return
                        end
                        local aspect = math.max(g_pageAspectMin, math.min(g_pageAspectMax, d.width / d.height))
                        local w = math.floor(cardH * aspect)
                        page.selfStyle.width = w
                        if shadow.valid then
                            shadow.selfStyle.width = w
                        end
                        --whole image unless it was clamped above.
                        page.selfStyle.imageRect = CoverWindow(w, cardH, d.width, d.height, 1, 0.5, 0.5)
                        page.selfStyle.bgcolor = "#ffffffff"
                    end)
                    return shadow, page
                end

                --pages outermost first so each nearer page draws over the last.
                --Slots are fixed (L1, R1, L2, R2, L3, R3): each filled one keeps
                --its place, and an empty one ("") is simply left out.
                local pages = slide.pages or {}
                local steps = math.ceil(AdventurePage.maxBookPages / 2)
                local children = {}
                for step = steps, 1, -1 do
                    for side = -1, 1, 2 do
                        local index = (step - 1) * 2 + cond(side < 0, 1, 2)
                        local imageid = pages[index]
                        if imageid ~= nil and imageid ~= "" then
                            --positive turns counterclockwise, so left cards lean left.
                            local rotate = -side * step * g_fanStepDegrees
                            local x = side * step * g_fanStepSpread
                            local shadow, page = Card(imageid, x, rotate, 0.6 - 0.12 * (step - 1), 0.35)
                            children[#children + 1] = shadow
                            children[#children + 1] = page
                        end
                    end
                end
                local coverShadow, coverPage = Card(cover, 0, 0, 1, 0.55,
                    AdventurePage.CoverScale(slide), math.floor(AdventurePage.CoverY(slide) * pageH))
                children[#children + 1] = coverShadow
                children[#children + 1] = coverPage
                spread.children = children
            end)
        end,
    }
end

--Tab 2: every map in turn. Each map is its own layer: a looping video over its
--poster, or for an older map a still image and its place names drifting
--slowly. After g_mapHoldTime (or one loop of a longer video) the next layer
--fades in over it. Only the showing layer and the one fading out are updated.
local function MakeMapsSlide(width, stageH)
    local caption = MakeCaption(width, stageH)
    local m_maps = {}
    local m_layers = {}
    local m_current = 1
    local m_previous = nil
    local m_hold = 0
    local m_count = 0
    local m_still = false

    local function MakeLayer(map)
        local video = nil
        if type(map.video) == "string" and map.video ~= "" then
            video = map.video
        end
        --how long this map shows before the next: at least one whole loop.
        local hold = g_mapHoldTime
        if video ~= nil and (tonumber(map.duration) or 0) > hold then
            hold = tonumber(map.duration)
        end
        local state = {dims = nil, time = 0, pins = {}, video = video, hold = hold, active = false}

        local image = gui.Panel{
            classes = {"adventureMapMedia"},
            floating = true,
            width = width,
            height = stageH,
            interactable = false,
            bgimage = "panels/square.png",
            bgcolor = "#ffffff00",
        }

        --the video, over the poster in image. No placeholder bgimage: a video
        --draws nothing until its first frame, so the poster shows until then.
        local videoPanel = nil
        if video ~= nil then
            videoPanel = gui.Panel{
                classes = {"adventureMapMedia", "collapsed"},
                floating = true,
                width = width,
                height = stageH,
                interactable = false,
                bgcolor = "#ffffffff",
            }
        end

        for i, pin in ipairs(map.pins or {}) do
            state.pins[i] = gui.Label{
                classes = {"adventurePin"},
                floating = true,
                halign = "left",
                valign = "top",
                interactable = false,
                text = pin.label or "",
                fontFace = g_serif,
                fontSize = 18,
                color = g_textStrong,
                width = "auto",
                height = "auto",
                hpad = 12,
                vpad = 4,
                borderBox = true,
                bgimage = "panels/square.png",
                bgcolor = "#000000b3",
                borderWidth = 1,
                borderColor = "#f6ddb659",
                cornerRadius = 4,
            }
        end

        local layerChildren = {image}
        if videoPanel ~= nil then
            layerChildren[#layerChildren + 1] = videoPanel
        end
        for _, pin in ipairs(state.pins) do
            layerChildren[#layerChildren + 1] = pin
        end

        local layer = gui.Panel{
            classes = {"adventureMapLayer"},
            floating = true,
            flow = "none",
            width = width,
            height = stageH,
            interactable = false,
            data = {state = state, map = map},
            children = layerChildren,
        }

        --Positions the window and the pins for this layer's own clock.
        state.apply = function()
            if state.dims == nil then
                return
            end
            local u, v, zoom = 0.5, 0.5, g_panZoom
            if videoPanel ~= nil then
                --the video is the motion: it fills the frame, centred, with no
                --pan. It plays only while its layer shows or fades out (so the
                --hidden maps are not all decoding); otherwise, and with reduced
                --motion, the poster stands in.
                zoom = 1
                local playing = state.active and not m_still
                videoPanel:SetClass("collapsed", not playing)
                if playing and videoPanel.bgimage ~= video then
                    videoPanel.bgimage = video
                end
            elseif not m_still then
                --cosine ease: slows to a stop at each end of the sweep.
                local phase = (state.time / g_panPeriod) * 2 * math.pi
                u = 0.5 - 0.5 * math.cos(phase)
                v = 0.5 - 0.5 * math.cos(phase * g_panVerticalRatio)
            end
            local rect, left, top, wFrac, hFrac = CoverWindow(width, stageH, state.dims.width, state.dims.height, zoom, u, v)
            image.selfStyle.imageRect = rect
            if videoPanel ~= nil then
                videoPanel.selfStyle.imageRect = rect
            end
            for i, pinDef in ipairs(map.pins or {}) do
                local label = state.pins[i]
                local px = ((pinDef.x or 0.5) - left) / wFrac
                local py = ((pinDef.y or 0.5) - top) / hFrac
                label.x = px * width - label.renderedWidth * 0.5
                label.y = py * stageH - label.renderedHeight * 0.5
                label:SetClass("pinShown", px > g_pinInset and px < 1 - g_pinInset and py > g_pinInset and py < 1 - g_pinInset)
            end
        end

        image.bgimage = map.image
        local mapW, mapH = tonumber(map.width) or 0, tonumber(map.height) or 0
        if video ~= nil and mapW > 0 and mapH > 0 then
            --the poster has the video's shape, which the map records.
            state.dims = {width = mapW, height = mapH}
            state.apply()
            image.selfStyle.bgcolor = "#ffffffff"
        else
            AdventurePage.ImageDimensions(map.image, function(dims)
                if mod.unloaded or not image.valid then
                    return
                end
                if dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
                    return
                end
                state.dims = dims
                state.apply()
                image.selfStyle.bgcolor = "#ffffffff"
            end)
        end

        return layer
    end

    local function ShowCaption()
        local map = m_maps[m_current]
        local total = math.max(m_count, #m_maps)
        caption:FireEvent("setCaption", Plural(total, "map", "maps") .. " included", map and map.name)
    end

    local function Select(index)
        m_previous = m_current
        m_current = index
        m_hold = 0
        for i, layer in ipairs(m_layers) do
            layer:SetClass("mapShown", i == m_current)
            local s = layer.data.state
            s.active = i == m_current or i == m_previous
            if s.video ~= nil and i ~= m_current then
                s.apply()
            end
        end
        local state = m_layers[m_current].data.state
        state.time = 0
        state.apply()
        ShowCaption()
    end

    local layerHost = gui.Panel{
        floating = true,
        flow = "none",
        width = width,
        height = stageH,
        interactable = false,
        --opacity is not inherited (it fades only a panel's own image), so the
        --cross-fade is on each layer's poster and video, keyed off the layer.
        styles = {
            {selectors = {"adventureMapMedia"}, opacity = 0, transitionTime = g_mapFadeTime},
            {selectors = {"adventureMapMedia", "parent:mapShown"}, opacity = 1, transitionTime = g_mapFadeTime},
        },
    }

    return gui.Panel{
        floating = true,
        flow = "none",
        width = width,
        height = stageH,
        --the dark, clipped frame the map pans inside (the stage itself is bare,
        --so the book fan can overhang it).
        clip = true,
        bgimage = "panels/square.png",
        bgcolor = "#0e0e10ff",
        cornerRadius = 8,

        layerHost,
        caption,

        --Runs only while this slide is the visible one: collapsed slides (and
        --a collapsed details page) do not think.
        think = function(element)
            if #m_layers == 0 then
                return
            end
            local dt = element.thinkTime
            local state = m_layers[m_current].data.state
            if not m_still then
                --a video layer is set up once, by Select; only still maps drift.
                if state.video == nil then
                    state.time = state.time + dt
                    state.apply()
                end
                --keep the outgoing map drifting until it has faded away.
                if m_previous ~= nil and m_previous ~= m_current and m_hold < g_mapFadeTime then
                    local prev = m_layers[m_previous].data.state
                    if prev.video == nil then
                        prev.time = prev.time + dt
                        prev.apply()
                    end
                end
            end
            if #m_layers > 1 and not m_still then
                m_hold = m_hold + dt
                --the outgoing map has faded away: stop its video.
                if m_previous ~= nil and m_previous ~= m_current and m_hold >= g_mapFadeTime then
                    local prev = m_layers[m_previous].data.state
                    if prev.active then
                        prev.active = false
                        prev.apply()
                    end
                end
                if m_hold >= state.hold then
                    Select((m_current % #m_layers) + 1)
                end
            end
        end,

        buildSlide = function(element, slide)
            m_maps = {}
            for _, map in ipairs(slide.maps or {}) do
                if type(map.image) == "string" and map.image ~= "" then
                    m_maps[#m_maps + 1] = map
                end
            end
            m_layers = {}
            for i, map in ipairs(m_maps) do
                m_layers[i] = MakeLayer(map)
            end
            layerHost.children = m_layers
            m_current = 1
            m_previous = nil
            m_hold = 0
        end,

        showSlide = function(element, slide, counts)
            m_count = CountOf(counts or {}, g_mapTypes)
            m_still = ReduceMotion()
            element.thinkTime = 0.03
            if #m_layers > 0 then
                Select(1)
            end
        end,
    }
end

--Tabs 3+: one piece of art, shown whole on the dark stage.
local function MakeArtSlide(width, stageH)
    local caption = MakeCaption(width, stageH)
    local image = gui.Panel{
        floating = true,
        halign = "center",
        valign = "center",
        width = width,
        height = stageH,
        interactable = false,
        bgimage = "panels/square.png",
        bgcolor = "#ffffff00",
    }
    return gui.Panel{
        floating = true,
        flow = "none",
        width = width,
        height = stageH,
        --dark frame the art is letterboxed in.
        clip = true,
        bgimage = "panels/square.png",
        bgcolor = "#0e0e10ff",
        cornerRadius = 8,

        image,
        caption,

        buildSlide = function(element, slide)
            image.bgimage = slide.image
            AdventurePage.ImageDimensions(slide.image, function(dims)
                if mod.unloaded or not image.valid then
                    return
                end
                if dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
                    return
                end
                --fit inside the stage at the art's own aspect: letterboxed, never
                --cropped or stretched.
                local scale = math.min(width / dims.width, stageH / dims.height)
                image.selfStyle.width = math.floor(dims.width * scale)
                image.selfStyle.height = math.floor(dims.height * scale)
                image.selfStyle.bgcolor = "#ffffffff"
            end)
        end,

        showSlide = function(element, slide, counts)
            caption:FireEvent("setCaption", slide.caption or "", nil)
        end,
    }
end

--The slides a page config describes, in tab order, each with the image its
--tab thumbnail shows and the tab's label.
local function SlidesFromConfig(cfg)
    local media = cfg.media or {}
    local slides = {}

    local book = media.book
    if type(book) == "table" and type(book.cover) == "string" and book.cover ~= "" then
        slides[#slides + 1] = {kind = "book", cover = book.cover, pages = book.pages or {}, subtitle = book.subtitle,
                               coverScale = book.coverScale, coverY = book.coverY,
                               thumb = book.cover, label = "The book"}
    end

    local maps = {}
    for _, map in ipairs(media.maps or {}) do
        if type(map.image) == "string" and map.image ~= "" then
            maps[#maps + 1] = map
        end
    end
    if #maps > 0 then
        slides[#slides + 1] = {kind = "maps", maps = maps, thumb = maps[1].image, label = "Maps"}
    end

    local artCount = 0
    for _, art in ipairs(media.art or {}) do
        if type(art.image) == "string" and art.image ~= "" and artCount < g_maxArt then
            artCount = artCount + 1
            slides[#slides + 1] = {kind = "art", image = art.image, caption = art.caption,
                                   thumb = art.image, label = art.label or "Art"}
        end
    end

    return slides
end

local function MakeMediaViewer(width, stageH)
    local m_slides = {}
    local m_panels = {}
    local m_counts = {}
    local m_selected = 1
    local m_moduleid = nil

    local stage = gui.Panel{
        width = width,
        height = stageH,
        flow = "none",
        --bare: each slide brings its own frame, and the book has none so its
        --fan can stick out past the stage.
        styles = {
            {selectors = {"adventurePin"}, opacity = 0, transitionTime = 1.2},
            --parent:mapShown: a hidden map layer's pins must not show over the current one.
            {selectors = {"adventurePin", "pinShown", "parent:mapShown"}, opacity = 1, transitionTime = 1.2},
        },
    }

    local tabGap = 12
    local tabCount = 2 + g_maxArt
    local tabW = math.floor((width - tabGap * (tabCount - 1)) / tabCount)
    local tabH = math.floor(tabW * 9 / 16)

    local tabs = gui.Panel{
        flow = "horizontal",
        width = width,
        height = "auto",
        tmargin = 14,
        styles = {
            {selectors = {"adventureTab"}, brightness = 0.6, borderColor = "#00000000", transitionTime = 0.15},
            {selectors = {"adventureTab", "hover"}, brightness = 1},
            {selectors = {"adventureTab", "selected"}, brightness = 1, borderColor = g_accent},
            {selectors = {"adventureTabLabel"}, color = g_textMuted},
            {selectors = {"adventureTabLabel", "selected"}, color = g_textStrong},
        },
    }

    local function Select(index)
        m_selected = index
        for i, panel in ipairs(m_panels) do
            panel:SetClass("collapsed", i ~= index)
        end
        if m_panels[index] ~= nil then
            m_panels[index]:FireEvent("showSlide", m_slides[index], m_counts)
        end
        tabs:FireEventTree("tabSelected", index)
    end

    local function BuildTabs()
        local children = {}
        for i, slide in ipairs(m_slides) do
            local thumb = gui.Panel{
                classes = {"adventureTab", cond(i == m_selected, "selected")},
                width = tabW,
                height = tabH,
                bgimage = "panels/square.png",
                bgcolor = "#ffffff10",
                borderWidth = 2,
                cornerRadius = 5,
                tabSelected = function(element, index)
                    element:SetClass("selected", index == i)
                end,
            }
            --v = 0 for the book: keep the top of the cover, where its title is.
            ShowCovered(thumb, slide.thumb, tabW, tabH, cond(slide.kind == "book", 0, 0.5))

            children[#children + 1] = gui.Panel{
                flow = "vertical",
                width = tabW,
                height = "auto",
                lmargin = cond(i == 1, 0, tabGap),
                press = function(element)
                    Select(i)
                end,
                thumb,
                gui.Label{
                    classes = {"adventureTabLabel", cond(i == m_selected, "selected")},
                    text = slide.label,
                    fontSize = 13,
                    width = tabW,
                    height = "auto",
                    textAlignment = "left",
                    tmargin = 6,
                    tabSelected = function(element, index)
                        element:SetClass("selected", index == i)
                    end,
                },
            }
        end
        tabs.children = children
        --one slide needs no tabs.
        tabs:SetClass("collapsed", #children <= 1)
    end

    return gui.Panel{
        flow = "vertical",
        width = width,
        height = "auto",

        stage,
        tabs,

        showPage = function(element, item, cfg)
            m_slides = SlidesFromConfig(cfg)
            m_counts = {}
            m_selected = 1
            element:SetClass("collapsed", #m_slides == 0)

            m_panels = {}
            for i, slide in ipairs(m_slides) do
                local panel
                if slide.kind == "book" then
                    panel = MakeBookSlide(width, stageH)
                elseif slide.kind == "maps" then
                    panel = MakeMapsSlide(width, stageH)
                else
                    panel = MakeArtSlide(width, stageH)
                end
                m_panels[i] = panel
            end
            stage.children = m_panels
            for i, panel in ipairs(m_panels) do
                panel:FireEvent("buildSlide", m_slides[i])
            end
            BuildTabs()
            if #m_slides > 0 then
                Select(1)
            end

            --the captions' counts arrive later; re-show the current slide then.
            local moduleid = item.assetid
            m_moduleid = moduleid
            FetchCounts(moduleid, function(counts)
                if mod.unloaded or not element.valid or m_moduleid ~= moduleid then
                    return
                end
                m_counts = ApplyCountOverrides(counts, cfg)
                if m_panels[m_selected] ~= nil then
                    m_panels[m_selected]:FireEvent("showSlide", m_slides[m_selected], m_counts)
                end
            end)
        end,
    }
end

--------------------------------------------------------------------------------
--Body, left column: about (in the book's voice) and the cast.
--------------------------------------------------------------------------------
local function SerifHeading(text, size)
    return gui.Label{
        text = text,
        fontFace = g_serif,
        fontSize = size or 28,
        color = g_textStrong,
        width = "auto",
        height = "auto",
        halign = "left",
    }
end

--Popout art is drawn whole, this much larger than the frame at popoutScale 1,
--matching the map's TokenPopoutShader (its frameUV factor). Cropping the edges
--instead, as gui.CreateTokenImage does, cuts off whatever pokes out the top.
local g_popoutArtScale = 1.46

--The window of a regular token's art that shows in the ring. Placed art
--(zoom + center, set by dragging in the editor) is recomputed from the image's
--size, keeping the window square on screen and inside the image; otherwise the
--token's own crop is used. center is in image fractions, top-down.
function AdventurePage.CastRect(member, dims)
    if member.zoom == nil or dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
        return member.rect or {x1 = 0, y1 = 0, x2 = 1, y2 = 1}
    end
    local side = math.min(dims.width, dims.height) / math.max(1, member.zoom)
    local rw, rh = side / dims.width, side / dims.height
    local center = member.center or {x = 0.5, y = 0.5}
    local cx = math.max(rw / 2, math.min(1 - rw / 2, center.x or 0.5))
    local cy = math.max(rh / 2, math.min(1 - rh / 2, center.y or 0.5))
    --imageRect runs bottom-up.
    return {x1 = cx - rw / 2, x2 = cx + rw / 2, y1 = 1 - cy - rh / 2, y2 = 1 - cy + rh / 2}
end

--A cast portrait as the store page draws it. A member picked from one of the
--adventure's tokens is drawn exactly as gui.CreateTokenImage draws that token:
--its art cut out by its frame with the frame on top, or popout art over the
--frame. Anything else (uploaded art, and tokens picked before frames were
--recorded) gets the page's own ring, with plain images and regular tokens
--clipped inside it and popout art breaking out over it. Fire
--showMember(member) to fill it. The editor uses it as its preview.
function AdventurePage.MakeCastPortrait(size, extra)
    local portrait = gui.Panel{
        width = size,
        height = size,
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#ffffff10",
        cornerRadius = size / 2,
        borderWidth = 2,
        borderColor = "#f6ddb640",
        interactable = false,
    }
    --the token's own frame, over regular art and under popout art.
    local frameArt = gui.Panel{
        classes = {"collapsed"},
        floating = true,
        width = size,
        height = size,
        halign = "center",
        valign = "center",
        bgcolor = "white",
        interactable = false,
    }
    local popoutArt = gui.Panel{
        classes = {"collapsed"},
        floating = true,
        width = size,
        height = size,
        halign = "center",
        valign = "center",
        bgcolor = "white",
        interactable = false,
    }
    local args = {
        width = size,
        height = size,
        halign = "center",
        portrait,
        frameArt,
        popoutArt,
        showMember = function(element, member)
            local framed = member.token and type(member.frame) == "string" and member.frame ~= ""
            popoutArt:SetClass("collapsed", not (member.token and member.popout))
            frameArt:SetClass("collapsed", not framed)
            if framed then
                frameArt.bgimage = member.frame
                frameArt.selfStyle.hueshift = member.frameHue or 0
            end
            --a framed token draws no ring: the frame is its border.
            portrait.selfStyle.cornerRadius = cond(framed, 0, size / 2)
            portrait.selfStyle.borderWidth = cond(framed, 0, 2)
            --regular art is cut out by the frame, as on the map.
            portrait.bgimageTokenMask = cond(framed and not member.popout, member.frame, nil)
            if member.token and member.popout then
                portrait.bgimage = "panels/square.png"
                portrait.selfStyle.bgcolor = cond(framed, "clear", "#ffffff10")
                local offset = member.offset or {x = 0, y = 0}
                popoutArt.bgimage = member.image
                popoutArt.selfStyle.imageRect = {x1 = 0, y1 = 0, x2 = 1, y2 = 1}
                popoutArt.selfStyle.scale = g_popoutArtScale / (member.popoutScale or 1)
                popoutArt.selfStyle.x = (offset.x or 0) * size
                popoutArt.selfStyle.y = (offset.y or 0) * size
            elseif member.token then
                local image = member.image
                portrait.bgimage = image
                portrait.selfStyle.bgcolor = "#ffffffff"
                portrait.selfStyle.imageRect = AdventurePage.CastRect(member, nil)
                if member.zoom ~= nil then
                    AdventurePage.ImageDimensions(image, function(dims)
                        if mod.unloaded or not portrait.valid or portrait.bgimage ~= image then
                            return
                        end
                        portrait.selfStyle.imageRect = AdventurePage.CastRect(member, dims)
                    end)
                end
            else
                --v = 0: keep the top of the art, where faces usually are.
                ShowCovered(portrait, member.image, size, size, 0)
            end
        end,
    }
    for k, v in pairs(extra or {}) do
        args[k] = v
    end
    return gui.Panel(args)
end

local function MakeCastMember(size, colW)
    local portrait = AdventurePage.MakeCastPortrait(size)
    local name = gui.Label{
        fontSize = 15,
        color = g_textStrong,
        width = colW,
        height = "auto",
        textAlignment = "center",
        tmargin = 10,
    }
    local role = gui.Label{
        fontSize = 13,
        color = g_textMuted,
        width = colW,
        height = "auto",
        textAlignment = "center",
    }
    return gui.Panel{
        flow = "vertical",
        width = colW,
        height = "auto",
        valign = "top",
        portrait,
        name,
        role,
        showMember = function(element, member)
            portrait:FireEvent("showMember", member)
            name.text = member.name or ""
            role.text = member.role or ""
            role:SetClass("collapsed", (member.role or "") == "")
        end,
    }
end

local function MakeAboutColumn(width)
    local aboutTitle = SerifHeading("", 30)
    local aboutText = gui.Label{
        fontSize = 16,
        fontWeight = "light",
        color = g_textBody,
        width = width,
        height = "auto",
        textAlignment = "left",
        tmargin = 12,
    }

    local maxCast = 5
    local colW = math.floor(width / maxCast)
    local members = {}
    for i = 1, maxCast do
        members[i] = MakeCastMember(116, colW)
    end

    local castSection = gui.Panel{
        flow = "vertical",
        width = width,
        height = "auto",
        tmargin = 40,
        SerifHeading("Meet the cast", 26),
        gui.Panel{
            flow = "horizontal",
            width = width,
            height = "auto",
            tmargin = 18,
            children = members,
        },
    }

    return gui.Panel{
        flow = "vertical",
        width = width,
        height = "auto",
        valign = "top",

        aboutTitle,
        aboutText,
        castSection,

        showPage = function(element, item, cfg)
            aboutTitle.text = cond((cfg.aboutTitle or "") ~= "", cfg.aboutTitle, "About this adventure")
            local about = cfg.about
            if about == nil or about == "" then
                about = item.details or ""
            end
            aboutText.text = about
            aboutText:SetClass("collapsed", about == "")

            local cast = {}
            for _, member in ipairs(cfg.cast or {}) do
                if type(member.image) == "string" and member.image ~= "" and #cast < maxCast then
                    cast[#cast + 1] = member
                end
            end
            castSection:SetClass("collapsed", #cast == 0)
            for i, panel in ipairs(members) do
                panel:SetClass("collapsed", cast[i] == nil)
                if cast[i] ~= nil then
                    panel:FireEvent("showMember", cast[i])
                end
            end
        end,
    }
end

--------------------------------------------------------------------------------
--Body, right column: the buy box -- price, button, what's inside.
--------------------------------------------------------------------------------

--What the module's contentSummary counts become, in display order. A def
--with text shows that fixed line (no number) whenever its count is above 0.
local g_insideDefs = {
    {one = "battle map", many = "battle maps", types = g_mapTypes},
    {one = "monster", many = "monsters", types = AdventurePage.countTypes.monsters},
    {one = "NPC", many = "NPCs", types = AdventurePage.countTypes.characters},
    {one = "treasure", many = "treasures", types = AdventurePage.countTypes.treasures},
    {one = "title", many = "titles", types = AdventurePage.countTypes.titles},
    {text = "Director PDF", types = g_pdfTypes},
}

local function InsideLines(counts)
    local lines = {}
    for _, def in ipairs(g_insideDefs) do
        local total = CountOf(counts, def.types)
        if total > 0 then
            lines[#lines + 1] = def.text or Plural(total, def.one, def.many)
        end
    end
    return lines
end

local function MakeBuyBox(width)
    local price = gui.Label{
        fontFace = g_serif,
        fontSize = 36,
        color = g_textStrong,
        width = "auto",
        height = "auto",
        halign = "left",
        classes = {"collapsedWhenInventory"},
    }

    local insideList = gui.Label{
        fontSize = 15,
        color = g_textBody,
        width = width - 48,
        height = "auto",
        textAlignment = "left",
        tmargin = 8,
    }

    local insideSection = gui.Panel{
        flow = "vertical",
        width = width - 48,
        height = "auto",
        tmargin = 22,
        gui.Panel{
            width = width - 48,
            height = 1,
            bgimage = "panels/square.png",
            bgcolor = "#ffffff1a",
            bmargin = 18,
        },
        gui.Label{
            text = "What's inside",
            uppercase = true,
            fontSize = 12,
            color = g_textMuted,
            width = "auto",
            height = "auto",
            halign = "left",
        },
        insideList,
    }

    local m_moduleid = nil

    local function ShowLines(lines)
        local bulleted = {}
        for i, line in ipairs(lines) do
            bulleted[i] = "\u{2022}  " .. line
        end
        insideList.text = table.concat(bulleted, "\n")
        insideSection:SetClass("collapsed", #lines == 0)
    end

    return gui.Panel{
        flow = "vertical",
        width = width,
        height = "auto",
        valign = "top",
        pad = 24,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = "#ffffff08",
        borderWidth = 1,
        borderColor = "#ffffff1f",
        cornerRadius = 10,

        price,
        gui.Panel{
            width = width - 48,
            height = "auto",
            tmargin = 14,
            MakeBuyButton(width - 48, false),
        },
        insideSection,

        showPage = function(element, item, cfg)
            price.text = PriceText(item)

            local moduleid = item.assetid
            m_moduleid = moduleid
            insideSection:SetClass("collapsed", true)
            FetchCounts(moduleid, function(counts)
                if mod.unloaded or not element.valid or m_moduleid ~= moduleid then
                    return
                end
                ShowLines(InsideLines(ApplyCountOverrides(counts, cfg)))
            end)
        end,
    }
end

--------------------------------------------------------------------------------

--Builds the adventure page for the shop details view. Listens for the
--details page's refreshItem(item) and shows itself only for items that have
--a page config; everything else keeps the generic layout.
--  args.width: the page width (the details view passes its banner width).
function AdventurePage.Create(args)
    local width = args.width
    local rightW = 360
    local gap = 44
    local leftW = width - rightW - gap - 56 * 2

    return gui.Panel{
        classes = {"collapsed"},
        flow = "vertical",
        width = width,
        height = "auto",
        halign = "center",
        valign = "top",
        bgimage = "panels/square.png",
        bgcolor = g_pageBg,

        MakeHero(width, 520),

        gui.Panel{
            width = width - 56 * 2,
            height = "auto",
            halign = "center",
            tmargin = 8,
            MakeMediaViewer(width - 56 * 2, math.floor((width - 56 * 2) * 9 / 16)),
        },

        gui.Panel{
            flow = "horizontal",
            width = width - 56 * 2,
            height = "auto",
            halign = "center",
            tmargin = 48,
            bmargin = 56,
            MakeAboutColumn(leftW),
            gui.Panel{
                width = rightW,
                height = "auto",
                lmargin = gap,
                valign = "top",
                MakeBuyBox(rightW),
            },
        },

        refreshItem = function(element, item)
            local cfg = AdventurePage.Read(item)
            element:SetClass("collapsed", cfg == nil)
            if cfg ~= nil then
                element:FireEventTree("showPage", item, cfg)
            end
        end,
    }
end
