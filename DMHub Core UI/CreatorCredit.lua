local mod = dmhub.GetModLoading()

--Credits for third-party creators whose art the app shows (scene backdrops,
--key art, location art). Each creator is registered once, with a logo and a
--link; any screen that shows their work puts CreatorCredit.Badge on it, or
--builds the whole screen on CreatorCredit.Backdrop, so the credit looks and
--behaves the same everywhere: the creator's logo in a corner of the art,
--with a tooltip naming them, that opens their site when clicked.
--
--To credit a new creator:
--  1. Upload their logo as a core image asset on a transparent background,
--     in white, since it is drawn straight over the art with no backing:
--     badges show it black (brightness 0) unless the caller passes
--     light = true for dark art. If their licence
--     supplies a watermark, use that, and set widthFraction to the share of
--     the art's width their licence says it must span.
--  2. Add a CreatorCredit.Register call at the bottom of this file.
--  3. Either pass creator = "<id>" wherever their art is shown, or tag the
--     art once with CreatorCredit.RegisterArt(imageid, "<id>") and let
--     Backdrop find the credit from the image.
--
--A creator organization's own branding (/ModuleAuthor/{orgid} logo + url)
--can also be credited, with no entry in this file: ForOrganization builds and
--registers the credit from it on first use.

--- @class CreatorCreditInfo
--- @field id string
--- @field name string Shown in the badge's tooltip ("Art by <name>").
--- @field logo string Image id of the logo, white on transparent (Badge darkens it to black unless light is set).
--- @field logoWidth number The logo image's pixel size, for its aspect ratio.
--- @field logoHeight number
--- @field widthFraction nil|number The share of the art's width the logo must span (a licence term); nil for a fixed-size badge.
--- @field url nil|string The creator's site; the badge opens it when clicked.

CreatorCredit = {
    --- @type table<string, CreatorCreditInfo>
    creators = {},

    --- Image (or video) id -> creator id, for art tagged with RegisterArt.
    --- @type table<string, string>
    art = {},

    --- Image (or video) id -> creator id, learned from the "Art by" setting
    --- of [[scene]] tags as they are shown (TagSceneArt).
    --- @type table<string, string>
    sceneArt = {},
}

--- Adds (or replaces) a creator.
--- @param id string
--- @param info {name: string, logo: string, logoWidth: number, logoHeight: number, widthFraction: nil|number, url: nil|string}
function CreatorCredit.Register(id, info)
    CreatorCredit.creators[id] = {
        id = id,
        name = info.name,
        logo = info.logo,
        logoWidth = info.logoWidth,
        logoHeight = info.logoHeight,
        widthFraction = info.widthFraction,
        url = info.url,
    }
end

--- Tags a piece of art (an image or video id) as a creator's work.
--- @param imageid string
--- @param creatorid string
function CreatorCredit.RegisterArt(imageid, creatorid)
    CreatorCredit.art[imageid] = creatorid
end

--- @param id nil|string
--- @return nil|CreatorCreditInfo
function CreatorCredit.Get(id)
    if id == nil then
        return nil
    end
    return CreatorCredit.creators[id]
end

--- Records (or, with nil, clears) the credit a [[scene]] tag's "Art by"
--- setting gives its art. Code that shows a scene calls this as it resolves
--- the scene's image, so anything drawing that image can find the credit
--- with ForArt.
--- @param imageid nil|string
--- @param creatorid nil|string
function CreatorCredit.TagSceneArt(imageid, creatorid)
    if imageid == nil or imageid == "" then
        return
    end
    if creatorid == nil or creatorid == "" or CreatorCredit.creators[creatorid] == nil then
        CreatorCredit.sceneArt[imageid] = nil
    else
        CreatorCredit.sceneArt[imageid] = creatorid
    end
end

--- The creator credited for a piece of art, if it was tagged.
--- @param imageid nil|string
--- @return nil|CreatorCreditInfo
function CreatorCredit.ForArt(imageid)
    if imageid == nil then
        return nil
    end
    return CreatorCredit.Get(CreatorCredit.art[imageid] or CreatorCredit.sceneArt[imageid])
end

--Creator organization id -> its CreatorCreditInfo once built, false when it
--has no logo or the lookup failed, or the callbacks waiting while it loads.
--- @type table<string, CreatorCreditInfo|false|fun(info: nil|CreatorCreditInfo)[]>
local g_orgCredits = {}

--- Calls back with a credit built from a creator organization's own
--- branding (its /ModuleAuthor record: display name and logo), or nil when
--- it has no logo or the lookup fails. The credit is registered as creator
--- "org:<orgid>", so Badge can show it. Its link is the organization's
--- Patreon campaign, else its website. The organizations seen so far
--- (Tehox Maps, 2-Minute Tabletop, MCDM) uploaded white-on-transparent
--- logos, so show the badge with light = true.
--- @param orgid nil|string
--- @param callback fun(info: nil|CreatorCreditInfo)
function CreatorCredit.ForOrganization(orgid, callback)
    if orgid == nil or orgid == "" then
        callback(nil)
        return
    end
    local cached = g_orgCredits[orgid]
    if type(cached) == "table" and cached.id ~= nil then
        callback(cached --[[@as CreatorCreditInfo]])
        return
    end
    if cached == false then
        callback(nil)
        return
    end
    if type(cached) == "table" then
        cached[#cached+1] = callback
        return
    end

    local waiting = { callback }
    g_orgCredits[orgid] = waiting
    local function Finish(info)
        g_orgCredits[orgid] = info or false
        if mod.unloaded then
            return
        end
        for _,fn in ipairs(waiting) do
            fn(info)
        end
    end

    module.GetOrganizationInfo{
        orgid = orgid,
        success = function(org)
            local logo = type(org) == "table" and org.logo or nil
            if type(logo) ~= "string" or logo == "" then
                Finish(nil)
                return
            end
            local name = org.displayName
            if type(name) ~= "string" or name == "" then
                name = orgid
            end
            local url = nil
            if type(org.patreonCampaign) == "table" and type(org.patreonCampaign.url) == "string" and org.patreonCampaign.url ~= "" then
                url = org.patreonCampaign.url
            elseif type(org.url) == "string" and org.url ~= "" then
                url = org.url
            end
            --the badge needs the logo's shape; the lookup wants the bare url.
            local lookup = logo
            if lookup:sub(1, 4) == "md5:" then
                lookup = lookup:sub(5)
            end
            gui.GetImageDimensionsCallback(lookup, function(dims)
                if dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
                    Finish(nil)
                    return
                end
                local id = "org:" .. orgid
                CreatorCredit.Register(id, {
                    name = name,
                    logo = logo,
                    logoWidth = dims.width,
                    logoHeight = dims.height,
                    url = url,
                })
                Finish(CreatorCredit.Get(id))
            end)
        end,
        failure = function()
            Finish(nil)
        end,
    }
end

--- Dropdown options for picking a creator: "None" (id "none") then every
--- registered creator by name.
--- @return {id: string, text: string}[]
function CreatorCredit.DropdownOptions()
    local result = {}
    for id, info in pairs(CreatorCredit.creators) do
        --organization credits (ForOrganization) only exist once looked up.
        if id:sub(1, 4) ~= "org:" then
            result[#result+1] = { id = id, text = info.name }
        end
    end
    table.sort(result, function(a, b) return a.text < b.text end)
    table.insert(result, 1, { id = "none", text = "None" })
    return result
end

--"https://www.czepeku.com/" -> "czepeku.com", for the tooltip.
local function ShortUrl(url)
    local s = url:gsub("^https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    return s
end

local BADGE_STYLES = {
    {
        --full strength: a creator's licence may require the watermark
        --to be plainly visible.
        selectors = { "creatorCreditLogo" },
        opacity = 1,
        transitionTime = 0.15,
    },
    {
        selectors = { "creatorCreditLogo", "parent:hover" },
        opacity = 1,
        scale = 1.05,
    },
}

--- A creator's logo as a badge, by default floating in the bottom-right
--- corner of the panel it is added to. Hovering names the creator; clicking
--- opens their site (through the app's usual confirm-before-opening prompt).
--- Returns nil for an unknown creator, so callers can add it unconditionally.
---
--- A creator registered with widthFraction gets a badge that wide a share of
--- the panel it is added to (options.width and height are ignored), so that
--- panel must be exactly the visible art: the callers cover-fit the art to it.
--- Otherwise the badge is options.width wide (default 170), or, when
--- options.height is given, that tall -- the better fit for logos of mixed
--- shapes, a wide wordmark and a square mark coming out the same height.
---
--- The logo is drawn black by default; pass light = true to show it white,
--- for a badge over dark art. backing = true puts it on a dark translucent
--- plate, for a badge over art of unknown brightness. label is the tooltip's
--- lead-in before the creator's name (default "Art by").
--- @param options {creator: string, width: nil|number, height: nil|number, halign: nil|string, valign: nil|string, hmargin: nil|number, vmargin: nil|number, light: nil|boolean, backing: nil|boolean, label: nil|string}
--- @return nil|Panel
function CreatorCredit.Badge(options)
    local info = CreatorCredit.Get(options.creator)
    if info == nil then
        return nil
    end
    local url = info.url
    local width, height
    if info.widthFraction ~= nil then
        width = string.format("%f%%", 100 * info.widthFraction)
        height = string.format("%f%% width", 100 * info.logoHeight / info.logoWidth)
    elseif options.height ~= nil then
        height = options.height
        width = math.floor(height * info.logoWidth / info.logoHeight + 0.5)
    else
        width = options.width or 170
        height = math.floor(width * info.logoHeight / info.logoWidth + 0.5)
    end

    local tooltip = string.format("%s %s", options.label or "Art by", info.name)
    if url ~= nil then
        tooltip = string.format("%s\nClick to visit %s", tooltip, ShortUrl(url))
    end

    --the plate is padding around the logo, so the logo keeps its size.
    local pad = 0
    if options.backing and type(width) == "number" and type(height) == "number" then
        pad = math.max(6, math.floor(height * 0.2 + 0.5))
        width = width + 2 * pad
        height = height + 2 * pad
    end

    return gui.Panel{
        classes = { "creatorCreditBadge" },
        floating = true,
        halign = options.halign or "right",
        valign = options.valign or "bottom",
        hmargin = options.hmargin or 24,
        vmargin = options.vmargin or 20,
        width = width,
        height = height,
        --a panel with no bgimage is not hit-tested.
        bgimage = "panels/square.png",
        bgcolor = cond(pad > 0, "#000000a0", "clear"),
        cornerRadius = cond(pad > 0, 6, nil),
        pad = pad,
        borderBox = true,
        styles = BADGE_STYLES,
        hoverCursor = cond(url ~= nil, "hand", nil),
        linger = function(element)
            gui.Tooltip(tooltip)(element)
        end,
        click = function(element)
            if url ~= nil then
                dmhub.OpenURL(url)
            end
        end,

        gui.Panel{
            classes = { "creatorCreditLogo" },
            interactable = false,
            width = "100%",
            height = "100%",
            bgimage = info.logo,
            bgcolor = "white",
            --the logo image is white; brightness 0 turns it black.
            brightness = cond(options.light, 1, 0),
        },
    }
end

--- The width a creator's badge takes in a panel boxWidth wide (see Badge), so
--- other controls can be laid out clear of it. 0 for an unknown creator.
--- @param creator nil|string
--- @param boxWidth number
--- @param width nil|number The options.width given to Badge, if any.
--- @return number
function CreatorCredit.BadgeWidth(creator, boxWidth, width)
    local info = CreatorCredit.Get(creator)
    if info == nil then
        return 0
    end
    if info.widthFraction ~= nil then
        return boxWidth * info.widthFraction
    end
    return width or 170
end

--The imageRect that shows an image of aspect imageAspect covering a box of
--boxAspect, cropped around focus (fx, fy) in 0..1 (0.5 = centred).
local function CoverRect(boxAspect, imageAspect, fx, fy)
    local wFrac, hFrac = 1, 1
    if imageAspect > boxAspect then
        wFrac = boxAspect / imageAspect
    else
        hFrac = imageAspect / boxAspect
    end
    local left = (1 - wFrac) * fx
    local top = (1 - hFrac) * fy
    return { x1 = left, x2 = left + wFrac, y1 = 1 - top - hFrac, y2 = 1 - top }
end

local BACKDROP_STYLES = {
    {
        selectors = { "creatorBackdropArt" },
        opacity = 0,
        transitionTime = 0.45,
    },
    {
        selectors = { "creatorBackdropArt", "shown" },
        opacity = 1,
    },
    --drops the art to transparent at once, so ReplayFade can ease it back in.
    {
        selectors = { "creatorBackdropArt", "instant" },
        transitionTime = 0,
    },
}

--- Re-plays a backdrop's fade-in, for a backdrop kept alive and shown again
--- (e.g. un-collapsed) rather than rebuilt.
--- @param backdrop Panel
function CreatorCredit.ReplayFade(backdrop)
    backdrop:FireEventTree("creatorBackdropReplay")
end

--- A full-bleed art backdrop: the art cover-fitted to width x height on black,
--- fading in once it has loaded, with the creator's badge in the bottom-right
--- corner.
---
--- options:
---   width, height  the backdrop's size in the parent's units (required).
---   image          the still (or, with video, its poster).
---   video          optional looping video drawn over the still once it plays.
---   aspect         the art's width / height. Omit to read it from the image.
---   focusX, focusY where to crop around when the aspects differ (0.5 = centre).
---   creator        creator id; defaults to the creator tagged on the video or image.
---   badge          optional overrides for CreatorCredit.Badge, or false for none.
---   children       panels to draw over the art (and under the badge).
--- @param options table
--- @return Panel
function CreatorCredit.Backdrop(options)
    local width = options.width
    local height = options.height
    local boxAspect = width / height
    local fx = options.focusX or 0.5
    local fy = options.focusY or 0.5
    local aspect = options.aspect

    --One art layer: a fresh panel stays invisible until its image has
    --loaded and then fires imageLoaded, which is when it fades in. A video
    --is streamed through its own looping player (the "###LOOP" suffix, as
    --the montage stage plays scenes); a plain bgimage plays it once and then
    --goes blank. A streamed video fires no imageLoaded, so it is scheduled.
    local ArtLayer = function(imageid, isVideo)
        return gui.Panel{
            classes = { "creatorBackdropArt" },
            floating = true,
            halign = "center",
            valign = "center",
            width = width,
            height = height,
            interactable = false,
            bgimage = cond(isVideo, nil, imageid),
            bgcolor = "white",
            data = { loaded = false },
            create = function(element)
                if aspect ~= nil then
                    element.selfStyle.imageRect = CoverRect(boxAspect, aspect, fx, fy)
                end
                if isVideo then
                    element.bgimageStreamed = imageid .. "###LOOP" .. dmhub.GenerateGuid()
                    element:ScheduleEvent("imageLoaded", 0.4)
                end
            end,
            --art that has not loaded yet fades in on imageLoaded anyway.
            creatorBackdropReplay = function(element)
                if not element.data.loaded then
                    return
                end
                element:SetClass("instant", true)
                element:SetClass("shown", false)
                element:ScheduleEvent("creatorBackdropFadeIn", 0.05)
            end,
            creatorBackdropFadeIn = function(element)
                element:SetClass("instant", false)
                element:SetClass("shown", true)
            end,
            imageLoaded = function(element)
                element.data.loaded = true
                if aspect ~= nil then
                    element:SetClass("shown", true)
                    return
                end
                local lookup = imageid
                if lookup:sub(1, 4) == "md5:" then
                    lookup = lookup:sub(5)
                end
                gui.GetImageDimensionsCallback(lookup, function(dims)
                    if mod.unloaded or not element.valid then
                        return
                    end
                    if dims ~= nil and (dims.width or 0) > 0 and (dims.height or 0) > 0 then
                        element.selfStyle.imageRect = CoverRect(boxAspect, dims.width / dims.height, fx, fy)
                    end
                    element:SetClass("shown", true)
                end)
            end,
        }
    end

    local children = {}
    if type(options.image) == "string" and options.image ~= "" then
        children[#children+1] = ArtLayer(options.image)
    end
    if type(options.video) == "string" and options.video ~= "" then
        children[#children+1] = ArtLayer(options.video, true)
    end
    for _,child in ipairs(options.children or {}) do
        children[#children+1] = child
    end

    local info = CreatorCredit.Get(options.creator) or CreatorCredit.ForArt(options.video) or CreatorCredit.ForArt(options.image)
    if info ~= nil and options.badge ~= false then
        local badgeOptions = { creator = info.id }
        if type(options.badge) == "table" then
            for k,v in pairs(options.badge) do
                badgeOptions[k] = v
            end
        end
        children[#children+1] = CreatorCredit.Badge(badgeOptions)
    end

    return gui.Panel{
        classes = { "creatorBackdrop" },
        floating = true,
        halign = "center",
        valign = "center",
        width = width,
        height = height,
        flow = "none",
        --opaque black: what shows until the art fades in, and what keeps
        --whatever is behind the backdrop from showing through.
        bgimage = "panels/square.png",
        bgcolor = "black",
        styles = BACKDROP_STYLES,
        children = children,
    }
end

--- Creators whose art ships with the app. ---------------------------------

--Czepeku's commercial use licence (czepeku.com/blog/commercial-use-licence)
--requires their watermark in the bottom-right corner of the art, at least a
--quarter of its width. The logo is their official white watermark; Badge
--shows it black unless the caller passes light = true (every Encounter of
--the Week scene does). Their black watermark is core image 95efaeaa-...;
--brightness cannot lighten it, so it is not used.
CreatorCredit.Register("czepeku", {
    name = "Czepeku Scenes",
    logo = "a19fa01d-7d92-4e1c-b48a-7b8d8de18c38",
    logoWidth = 1032,
    logoHeight = 101,
    widthFraction = 0.25,
    url = "https://www.czepeku.com",
})
