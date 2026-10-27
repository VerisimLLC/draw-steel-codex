local mod = dmhub.GetModLoading()

--- @class FullscreenDisplay: GameType
--- @field new fun(o?: table): FullscreenDisplay
FullscreenDisplay = RegisterGameType("FullscreenDisplay")

FullscreenDisplay.docid = "fullscreen_display"

--What is on show: the "fullscreen_display" document.
--  show            false, true (the players) or "all" (the Director too)
--  aboveui         drawn over all the game's UI rather than among its windows
--  coverart        the picture: an image asset id (a still or a video)
--  coverartCredit  the "Art by" creator id, or false
--  caption, subtitle   text drawn over the picture, or false
--  sceneid         the Scenes library scene on show (ScenesPanel.lua), or false
--  fit             {image, mode}: mode "contain" shows all of that image, letterboxed; otherwise it fills and crops
--Game Controls, [[scene]] journal tags and maximized tabletop scene windows
--all write it; GameHud mounts one display among the windows (as a maximized
--map stacks) and one over all the UI.

--Is this image asset a video? Videos are streamed through their own looping
--player; a still is a plain bgimage.
function FullscreenDisplay.IsVideo(imageid)
    local video = false
    pcall(function()
        local asset = assets.imagesTable[imageid]
        video = asset ~= nil and asset.isVideo == true
    end)
    return video
end

--- Whether this client sees the display now: the Director only for "all".
--- aboveui (optional) also requires that layer.
--- @param aboveui nil|boolean
--- @return boolean
function FullscreenDisplay.IsShowingHere(aboveui)
    local data = mod:GetDocumentSnapshot(FullscreenDisplay.docid).data
    if data == nil or not data.show then
        return false
    end
    if data.show ~= "all" and dmhub.isDM then
        return false
    end
    if aboveui ~= nil and (data.aboveui == true) ~= aboveui then
        return false
    end
    --a library scene the Director shares with only some players.
    if type(data.sceneid) == "string" and Tabletop.SceneShareExcludesMe(data.sceneid) then
        return false
    end
    return true
end

----------------------------------------------------------------------
--Drawing a scene: FullscreenDisplay.CreateSceneView is the picture with its caption and
--art credit, used by the tabletop's scene windows and the fullscreen
--display. Send it the "showScene" event with {image, caption, subtitle,
--credit} (any may be nil), and "setFit" with "cover" (fill, cropping the
--overflow) or "contain" (all of it, letterboxed).

local g_captionGradient = gui.Gradient{
    point_a = {x = 0.5, y = 0},
    point_b = {x = 0.5, y = 1},
    stops = {
        {position = 0, color = "#000000d0"},
        {position = 0.55, color = "#00000088"},
        {position = 1, color = "#00000000"},
    },
}

--Sizes an art panel inside its parent: cover fills and crops, contain fits
--and letterboxes. aspect is the art's height / width.
local function FitArt(element, aspect, fit)
    local parent = element.parent
    if parent == nil or aspect == nil or aspect <= 0 then
        return
    end
    local w = parent.renderedWidth
    local h = parent.renderedHeight
    if w <= 0 or h <= 0 then
        return
    end
    local tall = (h / w) > aspect
    if (fit == "cover") == tall then
        element.selfStyle.height = "100%"
        element.selfStyle.width = string.format("%f%% height", 100 / aspect)
    else
        element.selfStyle.width = "100%"
        element.selfStyle.height = string.format("%f%% width", 100 * aspect)
    end
end

local function CaptionText(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    return value
end

--- @param options nil|{fit: nil|string, textScale: nil|number, credit: nil|boolean, interactable: nil|boolean}
--- @return Panel
function FullscreenDisplay.CreateSceneView(options)
    options = options or {}
    local textScale = options.textScale or 1
    local m_fit = options.fit or "cover"
    local m_image = nil
    local m_aspect = nil
    --the library scene shown, whose cards (SceneElements.lua) are drawn
    --over the picture, and their layer.
    local m_sceneid = nil
    local m_layer = nil
    local m_background = false
    local root

    local artHolder = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        flow = "none",
        interactable = false,
    }

    --holds the cards' layer, sized to the picture (Refit).
    local layerHolder = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        flow = "none",
    }

    --A scene holding cards always shows its whole picture, so everyone sees
    --every card whatever the shape of their screen (David, 2026-10-17).
    local function EffectiveFit()
        if m_layer ~= nil and m_layer.valid and (m_layer.data.count or 0) > 0 then
            return "contain"
        end
        return m_fit
    end

    --w, h: the view's size when the layout pass that changed it says so
    --("rendered"); otherwise its last rendered size.
    local function Refit(w, h)
        local fit = EffectiveFit()
        for _, art in ipairs(artHolder.children) do
            FitArt(art, m_aspect, fit)
        end
        --the cards' layer covers the picture exactly, as FitArt sizes it.
        if m_layer ~= nil and m_layer.valid and root ~= nil and root.valid then
            if w == nil or h == nil then
                w, h = root.renderedWidth, root.renderedHeight
            end
            if w > 0 and h > 0 then
                local aspect = m_aspect or SceneElements.NO_ART_ASPECT
                local tall = (h / w) > aspect
                if (fit == "cover") == tall then
                    m_layer:FireEvent("setStage", h / aspect, h)
                else
                    m_layer:FireEvent("setStage", w, w * aspect)
                end
            end
        end
    end

    local function SetScene(sceneid)
        if sceneid == m_sceneid then
            return
        end
        m_sceneid = sceneid
        if m_layer ~= nil and m_layer.valid then
            m_layer:DestroySelf()
        end
        m_layer = nil
        if sceneid ~= nil then
            m_layer = SceneElements.CreateLayer(sceneid, {
                onCount = function(count)
                    Refit()
                end,
            })
            m_layer:FireEvent("setBackground", m_background)
            layerHolder.children = {m_layer}
        else
            layerHolder.children = {}
        end
        Refit()
    end

    --a new art panel per picture: a video has to be streamed (its own looping
    --player) and a still is a plain bgimage, and one panel cannot switch back.
    local function SetArt(image)
        if image == m_image then
            return
        end
        m_image = image
        m_aspect = nil
        if image == nil then
            artHolder.children = {}
            return
        end
        local video = FullscreenDisplay.IsVideo(image)
        local art = gui.Panel{
            halign = "center",
            valign = "center",
            width = "100%",
            height = "100%",
            bgcolor = "white",
            bgimage = cond(video, nil, image),
            interactable = false,
            create = function(element)
                if video then
                    element.bgimageStreamed = image .. "###LOOP" .. dmhub.GenerateGuid()
                end
                --a streamed video fires no imageLoaded, and a cached still may
                --not either.
                element:ScheduleEvent("imageLoaded", 0.1)
                element:ScheduleEvent("imageLoaded", 0.6)
            end,
            imageLoaded = function(element)
                if element.bgsprite ~= nil then
                    m_aspect = element.bgsprite.dimensions.y / element.bgsprite.dimensions.x
                    Refit()
                    return
                end
                pcall(function()
                    gui.GetImageDimensionsCallback(image, function(dims)
                        if mod.unloaded or not element.valid or m_image ~= image then
                            return
                        end
                        if dims ~= nil and (dims.width or 0) > 0 and (dims.height or 0) > 0 then
                            m_aspect = dims.height / dims.width
                            Refit()
                        end
                    end)
                end)
            end,
        }
        artHolder.children = {art}
    end

    local captionLabel = gui.Label{
        width = "90%",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        fontSize = math.floor(44 * textScale),
        bold = true,
        color = "#f4efe4",
        text = "",
        interactable = false,
    }
    local subtitleLabel = gui.Label{
        width = "90%",
        height = "auto",
        halign = "center",
        textAlignment = "center",
        fontSize = math.floor(22 * textScale),
        italics = true,
        color = "#d8d0c2",
        tmargin = math.floor(4 * textScale),
        text = "",
        interactable = false,
    }
    local captionBand = gui.Panel{
        classes = {"collapsed"},
        floating = true,
        width = "100%",
        height = "auto",
        valign = "bottom",
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = "white",
        gradient = g_captionGradient,
        tpad = math.floor(48 * textScale),
        bpad = math.floor(36 * textScale),
        borderBox = true,
        interactable = false,
        captionLabel,
        subtitleLabel,
    }

    --the "Art by" creator's badge (CreatorCredit.lua).
    local creditHolder = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        flow = "none",
        interactable = false,
        data = {creator = nil},
    }
    local function SetCredit(creator)
        if options.credit == false or creator == creditHolder.data.creator then
            return
        end
        creditHolder.data.creator = creator
        local badge = nil
        if creator ~= nil then
            badge = CreatorCredit.Badge{creator = creator}
        end
        creditHolder.children = {badge}
    end

    root = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "none",
        --clip needs an image and a colour that is not fully clear.
        bgimage = "panels/square.png",
        bgcolor = "#0b0907ff",
        clip = true,
        interactable = options.interactable == true,
        data = {w = 0, h = 0},
        artHolder,
        captionBand,
        creditHolder,
        layerHolder,

        --info.sceneid: a library scene, whose cards are drawn over it.
        showScene = function(element, info)
            info = info or {}
            SetArt(CaptionText(info.image))
            local sceneid = info.sceneid
            if type(sceneid) ~= "string" or sceneid == "" then
                sceneid = nil
            end
            SetScene(sceneid)
            local caption = CaptionText(info.caption)
            local subtitle = CaptionText(info.subtitle)
            captionLabel.text = caption or ""
            subtitleLabel.text = subtitle or ""
            captionLabel:SetClass("collapsed", caption == nil)
            subtitleLabel:SetClass("collapsed", subtitle == nil)
            captionBand:SetClass("collapsed", caption == nil and subtitle == nil)

            local creator = nil
            if type(info.credit) == "string" and CreatorCredit.Get(info.credit) ~= nil then
                creator = info.credit
            elseif m_image ~= nil then
                local credited = CreatorCredit.ForArt(m_image)
                creator = credited ~= nil and credited.id or nil
            end
            SetCredit(creator)
        end,

        setFit = function(element, fit)
            if fit ~= m_fit then
                m_fit = fit
                Refit()
            end
        end,

        --the view is the table's background (a maximized scene under the
        --UI): its cards' layer lets the mouse through (SceneElements.lua).
        setBackground = function(element, background)
            background = background == true
            if background ~= m_background then
                m_background = background
                if m_layer ~= nil and m_layer.valid then
                    m_layer:FireEvent("setBackground", background)
                end
            end
        end,

        --windows resize: refit in the layout pass that resized the view, so
        --the cards resize with the picture rather than a frame behind it.
        rendered = function(element, width, height)
            if width ~= element.data.w or height ~= element.data.h then
                element.data.w = width
                element.data.h = height
                Refit(width, height)
            end
        end,

        --(a fallback for a size change that fires no "rendered".)
        thinkTime = 0.2,
        think = function(element)
            local w, h = element.renderedWidth, element.renderedHeight
            if w ~= element.data.w or h ~= element.data.h then
                element.data.w = w
                element.data.h = h
                Refit()
            end
        end,
    }
    return root
end

--The title bar's presentation control (UpdatePresentationBar below) and what
--it last showed, so it is only rebuilt when that changes.
local PRESENTATION_ID = "fullscreen_display"
local g_presentationSignature = nil

--options.aboveui: the display over all the UI (GameHud mounts it near the top
--of the hud). Otherwise it goes in the documents layer and stacks as a
--maximized map does: it comes up over the maps, scenes and journals when it
--goes on show, and the icon rails and their panel windows stay over it.
function FullscreenDisplay.Create(options)
    local aboveui = options.aboveui or false
    --a new hud: the title bar's control is put back on the next refresh.
    g_presentationSignature = nil
    local doc = mod:GetDocumentSnapshot(FullscreenDisplay.docid)
    --interactable: while shown it takes the clicks, as the full-screen art always has.
    local view = FullscreenDisplay.CreateSceneView{fit = "cover", interactable = true}

    --the table's shares decide which players see a library scene, so a
    --change to them refreshes the display too.
    local shareMonitor = gui.Panel{
        floating = true,
        width = 0,
        height = 0,
        interactable = false,
        monitorGame = Tabletop.ShareDocPath(),
        refreshGame = function(element)
            if element.parent ~= nil then
                element.parent:FireEvent("refreshGame")
            end
        end,
    }

    local panel = gui.Panel{
        classes = {"hidden", cond(aboveui, "aboveui", "belowui")},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        --among the windows: a press on it brings it back over them.
        raiseOnPress = not aboveui,
        data = {shown = nil},
        view,
        shareMonitor,

        monitorGame = doc.path,

        refreshGame = function(element)
            local data = mod:GetDocumentSnapshot(FullscreenDisplay.docid).data or {}
            local hide = not FullscreenDisplay.IsShowingHere(aboveui)
            element:SetClass("hidden", hide)
            --going on show, or a new picture on show, brings it up over the
            --windows; after that they stack by click order.
            local shown = nil
            if not hide then
                shown = tostring(data.sceneid) .. "|" .. tostring(data.coverart)
            end
            if shown ~= element.data.shown and (aboveui or element.parent ~= nil) then
                element.data.shown = shown
                if shown ~= nil and not aboveui then
                    element:SetAsLastSibling()
                end
            end
            if not hide then
                local fit = "cover"
                if type(data.fit) == "table" and data.fit.image == data.coverart and data.fit.mode == "contain" then
                    fit = "contain"
                end
                view:FireEvent("setFit", fit)
                view:FireEvent("showScene", {
                    image = data.coverart,
                    caption = data.caption,
                    subtitle = data.subtitle,
                    credit = data.coverartCredit,
                    sceneid = data.sceneid,
                })
            end
            FullscreenDisplay.UpdatePresentationBar()
        end,
    }
    if not aboveui then
        --as a maximized map: under the rails and their panel windows, and
        --under any dialog that was over it when it is raised.
        panel.raiseBelowClasses = PanelDocument.ABOVE_MAP_WINDOWS
        panel.raiseUnderNonWindows = true
    end
    return panel
end

--The Director's control in the title bar: Hide / Players / All and Above UI,
--for whatever is on show. A maximized tabletop scene window has its own
--(Players / All) in its strip under the title bar (Tabletop.lua), so while
--there is one the bar shows none.
local function WriteDisplay(description, fn)
    local doc = mod:GetDocumentSnapshot(FullscreenDisplay.docid)
    doc:BeginChange()
    fn(doc.data)
    doc:CompleteChange(description)
end

function FullscreenDisplay.UpdatePresentationBar()
    local data = mod:GetDocumentSnapshot(FullscreenDisplay.docid).data or {}
    local scenes = rawget(_G, "Scenes")

    local value = nil
    if dmhub.isDM and data.show and Tabletop.MaximizedSceneId() == nil then
        value = data.show
    end

    local aboveui = data.aboveui == true
    local signature = nil
    if value ~= nil then
        signature = string.format("%s|%s", tostring(value), tostring(aboveui))
    end
    if signature == g_presentationSignature then
        return
    end
    g_presentationSignature = signature

    if signature == nil then
        TopBar.ClearPresentationInfo(PRESENTATION_ID)
        return
    end

    TopBar.SetPresentationInfo{
        id = PRESENTATION_ID,
        text = "Show Scene",
        value = value,
        options = {
            {id = false, text = "Hide"},
            {id = true, text = "Players"},
            {id = "all", text = "All"},
        },
        onchange = function(newValue)
            local current = mod:GetDocumentSnapshot(FullscreenDisplay.docid).data
            if scenes ~= nil and type(current.sceneid) == "string" then
                --a library scene: its sound cue follows it.
                scenes.Present(current.sceneid, newValue)
                return
            end
            WriteDisplay("Show Fullscreen Display", function(d)
                d.show = newValue
            end)
        end,
        aboveui = aboveui,
        onaboveui = function(newValue)
            WriteDisplay("Show Above UI", function(d)
                d.aboveui = newValue == true
            end)
        end,
    }
end

function FullscreenDisplay.GetDocumentSnapshot()
	local doc = mod:GetDocumentSnapshot(FullscreenDisplay.docid)
    return doc
end

----------------------------------------------------------------------
-- DramaticBanner
--
-- A transient, full-screen "hero moment" banner built around a single
-- token. The screen dims and an opaque band irises open across the
-- middle of the screen. Two crossed swords sit over the centre of the
-- band and sweep apart, drawing back to reveal the token's portrait
-- and the title text between them. After a fixed hold the whole thing
-- reverses out.
--
-- The sword-reveal animation and its sound are modelled on the
-- "Draw Steel" initiative banner (Draw Steel UI/DSInitiativeRoll.lua).
--
-- That is the "heroic" banner type. The "malice" type is a lighter
-- cousin for when the Director spends malice: a much shorter,
-- translucent band that shimmers over the map, with no swords -- the
-- malice icon sits beside the title instead -- and the content fading
-- in rather than being wiped open. Types are listed in
-- DramaticBanner.types.
--
-- It is NOT a modal: the overlay never captures input, so play
-- continues underneath it. Trigger one from anywhere with:
--
--     DramaticBanner.Show{ tokenid = tok.id, text = "Lord Syriax", subtitle = "The Pale Tyrant" }
--     DramaticBanner.Show{ tokenid = tok.id, text = "Malice: Dark Bargain", bannerType = "malice" }
--
-- State is held in a synced document, so every client in the game sees
-- the banner at the same moment. The panel is created once and mounted
-- at the top-most overlay layer of the game HUD.
----------------------------------------------------------------------

--- @class DramaticBanner: GameType
--- @field new fun(o?: table): DramaticBanner
DramaticBanner = RegisterGameType("DramaticBanner")

DramaticBanner.docid = "dramatic_banner"

-- Seconds the banner holds fully on screen between its entrance and exit.
DramaticBanner.holdTime = 3.2

-- Sound played as the banner enters (matches the Draw Steel initiative
-- banner). Used whenever DramaticBanner.Show is not given its own sound.
DramaticBanner.defaultSound = "UI.DrawSteel"

-- Accent colour used when the token has no vivid colour of its own
-- (monsters and unowned tokens report a near-white playerColor).
DramaticBanner.fallbackAccent = "#e8c264"

-- The malice red used by the ability cost diamond (see
-- ActivatedAbility.actionColorKey), so malice banners match the icon.
DramaticBanner.maliceAccent = "#DE1E47"

-- The kinds of banner. Every banner shown before types existed is a
-- "heroic" banner: the full-height opaque band with the crossed swords.
-- A "malice" banner is a short, translucent band that shimmers over the
-- map, with the malice icon beside the title in place of the swords.
-- Ordered for the editor dropdown; the first entry is the default.
DramaticBanner.defaultType = "heroic"
DramaticBanner.types = {
    { id = "heroic", text = "Heroic", sound = DramaticBanner.defaultSound },
    { id = "malice", text = "Malice", sound = "Notify.Malice_Use" },
}

--- The entry in DramaticBanner.types for a type id, falling back to the
--- default type for nil or unknown ids (banners from older documents).
--- @param id nil|string
--- @return {id: string, text: string, sound: string}
function DramaticBanner.GetTypeInfo(id)
    for _,info in ipairs(DramaticBanner.types) do
        if info.id == id then
            return info
        end
    end
    return DramaticBanner.types[1]
end

-- Subtle vertical sheen for the opaque heroic banner band (opaque
-- throughout). Kept as a plain style table so playBanner can swap it in
-- and out of the band's selfStyle per banner type.
local g_dramaticBandGradientStyle = {
    point_a = {x = 0.5, y = 0},
    point_b = {x = 0.5, y = 1},
    stops = {
        {position = 0,   color = "#07070bff"},
        {position = 0.5, color = "#181820ff"},
        {position = 1,   color = "#07070bff"},
    },
}

-- The malice band: a dark, red-tinged wash that is translucent across
-- its body and fades out entirely at its top and bottom edges, so it
-- reads as a shimmer over the map rather than a solid strip.
local g_maliceBandGradientStyle = {
    point_a = {x = 0.5, y = 0},
    point_b = {x = 0.5, y = 1},
    stops = {
        {position = 0,    color = "#16050a00"},
        {position = 0.18, color = "#16050aad"},
        {position = 0.5,  color = "#24080fc1"},
        {position = 0.82, color = "#16050aad"},
        {position = 1,    color = "#16050a00"},
    },
}

-- The two reveal covers are band-coloured panels that hide the content
-- until the swords draw them apart. Each is opaque across its body and
-- fades to transparent at its inner edge, so the wipe is soft and the
-- cover blends seamlessly into the band. One gradient per side (the
-- left cover fades on its right edge, the right cover on its left).
local g_dramaticCoverGradientLeft = gui.Gradient{
    point_a = {x = 0},
    point_b = {x = 1},
    stops = {
        {position = 0,   color = "#181820ff"},
        {position = 0.8, color = "#181820ff"},
        {position = 1,   color = "#18182000"},
    },
}
local g_dramaticCoverGradientRight = gui.Gradient{
    point_a = {x = 0},
    point_b = {x = 1},
    stops = {
        {position = 0,   color = "#18182000"},
        {position = 0.2, color = "#181820ff"},
        {position = 1,   color = "#181820ff"},
    },
}

function DramaticBanner.GetDocumentSnapshot()
    return mod:GetDocumentSnapshot(DramaticBanner.docid)
end

--- Show a dramatic banner, centred on a token, to every client in the game.
--- bannerType is an id from DramaticBanner.types ("heroic" when omitted);
--- the sound defaults to that type's sound.
--- @param args {tokenid: nil|string, text: string, subtitle: nil|string, sound: nil|string, bannerType: nil|string}
function DramaticBanner.Show(args)
    local typeInfo = DramaticBanner.GetTypeInfo(args.bannerType)
    local doc = mod:GetDocumentSnapshot(DramaticBanner.docid)
    doc:BeginChange()
    -- A fresh triggerId is what makes each call replay the animation,
    -- even when the content is identical to the previous banner.
    doc.data.triggerId = dmhub.GenerateGuid()
    doc.data.tokenid = args.tokenid
    doc.data.text = args.text or ""
    doc.data.subtitle = args.subtitle
    doc.data.bannerType = typeInfo.id
    doc.data.sound = args.sound or typeInfo.sound
    doc:CompleteChange("Show dramatic banner", {undoable = false})

    -- Record when this banner will have fully cleared the screen: the
    -- fixed hold, then the exit tail (dismiss schedules hideElements
    -- 0.5s later, after which the dim fades out over ~0.25s). A small
    -- buffer covers document propagation. Callers such as ability
    -- behaviors poll TimeUntilDone() to wait for the banner.
    DramaticBanner.displayUntil = dmhub.Time() + DramaticBanner.holdTime + 0.8
end

-- Seconds until the most recently shown banner has fully animated off
-- the screen. Returns <= 0 when no banner is (or has been) showing.
function DramaticBanner.TimeUntilDone()
    local t = DramaticBanner.displayUntil
    if t == nil then
        return 0
    end
    return t - dmhub.Time()
end

-- Resolves a token into (opaque, transparent) accent colour strings.
-- Uses the token's player colour when it is vivid enough, otherwise a
-- dramatic gold fallback.
local function ResolveBannerAccent(token)
    local c = nil
    if token ~= nil then
        c = token.playerColor
    end
    if c == nil or c.s < 0.18 then
        return DramaticBanner.fallbackAccent .. "ff", DramaticBanner.fallbackAccent .. "00"
    end
    local vivid = c:Modify{ s = math.max(c.s, 0.6), v = math.max(c.v, 0.95), a = 1 }
    return vivid.tostring, vivid:Modify{ a = 0 }.tostring
end

-- Creates the banner overlay panel. Mounted once by the game HUD.
function DramaticBanner.Create()
    local doc = mod:GetDocumentSnapshot(DramaticBanner.docid)

    -- How far each sword sits from centre when fully drawn apart.
    local swordOpenOffset = 710

    ------------------------------------------------------------------
    -- Backdrop: full-screen dim + the opaque band across the middle.
    -- Each animated element carries exactly one of a pair of mutually
    -- exclusive classes, so there is never a style-specificity tie.
    ------------------------------------------------------------------
    local dimPanel = gui.Panel{
        classes = {"dim-out"},
        interactable = false,
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = "black",
        styles = {
            { classes = {"dim-out"}, opacity = 0, transitionTime = 0.25 },
            -- Per-type "in" classes (one is set per banner): the heroic
            -- banner dims the whole screen hard; the malice banner only
            -- darkens it a touch so the map stays readable through the
            -- translucent band.
            { classes = {"dim-in-heroic"}, opacity = 0.62, transitionTime = 0.4 },
            { classes = {"dim-in-malice"}, opacity = 0.22, transitionTime = 0.4 },
        },
    }

    -- Band that irises open vertically from the centre line. Opaque and
    -- tall for the heroic banner; short and translucent for malice (the
    -- gradient is swapped per banner in playBanner).
    local bandPanel = gui.Panel{
        classes = {"band-out"},
        interactable = false,
        width = "100%",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "white",
        gradient = g_dramaticBandGradientStyle,
        styles = {
            { classes = {"band-out"},       height = 0,   transitionTime = 0.1 },
            { classes = {"band-in-heroic"}, height = 450, transitionTime = 0.1 },
            -- Tall enough for a readable portrait (which fills the band
            -- height), while still well short of the heroic band.
            { classes = {"band-in-malice"}, height = 290, transitionTime = 0.1 },
        },
    }

    -- The content elements below carry exactly one of these classes. The
    -- heroic banner snaps them visible (the covers do the revealing); the
    -- malice banner has no covers, so it fades them in and out instead.
    -- Opacity does not cascade, hence one set per element rather than on
    -- their shared parent.
    --
    -- The "-now" variants snap with no transition. playBanner must use
    -- them to set the starting state: a timed fade started there would
    -- still be mid-flight when the reveal layer un-hides 0.12s later,
    -- which showed as a one-frame flicker on the first banner of a
    -- session (the elements start life visible, so the first malice
    -- banner's fade-out was caught partway).
    local contentFadeStyles = {
        { classes = {"content-out"},     opacity = 0, transitionTime = 0.4 },
        { classes = {"content-in"},      opacity = 1, transitionTime = 0.4 },
        { classes = {"content-out-now"}, opacity = 0, transitionTime = 0 },
        { classes = {"content-in-now"},  opacity = 1, transitionTime = 0 },
    }
    local contentFadeClasses = {"content-out", "content-in", "content-out-now", "content-in-now"}

    ------------------------------------------------------------------
    -- Content revealed between the swords: the token portrait and the
    -- title / subtitle text.
    ------------------------------------------------------------------
    -- Portrait fills the band vertically (minus 16px) at the standard portrait
    -- aspect (width = portraitWidthPercentOfHeight% of height, i.e. 3:4), and
    -- crops its image to that aspect via imageRect in playBanner -- exactly the
    -- recipe the character panel's portrait-body uses -- so it is never
    -- stretched. Its edges fade out so it blends softly into the band.
    local portraitPanel = gui.Panel{
        classes = {"content-out-now"},
        interactable = false,
        height = "100%-16",
        width = string.format("%f%% height", Styles.portraitWidthPercentOfHeight),
        halign = "center",
        valign = "center",
        bgcolor = "white",
        edgeFade = 0.1,
        styles = contentFadeStyles,
    }

    -- The malice icon, shown beside the title in place of the swords on
    -- malice banners only. The png is a white mask, tinted malice red.
    local maliceIcon = gui.Panel{
        classes = {"content-out-now", "collapsed"},
        interactable = false,
        width = 96,
        height = 96,
        valign = "center",
        lmargin = 30,
        bgimage = "panels/malice.png",
        bgcolor = DramaticBanner.maliceAccent,
        styles = contentFadeStyles,
    }

    local titleLabel = gui.Label{
        classes = {"content-out-now"},
        interactable = false,
        text = "",
        width = "100%",
        height = "auto",
        textAlignment = "left",
        textWrap = false,
        fontFace = "Book",
        fontSize = 36,
        fontWeight = "black",
        color = "white",
        styles = contentFadeStyles,
    }

    local accentRule = gui.Panel{
        classes = {"content-out-now"},
        interactable = false,
        width = "100%",
        height = 4,
        halign = "left",
        vmargin = 10,
        bgimage = "panels/square.png",
        bgcolor = "white",
        styles = contentFadeStyles,
    }

    local subtitleLabel = gui.Label{
        classes = {"content-out-now"},
        interactable = false,
        text = "",
        width = "100%",
        height = "auto",
        textAlignment = "left",
        textWrap = true,
        fontFace = "Book",
        fontSize = 21,
        uppercase = true,
        color = "white",
        styles = contentFadeStyles,
    }

    -- Every element the malice banner fades rather than wipes. `instant`
    -- snaps to the state instead of transitioning to it.
    local fadingContent = { portraitPanel, maliceIcon, titleLabel, accentRule, subtitleLabel }
    local function SetContentVisible(visible, instant)
        local target = cond(visible, "content-in", "content-out") .. cond(instant, "-now", "")
        for _,el in ipairs(fadingContent) do
            for _,cls in ipairs(contentFadeClasses) do
                el:SetClass(cls, cls == target)
            end
        end
    end

    local textColumn = gui.Panel{
        interactable = false,
        width = 560,
        height = "auto",
        valign = "center",
        lmargin = 50,
        flow = "vertical",
        children = { titleLabel, accentRule, subtitleLabel },
    }

    -- Portrait + text, revealed between the parting swords. Height is fixed to
    -- the reveal layer so the portrait's "100%-16" height resolves against the
    -- band rather than collapsing against an auto-height parent.
    local contentGroup = gui.Panel{
        interactable = false,
        width = "auto",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "horizontal",
        children = { portraitPanel, maliceIcon, textColumn },
    }

    ------------------------------------------------------------------
    -- The two swords. They rest crossed at the centre and sweep apart
    -- to reveal the content. The right sword mirrors the left.
    ------------------------------------------------------------------
    local function MakeSword(isLeft)
        local closedClass = cond(isLeft, "lsw-closed", "rsw-closed")
        local openClass = cond(isLeft, "lsw-open", "rsw-open")
        local openX = cond(isLeft, -swordOpenOffset, swordOpenOffset)
        return gui.Panel{
            classes = {closedClass},
            interactable = false,
            width = 440,
            height = "50% width",
            halign = "center",
            valign = "center",
            bgimage = "panels/initiative/drawsteel-sword.png",
            bgcolor = "white",
            scale = cond(isLeft, nil, {x = -1, y = 1}),
            styles = {
                -- easeInBack winds the swords/covers back out slightly
                -- before they slam home.
                { classes = {closedClass}, x = 0, transitionTime = 0.45, easing = "EaseInBack" },
                { classes = {openClass},   x = openX, transitionTime = 0.6, easing = "EaseOutCubic" },
            },
        }
    end
    local leftSword = MakeSword(true)
    local rightSword = MakeSword(false)

    ------------------------------------------------------------------
    -- The two reveal covers. They sit above the content but below the
    -- swords. Closed, they meet at the centre and fully hide the
    -- portrait + text; they slide apart in lockstep with the swords,
    -- wiping away to reveal the content.
    ------------------------------------------------------------------
    local coverOpenOffset = 760

    local function MakeCover(isLeft)
        local closedClass = cond(isLeft, "lcv-closed", "rcv-closed")
        local openClass = cond(isLeft, "lcv-open", "rcv-open")
        local openX = cond(isLeft, -coverOpenOffset, coverOpenOffset)
        return gui.Panel{
            classes = {closedClass},
            interactable = false,
            width = 1200,
            height = "100%",
            halign = cond(isLeft, "left", "right"),
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = "white",
            gradient = cond(isLeft, g_dramaticCoverGradientLeft, g_dramaticCoverGradientRight),
            styles = {
                -- easeInBack winds the swords/covers back out slightly
                -- before they slam home.
                { classes = {closedClass}, x = 0, transitionTime = 0.45, easing = "EaseInBack" },
                { classes = {openClass},   x = openX, transitionTime = 0.6, easing = "EaseOutCubic" },
            },
        }
    end
    local leftCover = MakeCover(true)
    local rightCover = MakeCover(false)

    -- Holds the content, covers and swords. The built-in "hidden" class
    -- gates the whole reveal -- unlike opacity, hidden cascades to every
    -- child -- so it all stays invisible between banners. Child order is
    -- the draw order: content at the back, covers over it, swords on top.
    local revealLayer = gui.Panel{
        classes = {"hidden", "reveal-heroic"},
        flow = "none",
        interactable = false,
        width = "100%",
        halign = "center",
        valign = "center",
        children = { contentGroup, leftCover, rightCover, leftSword, rightSword },
        styles = {
            -- Slightly taller than the band of each type, so the content
            -- (whose height resolves against this layer) can overhang it.
            { classes = {"reveal-heroic"}, height = 460 },
            { classes = {"reveal-malice"}, height = 300 },
        },
    }

    -- Elements only the heroic banner uses: the swords and the covers.
    local heroicOnly = { leftSword, rightSword, leftCover, rightCover }

    ------------------------------------------------------------------
    -- Root overlay + animation control.
    ------------------------------------------------------------------
    return gui.Panel{
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "none",
        interactable = false,

        data = {
            -- Bumped on every banner; lets a stale scheduled callback
            -- recognise that a newer banner has superseded it.
            generation = 0,
            -- Seeded with the current triggerId so an already-shown
            -- banner is not replayed when a client joins or reloads.
            lastTriggerId = doc.data and doc.data.triggerId,
        },

        monitorGame = doc.path,

        children = { dimPanel, bandPanel, revealLayer },

        refreshGame = function(element)
            local d = mod:GetDocumentSnapshot(DramaticBanner.docid)
            if d.data == nil or d.data.triggerId == nil then
                return
            end
            if d.data.triggerId == element.data.lastTriggerId then
                return
            end
            element.data.lastTriggerId = d.data.triggerId
            element:FireEvent("playBanner")
        end,

        playBanner = function(element)
            local d = mod:GetDocumentSnapshot(DramaticBanner.docid)
            if d.data == nil then
                return
            end

            local token = nil
            if d.data.tokenid then
                --off the map too (a hero in the EotW town is never spawned)
                token = dmhub.GetTokenById(d.data.tokenid) or dmhub.GetCharacterById(d.data.tokenid)
            end
            local hasPortrait = token ~= nil

            -- Which kind of banner this is. Documents written before
            -- banner types existed have no bannerType and are heroic.
            local isMalice = DramaticBanner.GetTypeInfo(d.data.bannerType).id == "malice"
            element.data.isMalice = isMalice

            -- Malice banners are always in malice red; heroic banners
            -- take the token's colour.
            local accent, accentClear
            if isMalice then
                accent, accentClear = DramaticBanner.maliceAccent .. "ff", DramaticBanner.maliceAccent .. "00"
            else
                accent, accentClear = ResolveBannerAccent(token)
            end

            -- Title / subtitle content. Text sits beside the portrait or
            -- the malice icon when there is one, otherwise it is centred
            -- on the band. The short malice band gets smaller type.
            local hasLead = hasPortrait or isMalice
            titleLabel.text = d.data.text or ""
            titleLabel.textAlignment = cond(hasLead, "left", "center")
            titleLabel.selfStyle.fontSize = cond(isMalice, 30, 36)
            textColumn.lmargin = cond(hasLead, cond(isMalice, 30, 50), 0)
            local subtitle = d.data.subtitle
            subtitleLabel.text = subtitle or ""
            subtitleLabel.textAlignment = cond(hasLead, "left", "center")
            subtitleLabel.selfStyle.fontSize = cond(isMalice, 17, 21)
            subtitleLabel.color = accent
            subtitleLabel:SetClass("collapsed", subtitle == nil or subtitle == "")
            accentRule.vmargin = cond(isMalice, 6, 10)

            -- The malice icon stands in for the swords beside the title.
            maliceIcon:SetClass("collapsed", not isMalice)
            for _,el in ipairs(heroicOnly) do
                el:SetClass("collapsed", isMalice)
            end

            -- Band: tall and opaque, or short and translucent.
            bandPanel.selfStyle.gradient = cond(isMalice, g_maliceBandGradientStyle, g_dramaticBandGradientStyle)
            revealLayer:SetClass("reveal-heroic", not isMalice)
            revealLayer:SetClass("reveal-malice", isMalice)

            -- Accent rule in the token colour, faded at both ends.
            accentRule.selfStyle = {
                bgcolor = "white",
                gradient = {
                    point_a = {x = 0},
                    point_b = {x = 1},
                    stops = {
                        {position = 0,   color = accentClear},
                        {position = 0.5, color = accent},
                        {position = 1,   color = accentClear},
                    },
                },
            }

            -- Portrait, skipped entirely when no token was supplied or
            -- it is off-map.
            portraitPanel:SetClass("collapsed", not hasPortrait)
            if hasPortrait then
                -- Same logic as the character panel's portrait-body: crop the
                -- image to the portrait aspect via imageRect so it fills the
                -- frame without stretching. Spine portraits frame themselves
                -- (inspectPortrait returns a live '#spineinspect:' render), so
                -- they are shown un-cropped.
                --hasPortrait is token ~= nil.
                ---@cast token -nil
                local portrait = token.inspectPortrait
                portraitPanel.bgimage = portrait
                local rect = nil
                if not token.hasSpineAnimation then
                    rect = token:GetPortraitRectForAspect(Styles.portraitWidthPercentOfHeight*0.01, portrait)
                end
                portraitPanel.selfStyle.imageRect = rect

                -- The malice portrait sits on a translucent band, so it is
                -- vignetted into it with a radial gradient. The shader
                -- samples gradients (and edgeFade) in image-rect space, not
                -- panel space, so the gradient is anchored to the crop rect:
                -- centred on it, with the fade reaching 100% at its top and
                -- bottom edges. The sides (3:4, so nearer the centre) fade
                -- partway and the corners vanish completely.
                if isMalice then
                    local x1, y1, x2, y2 = 0, 0, 1, 1
                    if rect ~= nil then
                        x1, y1, x2, y2 = rect.x1, rect.y1, rect.x2, rect.y2
                    end
                    local cx, cy = (x1 + x2) * 0.5, (y1 + y2) * 0.5
                    portraitPanel.selfStyle.edgeFade = 0
                    portraitPanel.selfStyle.gradient = {
                        type = "radial",
                        point_a = {x = cx, y = cy},
                        point_b = {x = cx, y = y2},
                        stops = {
                            {position = 0,    color = "#ffffffff"},
                            {position = 0.45, color = "#ffffffff"},
                            {position = 1,    color = "#ffffff00"},
                        },
                    }
                else
                    portraitPanel.selfStyle.edgeFade = 0.1
                    portraitPanel.selfStyle.gradient = nil
                end
            end

            if d.data.sound then
                audio.FireSoundEvent(d.data.sound)
            end

            element.data.generation = element.data.generation + 1
            local g = element.data.generation

            -- The band irises open fast; the swords and content are
            -- held back (revealLayer stays hidden) until it has arrived.
            dimPanel:SetClass("dim-out", false)
            dimPanel:SetClass("dim-in-heroic", not isMalice)
            dimPanel:SetClass("dim-in-malice", isMalice)
            bandPanel:SetClass("band-out", false)
            bandPanel:SetClass("band-in-heroic", not isMalice)
            bandPanel:SetClass("band-in-malice", isMalice)
            -- Heroic content starts visible behind its covers; malice
            -- content starts faded out and fades in with the "curtains".
            -- Snap, never fade, here: see contentFadeStyles.
            SetContentVisible(not isMalice, true)
            leftSword:SetClass("lsw-open", false)
            leftSword:SetClass("lsw-closed", true)
            rightSword:SetClass("rsw-open", false)
            rightSword:SetClass("rsw-closed", true)
            leftCover:SetClass("lcv-open", false)
            leftCover:SetClass("lcv-closed", true)
            rightCover:SetClass("rcv-open", false)
            rightCover:SetClass("rcv-closed", true)

            element:ScheduleEvent("revealElements", 0.12, g)
            element:ScheduleEvent("dismissBanner", DramaticBanner.holdTime, g)
        end,

        -- The band has arrived: show the crossed swords + covered content.
        revealElements = function(element, g)
            if g ~= element.data.generation then
                return
            end
            revealLayer:SetClass("hidden", false)
            -- Part the swords + covers one frame later so the sweep
            -- animates from a visible, closed state.
            element:ScheduleEvent("openCurtains", 0.06, g)
        end,

        -- Swords and covers sweep apart, wiping away to reveal the
        -- portrait and text. (Malice: the content simply fades in; its
        -- swords and covers are collapsed, so their classes are moot.)
        openCurtains = function(element, g)
            if g ~= element.data.generation then
                return
            end
            if element.data.isMalice then
                SetContentVisible(true)
            end
            leftSword:SetClass("lsw-closed", false)
            leftSword:SetClass("lsw-open", true)
            rightSword:SetClass("rsw-closed", false)
            rightSword:SetClass("rsw-open", true)
            leftCover:SetClass("lcv-closed", false)
            leftCover:SetClass("lcv-open", true)
            rightCover:SetClass("rcv-closed", false)
            rightCover:SetClass("rcv-open", true)
        end,

        -- Exit: the elements leave first -- the swords and covers sweep
        -- back together -- and only then does the band snap shut.
        dismissBanner = function(element, g)
            if g ~= element.data.generation then
                return
            end
            if element.data.isMalice then
                SetContentVisible(false)
            end
            leftSword:SetClass("lsw-open", false)
            leftSword:SetClass("lsw-closed", true)
            rightSword:SetClass("rsw-open", false)
            rightSword:SetClass("rsw-closed", true)
            leftCover:SetClass("lcv-open", false)
            leftCover:SetClass("lcv-closed", true)
            rightCover:SetClass("rcv-open", false)
            rightCover:SetClass("rcv-closed", true)
            element:ScheduleEvent("hideElements", 0.5, g)
        end,

        -- The swords have closed: hide them, then snap the band and
        -- the dim away fast.
        hideElements = function(element, g)
            if g ~= element.data.generation then
                return
            end
            revealLayer:SetClass("hidden", true)
            bandPanel:SetClass("band-in-heroic", false)
            bandPanel:SetClass("band-in-malice", false)
            bandPanel:SetClass("band-out", true)
            dimPanel:SetClass("dim-in-heroic", false)
            dimPanel:SetClass("dim-in-malice", false)
            dimPanel:SetClass("dim-out", true)
        end,
    }
end