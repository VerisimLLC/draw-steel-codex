local mod = dmhub.GetModLoading()

RegisterGameType("FullscreenDisplay")

FullscreenDisplay.docid = "fullscreen_display"

function FullscreenDisplay.Create(options)
    local belowui = options.belowui or false
	local doc = mod:GetDocumentSnapshot(FullscreenDisplay.docid)
    local displayPanel = gui.Panel{
        classes = {"hidden", cond(belowui, "belowui", "aboveui")},
        width = "100%",
        height = "100%",
        bgimage = doc.data.coverart,
        bgcolor = "white",
        halign = "center",
        valign = "center",
        floating = true,

        styles = {
            {
                selectors = {"~dm", "closebutton"},
                hidden = 1,
            }
        },

        screenResized = function(element)
            element:ScheduleEvent("imageLoaded", 0.5)
        end,

        imageLoaded = function(element)
            if element.bgsprite == nil then
                return
            end

            local w = element.parent.renderedWidth
            local h = element.parent.renderedHeight
            local aspect = h / w

            local imageAspect = element.bgsprite.dimensions.y/element.bgsprite.dimensions.x

            if aspect == imageAspect then
                element.selfStyle.width = "100%"
                element.selfStyle.height = "100%"
            elseif aspect > imageAspect then
                element.selfStyle.height = "100%"
                element.selfStyle.width = string.format("%f%% height", 100/imageAspect)
            else
                element.selfStyle.width = "100%"
                element.selfStyle.height = string.format("%f%% width", 100*imageAspect)
            end
        end,
    }

    return gui.Panel{
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        displayPanel,

        data = {
            presentationInfo = nil,
        },

        monitorGame = doc.path,

        refreshGame = function(element)
	        local doc = mod:GetDocumentSnapshot(FullscreenDisplay.docid)
            displayPanel.bgimage = doc.data and doc.data.coverart
            local hide = doc.data == nil or (doc.data.belowui or false) ~= belowui or (not doc.data.show) or (doc.data.show ~= "all" and dmhub.isDM)
            displayPanel:SetClass("hidden", hide)

            if not hide then
                displayPanel:FireEvent("imageLoaded")
            end

            if doc.data == nil or (not doc.data.show) or not dmhub.isDM then
                if element.data.presentationInfo ~= nil then
                    TopBar.ClearPresentationInfo(element.data.presentationInfo.id)
                    element.data.presentationInfo = nil
                end
            else
                local info = element.data.presentationInfo or {}
                info.id = info.id or dmhub.GenerateGuid()
                info.text = "Show Scene"
                info.onchange = info.onchange or function(value)
                    local doc = FullscreenDisplay.GetDocumentSnapshot()
                    doc:BeginChange()
                    doc.data.show = value
                    doc:CompleteChange("Show Fullscreen Display")
                end
                info.options = info.options or {
                    {
                        id = false,
                        text = "Hide",
                        execute = function()
                        end,
                    },
                    {
                        id = true,
                        text = "Players",
                        execute = function()
                        end,
                    },
                    {
                        id = "all",
                        text = "All",
                        execute = function()
                        end,
                    }
                }
                info.value = doc.data.show
                TopBar.SetPresentationInfo(info)
                element.data.presentationInfo = info
            end
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
-- It is NOT a modal: the overlay never captures input, so play
-- continues underneath it. Trigger one from anywhere with:
--
--     DramaticBanner.Show{ tokenid = tok.id, text = "Lord Syriax", subtitle = "The Pale Tyrant" }
--
-- State is held in a synced document, so every client in the game sees
-- the banner at the same moment. The panel is created once and mounted
-- at the top-most overlay layer of the game HUD.
----------------------------------------------------------------------

RegisterGameType("DramaticBanner")

DramaticBanner.docid = "dramatic_banner"

-- Seconds the banner holds fully on screen between its entrance and exit.
DramaticBanner.holdTime = 4

-- Sound played as the banner enters (matches the Draw Steel initiative
-- banner). Used whenever DramaticBanner.Show is not given its own sound.
DramaticBanner.defaultSound = "UI.DrawSteel"

-- Accent colour used when the token has no vivid colour of its own
-- (monsters and unowned tokens report a near-white playerColor).
DramaticBanner.fallbackAccent = "#e8c264"

-- Subtle vertical sheen for the opaque banner band (opaque throughout).
local g_dramaticBandGradient = gui.Gradient{
    point_a = {x = 0.5, y = 0},
    point_b = {x = 0.5, y = 1},
    stops = {
        {position = 0,   color = "#07070bff"},
        {position = 0.5, color = "#181820ff"},
        {position = 1,   color = "#07070bff"},
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
--- @param args {tokenid: nil|string, text: string, subtitle: nil|string, sound: nil|string}
function DramaticBanner.Show(args)
    local doc = mod:GetDocumentSnapshot(DramaticBanner.docid)
    doc:BeginChange()
    -- A fresh triggerId is what makes each call replay the animation,
    -- even when the content is identical to the previous banner.
    doc.data.triggerId = dmhub.GenerateGuid()
    doc.data.tokenid = args.tokenid
    doc.data.text = args.text or ""
    doc.data.subtitle = args.subtitle
    doc.data.sound = args.sound or DramaticBanner.defaultSound
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
            { classes = {"dim-in"},  opacity = 0.62, transitionTime = 0.4 },
        },
    }

    -- Opaque band that irises open vertically from the centre line.
    local bandPanel = gui.Panel{
        classes = {"band-out"},
        interactable = false,
        width = "100%",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "white",
        gradient = g_dramaticBandGradient,
        styles = {
            { classes = {"band-out"}, height = 0,   transitionTime = 0.1 },
            { classes = {"band-in"},  height = 450, transitionTime = 0.1 },
        },
    }

    ------------------------------------------------------------------
    -- Content revealed between the swords: the token portrait and the
    -- title / subtitle text.
    ------------------------------------------------------------------
    -- Portrait uses the standard 3:4 (width:height) aspect ratio, with
    -- its edges faded out so it blends softly into the band.
    local portraitPanel = gui.Panel{
        interactable = false,
        width = 300,
        height = 400,
        halign = "center",
        valign = "center",
        bgcolor = "white",
        edgeFade = 0.1,
    }

    local titleLabel = gui.Label{
        interactable = false,
        text = "",
        width = "100%",
        height = "auto",
        textAlignment = "left",
        textWrap = false,
        fontFace = "Colvillain",
        fontSize = 53,
        fontWeight = "black",
        color = "white",
    }

    local accentRule = gui.Panel{
        interactable = false,
        width = "100%",
        height = 4,
        halign = "left",
        vmargin = 10,
        bgimage = "panels/square.png",
        bgcolor = "white",
    }

    local subtitleLabel = gui.Label{
        interactable = false,
        text = "",
        width = "100%",
        height = "auto",
        textAlignment = "left",
        textWrap = true,
        fontFace = "Colvillain",
        fontSize = 21,
        uppercase = true,
        color = "white",
    }

    local textColumn = gui.Panel{
        interactable = false,
        width = 560,
        height = "auto",
        valign = "center",
        lmargin = 50,
        flow = "vertical",
        children = { titleLabel, accentRule, subtitleLabel },
    }

    -- Portrait + text, revealed between the parting swords.
    local contentGroup = gui.Panel{
        interactable = false,
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        flow = "horizontal",
        children = { portraitPanel, textColumn },
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
        classes = {"hidden"},
        flow = "none",
        interactable = false,
        width = "100%",
        height = 460,
        halign = "center",
        valign = "center",
        children = { contentGroup, leftCover, rightCover, leftSword, rightSword },
    }

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
                token = dmhub.GetTokenById(d.data.tokenid)
            end
            local hasPortrait = token ~= nil

            local accent, accentClear = ResolveBannerAccent(token)

            -- Title / subtitle content. When there is no portrait the
            -- text is centred on the band instead of sitting beside it.
            titleLabel.text = d.data.text or ""
            titleLabel.textAlignment = cond(hasPortrait, "left", "center")
            textColumn.lmargin = cond(hasPortrait, 50, 0)
            local subtitle = d.data.subtitle
            subtitleLabel.text = subtitle or ""
            subtitleLabel.textAlignment = cond(hasPortrait, "left", "center")
            subtitleLabel.color = accent
            subtitleLabel:SetClass("collapsed", subtitle == nil or subtitle == "")

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
                portraitPanel.bgimage = token.inspectPortrait
            end

            if d.data.sound then
                audio.FireSoundEvent(d.data.sound)
            end

            element.data.generation = element.data.generation + 1
            local g = element.data.generation

            -- The band irises open fast; the swords and content are
            -- held back (revealLayer stays hidden) until it has arrived.
            dimPanel:SetClass("dim-out", false)
            dimPanel:SetClass("dim-in", true)
            bandPanel:SetClass("band-out", false)
            bandPanel:SetClass("band-in", true)
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
        -- portrait and text.
        openCurtains = function(element, g)
            if g ~= element.data.generation then
                return
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
            bandPanel:SetClass("band-in", false)
            bandPanel:SetClass("band-out", true)
            dimPanel:SetClass("dim-in", false)
            dimPanel:SetClass("dim-out", true)
        end,
    }
end