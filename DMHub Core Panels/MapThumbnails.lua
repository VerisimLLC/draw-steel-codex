local mod = dmhub.GetModLoading()

--Map thumbnails: the picture to show for a map, and a panel that shows it.
--The engine captures and stores the thumbnail (map.thumbnailImage, see
--MAP_THUMBNAILS.md at the repo root); this file picks the best picture a map
--has and displays it the way the map pack browser shows its tiles.
--
--  MapThumbnail.Image(map)            best bgimage for a map, or nil
--  MapThumbnail.Aspect(map)           width / height of the map in tiles
--  MapThumbnail.Panel{ mapid = ... }  a cover-fit picture of a map
--  MapThumbnail.Refresh(map, options) capture the current map's thumbnail now

--- @class MapThumbnailPanelArgs
--- @field mapid string|nil The map to show; nil shows nothing. Change it later with the setMap event.
--- @field width number|string|nil
--- @field height number|string|nil
--- @field pan boolean|nil Drift across a picture that overflows the panel while hovered, like the map pack tiles. Makes the panel take hover.
--- @field classes string[]|nil
--- @field halign string|nil
--- @field floating boolean|nil
--- @field valign string|nil

MapThumbnail = {}

--Map-pack thumbnails found so far, by "pack/mapid". Searching a pack walks
--its whole index (~50ms for a big pack), so a hit is never looked up twice.
local g_packThumbs = {}

local function ResolveMap(mapOrId)
    if type(mapOrId) == "string" then
        if mapOrId == "" then
            return nil
        end
        mapOrId = game.GetMap(mapOrId)
    end
    if mapOrId == nil or not mapOrId.valid then
        return nil
    end
    return mapOrId
end

local function PackThumb(map)
    local source = map.packSource
    if source == nil or rawget(_G, "mappacks") == nil then
        return nil
    end
    local key = source.pack .. "/" .. source.mapid
    if g_packThumbs[key] == nil then
        for _, entry in ipairs(mappacks.Search { text = "", pack = source.pack, maxResults = 10000 }) do
            if entry.id == source.mapid and entry.variantIndex == 0 and (entry.thumb or "") ~= "" then
                --raw content-addressed ids display through the md5: prefix.
                g_packThumbs[key] = "md5:" .. entry.thumb
                break
            end
        end
    end
    return g_packThumbs[key]
end

--- The best picture of a map, as a bgimage id, or nil when it has none. In
--- order: its captured thumbnail, its map pack's artwork, its loading-screen
--- art, the tabletop snapshot of its window (this session only).
--- The second result names the source: "thumbnail", "pack", "art" or "snapshot".
--- @param mapOrId MapManifestLua|string
--- @return string|nil image
--- @return string|nil source
function MapThumbnail.Image(mapOrId)
    local map = ResolveMap(mapOrId)
    if map == nil then
        return nil, nil
    end

    local thumbnail = map.thumbnailImage
    if thumbnail ~= nil and thumbnail ~= "" then
        return thumbnail, "thumbnail"
    end

    local pack = PackThumb(map)
    if pack ~= nil then
        return pack, "pack"
    end

    local art = map.loadingScreenImage
    if type(art) == "string" and art ~= "" then
        return art, "art"
    end

    if dmhub.HasMapSnapshot(map.id) then
        return "#MapSnapshot:" .. map.id, "snapshot"
    end

    return nil, nil
end

--- Width / height of a map in tiles: the shape of its captured thumbnail.
--- @param mapOrId MapManifestLua|string
--- @return number
function MapThumbnail.Aspect(mapOrId)
    local map = ResolveMap(mapOrId)
    if map == nil then
        return 1
    end
    local dim = map.dimensions
    local w = math.max(1, dim.z - dim.x)
    local h = math.max(1, dim.w - dim.y)
    return w / h
end

--The smallest size with the given aspect that covers boxW x boxH (the same
--fit as mod.shared.MapPackCoverSize).
local function CoverSize(aspect, boxW, boxH)
    if aspect >= boxW / boxH then
        return math.ceil(boxH * aspect), boxH
    end
    return boxW, math.ceil(boxW / aspect)
end

--- Capture the current map's thumbnail now (Director only). options.complete(assetid)
--- and options.error(message) are optional; with no error handler a failure
--- is shown in a message box.
--- @param mapOrId MapManifestLua|string
--- @param options {complete: nil|fun(assetid: string), error: nil|fun(message: string)}|nil
function MapThumbnail.Refresh(mapOrId, options)
    options = options or {}
    local map = ResolveMap(mapOrId)
    local function Fail(message)
        if options.error ~= nil then
            options.error(message)
        else
            gui.ModalMessage {
                title = "Map Thumbnail",
                message = message,
            }
        end
    end
    if map == nil then
        Fail("This map no longer exists.")
        return
    end
    map:CaptureThumbnail {
        complete = function(assetid)
            if options.complete ~= nil then
                options.complete(assetid)
            end
        end,
        error = Fail,
    }
end

--- A cover-fit picture of a map: the picture fills the panel keeping the
--- map's shape, cropped to the middle (built like the map pack browser's
--- tiles: a clipping viewport around an oversized image). Shows nothing when
--- the map has no picture, so put it over a background. Refreshes itself when
--- maps change; fire "setMap" with a map id (or nil) to show another map.
--- width and height must be numbers when pan is set.
--- @param args MapThumbnailPanelArgs
--- @return Panel
function MapThumbnail.Panel(args)
    local mapid = args.mapid
    local pan = args.pan == true
    local boxW = args.width or "100%"
    local boxH = args.height or "100%"

    --the picture's own shape once it has loaded; until then the map's.
    local imageAspect = nil
    local overflowX, overflowY = 0, 0

    --hover pan state (see the pan section below).
    local panStart = nil
    local panOffset = 0
    local lastThink = nil

    local image
    local function Layout()
        if image == nil or not image.valid then
            return
        end
        local w, h = image.parent.renderedWidth, image.parent.renderedHeight
        if type(boxW) == "number" then w = boxW end
        if type(boxH) == "number" then h = boxH end
        if w == nil or h == nil or w <= 0 or h <= 0 then
            return
        end
        local iw, ih = CoverSize(imageAspect or MapThumbnail.Aspect(mapid or ""), w, h)
        image.selfStyle.width = iw
        image.selfStyle.height = ih
        overflowX = math.max(0, iw - w)
        overflowY = math.max(0, ih - h)
    end

    image = gui.Panel {
        classes = { "mapThumbnailImage", "hidden" },
        bgimage = "panels/square.png",
        bgcolor = "white",
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        interactable = false,
        imageLoaded = function(element)
            local w, h = element.bgimageWidth, element.bgimageHeight
            if w ~= nil and h ~= nil and w > 0 and h > 0 then
                imageAspect = w / h
                Layout()
            end
        end,
    }

    local panel

    local function Show()
        local picture = mapid ~= nil and MapThumbnail.Image(mapid) or nil
        image:SetClass("hidden", picture == nil)
        --a dark backing under a picture still loading; nothing at all without one.
        if panel ~= nil then
            panel.selfStyle.bgcolor = cond(picture == nil, "clear", "black")
        end
        if picture ~= nil and image.bgimage ~= picture then
            imageAspect = nil
            image.bgimage = picture
        end
        image.x = 0
        image.y = 0
        Layout()
        --at rest the picture is centred: halfway through its pan range.
        panOffset = math.max(overflowX, overflowY) / 2
    end

    --hover pan: the picture drifts along whichever side overflows and eases
    --back when the mouse leaves (MapPackBrowser.lua's tile pan, centred).
    local tuning = mod.shared.MapPackPanTuning or { speed = 40, minPeriod = 4, returnRate = 6 }

    local function PanRange()
        return math.max(overflowX, overflowY)
    end

    local function ApplyPan()
        local range = PanRange()
        local offset = panOffset - range / 2
        if overflowX > 0 then
            image.x = offset
        elseif overflowY > 0 then
            image.y = offset
        end
    end

    panel = gui.Panel {
        classes = args.classes,
        width = boxW,
        height = boxH,
        halign = args.halign,
        valign = args.valign,
        floating = args.floating,
        --clipping needs a background image to clip to (as the map pack tile viewport has).
        bgimage = "panels/square.png",
        bgcolor = "clear",
        clip = true,
        clipHidden = true,
        interactable = pan,

        image,

        create = function(element)
            Show()
        end,

        --picture changes: captured, renamed, deleted.
        monitorGame = "/mapManifests",
        refreshGame = function(element)
            Show()
        end,

        setMap = function(element, newMapId)
            if newMapId == "" then
                newMapId = nil
            end
            mapid = newMapId
            Show()
        end,

        hover = pan and function(element)
            local range = PanRange()
            if range <= 0 then
                return
            end
            local period = math.max(tuning.minPeriod, 2 * range / tuning.speed)
            --start the swing from the centre (the rest position) so it never jumps.
            local phase = math.acos(1 - 2 * math.min(1, panOffset / range))
            panStart = dmhub.Time() - phase * period / (2 * math.pi)
            lastThink = dmhub.Time()
            element.thinkTime = 0.01
        end or nil,

        dehover = pan and function(element)
            panStart = nil
        end or nil,

        think = pan and function(element)
            local now = dmhub.Time()
            local range = PanRange()
            local rest = range / 2
            if panStart ~= nil and range > 0 then
                local period = math.max(tuning.minPeriod, 2 * range / tuning.speed)
                local phase = (now - panStart) * 2 * math.pi / period
                panOffset = range * (1 - math.cos(phase)) / 2
            else
                --ease back to the centre, then stop thinking.
                local dt = now - (lastThink or now)
                panOffset = rest + (panOffset - rest) * math.exp(-dt * tuning.returnRate)
                if math.abs(panOffset - rest) < 0.5 then
                    panOffset = rest
                    element.thinkTime = nil
                end
            end
            lastThink = now
            ApplyPan()
        end or nil,
    }

    return panel
end
