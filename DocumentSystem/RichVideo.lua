local mod = dmhub.GetModLoading()

--- A rich-document widget that embeds a playable video (or animated webp) with
--- YouTube-like transport controls: play/pause, a scrubbable timeline, mute, and
--- a volume slider. Display/scale/alignment mirror RichImage; the transport bar
--- is driven by the panel video bridge added to SheetPanel (videoTime,
--- videoDuration, PlayVideo/PauseVideo, videoVolume, videoMuted, ...).
---@class RichVideo
RichVideo = RegisterGameType("RichVideo", "RichTag")
RichVideo.tag = "video"
RichVideo.image = false      -- asset id of the video / animated webp
RichVideo.halign = "left"
RichVideo.uiscale = 1
RichVideo.maxWidth = "100%"
RichVideo.loop = true
RichVideo.autoplay = true
RichVideo.muted = false
RichVideo.volume = 1

local FormatTime = function(value, maxValue)
    maxValue = maxValue or value
    if maxValue >= 60 then
        local hours = math.floor(value / (60 * 60))
        local minutes = math.floor((value / 60) % 60)
        local seconds = math.floor(value % 60)

        if hours > 0 then
            return string.format("%d:%02d:%02d", hours, minutes, seconds)
        else
            return string.format("%0d:%02d", minutes, seconds)
        end
    else
        local minutes = math.floor((value / 60) % 60)
        local seconds = math.floor(value % 60)
        return string.format("%0d:%02d", minutes, seconds)
    end
end

function RichVideo.Create()
    return RichVideo.new {}
end

-- Build the unique video source string. The "###" suffix gives this widget its own
-- independent player instance (so play/pause/seek don't bleed onto other panels or
-- map backgrounds showing the same clip); LOOP/AUDIO enable looping and the audio track.
-- See project_richvideo_transport_bridge / SheetPanel bridge.
--
-- We ALWAYS loop at the engine level. A non-looping engine clip returns a null texture
-- when it finishes, which collapses the autosizeimage panel (the video "disappears").
-- The widget's own "no loop" setting is emulated in Lua instead: think() pauses the clip
-- on its last frame when it reaches the end and shows the replay poster.
local function BuildVideoSource(image, guid)
    if not image then
        return nil
    end

    return image .. "###LOOPAUDIO" .. guid
end

function RichVideo.CreateDisplay(self)
    local m_guid = dmhub.GenerateGuid()
    local m_currentSrc = nil
    local m_configInit = false
    local m_started = false
    local m_finished = false
    -- ticks to suppress end-detection after a seek, since videoTime updates asynchronously
    -- and a stale near-end reading would otherwise finish the video right after a seek.
    local m_seekGuard = 0
    local m_image = self.image
    local m_loop = self.loop
    local m_autoplay = self.autoplay
    local m_volume = self.volume
    local m_muted = self.muted

    local m_videoPanel
    local m_controlBar
    local m_playButton
    local m_timeLabel
    local m_scrubWrapper
    local m_scrubFill
    local m_muteButton
    local m_volumeSlider

    -- forward-declared so the button/press closures can call them before assignment.
    local TogglePlayback
    local Replay

    -- Auto-hide the control bar while the video is playing and the mouse is elsewhere.
    -- The engine hovers a panel and its parents, but stops at the first swallowPress
    -- panel -- so hovering the (swallowPress) bar or its buttons does NOT mark the video
    -- as hovered. Each such panel therefore reports its own hover into this shared set,
    -- and AnyHovered() is true when the mouse is anywhere over the widget.
    local m_hover = {}
    local function HoverIn(key) return function() m_hover[key] = true end end
    local function HoverOut(key) return function() m_hover[key] = false end end
    local function AnyHovered()
        for _, v in pairs(m_hover) do
            if v then
                return true
            end
        end
        return false
    end

    -- Play/pause button: a "none"-flow container holding both a play triangle and a
    -- two-bar pause glyph; think() toggles which is visible based on play state.
    local m_playIcon = gui.Panel {
        bgimage = "panels/triangle.png",
        bgcolor = "white",
        width = 18,
        height = 18,
        halign = "center",
        valign = "center",
        rotate = 90,
    }

    local m_pauseIcon = gui.Panel {
        classes = { "collapsed" },
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        bgimage = true,
        bgcolor = "clear",
        gui.Panel { bgimage = "panels/square.png", bgcolor = "white", width = 5, height = 18 },
        gui.Panel { bgimage = "panels/square.png", bgcolor = "white", width = 5, height = 18, hmargin = 4 },
    }

    m_playButton = gui.Panel {
        classes = { "videoPlayButton" },
        flow = "none",
        width = 24,
        height = 24,
        valign = "center",
        halign = "left",
        swallowPress = true,
        hover = HoverIn("play"),
        dehover = HoverOut("play"),
        press = function(element)
            TogglePlayback()
        end,

        m_playIcon,
        m_pauseIcon,
    }

    m_timeLabel = gui.Label {
        classes = { "sizeS" },
        width = "auto",
        height = "auto",
        valign = "center",
        halign = "left",
        hmargin = 6,
        color = "white",
        text = "0:00/0:00",
    }

    -- Custom progress bar (not gui.Slider): a rounded translucent rail with a flat-color
    -- fill child whose width is a percentage of the track, set each think() from playback
    -- progress. The rail uses translucent white so it reads against the dark control bar;
    -- the fill is the theme accent color (flat, no gradient) so it tracks the scheme -- the
    -- same token the old fillBar gradient tinted toward at its bright (right) end.
    m_scrubFill = gui.Panel {
        classes = {"bgAccent"},
        bgimage = "panels/square.png",
        halign = "left",
        valign = "center",
        height = "100%",
        width = "0%",
        cornerRadius = 4,
    }

    local m_scrubTrack = gui.Panel {
        bgimage = "panels/square.png",
        bgcolor = "#FFFFFF55",
        width = "100%",
        height = 9,
        valign = "center",
        cornerRadius = 4,

        m_scrubFill,
    }

    -- A full-height wrapper carries the click target (easier to hit than the 6px track)
    -- and seeks to the clicked fraction. element.mousePoint.x is normalized 0..1 across
    -- the panel (same convention gui.Slider's click area uses).
    m_scrubWrapper = gui.Panel {
        width = "40%",
        height = "100%",
        valign = "center",
        flow = "none",
        swallowPress = true,
        hover = HoverIn("scrub"),
        dehover = HoverOut("scrub"),
        press = function(element)
            if m_videoPanel ~= nil and m_videoPanel.videoCanSeek then
                local dur = m_videoPanel.videoDuration or 0
                if dur > 0 then
                    local frac = element.mousePoint.x
                    frac = math.max(0, math.min(1, frac))
                    m_videoPanel.videoTime = frac * dur
                    -- the seek lands a few frames later; don't let a stale near-end
                    -- reading in the meantime trip end-detection.
                    m_seekGuard = 4
                end
            end
        end,

        m_scrubTrack,
    }

    m_muteButton = gui.Panel {
        classes = { "videoMuteButton" },
        bgimage = "ui-icons/AudioVolumeButton.png",
        bgcolor = "white",
        width = 21,
        height = 21,
        halign = "right",
        valign = "center",
        hmargin = 6,
        swallowPress = true,
        hover = HoverIn("mute"),
        dehover = HoverOut("mute"),
        press = function(element)
            m_muted = not m_muted
            element:SetClass("muted", m_muted)
            if m_videoPanel ~= nil then
                m_videoPanel.videoMuted = m_muted
            end
        end,
    }

    -- gui.Slider overwrites its own hover/dehover (to swap the handle image), so we can't
    -- attach our hover tracking to it directly. Drop the slider's swallowPress and wrap it
    -- in a swallowPress container that carries the hover and stops clicks from reaching the
    -- video toggle. (Hovering the slider walks up to the wrapper, which is the chain break.)
    m_volumeSlider = gui.Slider {
        width = 84,
        height = 18,
        valign = "center",
        sliderWidth = 84,
        minValue = 0,
        maxValue = 1,
        value = self.volume,
        handleSize = "100%",
        preview = function(element)
            m_volume = element.value
            if m_videoPanel ~= nil then
                m_videoPanel.videoVolume = m_volume
            end
        end,
        confirm = function(element)
            m_volume = element.value
            if m_videoPanel ~= nil then
                m_videoPanel.videoVolume = m_volume
            end
        end,
    }

    local m_volumeWrapper = gui.Panel {
        width = "auto",
        height = "100%",
        halign = "right",
        valign = "center",
        rmargin = 8,
        flow = "horizontal",
        swallowPress = true,
        hover = HoverIn("volume"),
        dehover = HoverOut("volume"),

        m_volumeSlider,
    }

    m_controlBar = gui.Panel {
        classes = { "videoControlBar" },
        floating = true,
        flow = "horizontal",
        width = "100%",
        height = 40,
        halign = "center",
        valign = "bottom",
        bgimage = "panels/square.png",
        bgcolor = "#000000c0",
        pad = 6,
        borderBox = true,
        swallowPress = true,
        hover = HoverIn("bar"),
        dehover = HoverOut("bar"),

        m_playButton,
        m_timeLabel,
        m_scrubWrapper,
        m_muteButton,
        m_volumeWrapper,
    }

    -- Darkened "poster" overlay shown whenever the video is loaded but not playing
    -- (autoplay off, paused, or finished-with-loop-off). A big glyph sits in the middle:
    -- a play triangle normally, or a replay (curved-arrow) icon once the video has
    -- finished. Clicking anywhere on the video bubbles to the video surface's press.
    -- Sized in think() to match the video surface's rendered pixels (a floating "100%"
    -- can't resolve against an autosizeimage parent), so we read renderedWidth/Height.
    local m_bigPlayIcon = gui.Panel {
        bgimage = "panels/triangle.png",
        bgcolor = "white",
        width = 72,
        height = 72,
        halign = "center",
        valign = "center",
        rotate = 90,
    }

    local m_bigReplayIcon = gui.Panel {
        classes = { "collapsed" },
        bgimage = "icons/standard/Icon_App_Undo.png",
        bgcolor = "white",
        width = 64,
        height = 64,
        halign = "center",
        valign = "center",
    }

    local m_playOverlay = gui.Panel {
        classes = { "videoPosterOverlay" },
        floating = true,
        width = 16,
        height = 16,
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#00000099",

        m_bigPlayIcon,
        m_bigReplayIcon,
    }

    m_videoPanel = gui.Panel {
        classes = { "videoSurface" },
        width = "auto",
        height = "auto",
        autosizeimage = true,
        maxWidth = self.maxWidth,
        uiscale = self.uiscale,
        clip = true,
        bgcolor = "white",

        styles = {
            {
                selectors = { "videoMuteButton", "muted" },
                opacity = 0.4,
            },
        },

        hover = HoverIn("video"),
        dehover = HoverOut("video"),

        press = function(element)
            TogglePlayback()
        end,

        refreshTag = function(element, tag, match, token)
            tag = tag or self
            self = tag

            m_loop = tag.loop
            m_autoplay = tag.autoplay
            m_image = tag.image

            if not m_configInit then
                m_configInit = true
                m_volume = tag.volume
                m_muted = tag.muted
                m_volumeSlider.value = m_volume
                m_muteButton:SetClass("muted", m_muted)
            end

            local src = BuildVideoSource(tag.image, m_guid)
            if src ~= m_currentSrc then
                m_currentSrc = src
                m_started = false
                m_finished = false
                if src ~= nil then
                    element.bgimageStreamed = src
                else
                    element.bgimage = nil
                end
            end

            element.selfStyle.uiscale = tag.uiscale
            element:SetClass("collapsed", tag.image == false)
        end,

        thinkTime = 0.1,
        think = function(element)
            local dur = element.videoDuration or 0
            local playing = element.videoPlaying

            if playing then
                m_finished = false
            end

            -- swap the play/pause glyphs.
            m_playIcon:SetClass("collapsed", playing)
            m_pauseIcon:SetClass("collapsed", not playing)

            -- one-time setup once the video has actually loaded.
            -- Wait until the engine has actually started the clip (playing == true) before
            -- doing first-load setup. The engine's EnsureInit calls Play() on the underlying
            -- player when the clip finishes preparing; if we paused before that, EnsureInit
            -- would resume the real player while our wrapper still reads "paused" -- so the
            -- poster would show over a video that is in fact still playing.
            if not m_started and dur > 0 and playing then
                m_started = true
                element.videoVolume = m_volume
                element.videoMuted = m_muted
                if not m_autoplay then
                    element:PauseVideo()
                    element.videoTime = 0
                end
            end

            -- Emulate "no loop": the clip always loops at the engine level (so it never
            -- nulls its texture and collapses), but a non-looping widget plays it once and
            -- then stops on the last frame and offers replay. Pause just before the end.
            -- (think runs every 0.1s and the window is 0.12s wide, so a tick always lands in
            -- it at normal speed.) End-detection is suppressed for a few ticks after a seek
            -- (m_seekGuard), since videoTime updates asynchronously -- without this a backward
            -- seek would read a stale near-end time and wrongly finish the video.
            if m_seekGuard > 0 then
                m_seekGuard = m_seekGuard - 1
            elseif dur > 0 and m_started and not m_loop and not m_finished and playing then
                local t = element.videoTime or 0
                if t >= dur - 0.12 then
                    m_finished = true
                    element:PauseVideo()
                end
            end

            -- the big darkened poster overlay shows whenever we have a video that is
            -- loaded-and-not-playing, sized to cover the rendered video. It shows the
            -- replay glyph once the video has finished (loop off), else the play glyph.
            m_playOverlay:SetClass("collapsed", m_currentSrc == nil or playing)
            m_bigPlayIcon:SetClass("collapsed", m_finished)
            m_bigReplayIcon:SetClass("collapsed", not m_finished)
            local rw = element.renderedWidth
            local rh = element.renderedHeight
            if rw ~= nil and rw > 0 and rh ~= nil and rh > 0 then
                m_playOverlay.selfStyle.width = rw
                m_playOverlay.selfStyle.height = rh
            end

            -- Show the control bar when there are controls AND (the video is not playing
            -- OR the mouse is hovering the widget). So a playing video hides its controls
            -- until hovered.
            local hasControls = element.videoCanSeek or dur > 0
            local showControls = hasControls and ((not playing) or AnyHovered())
            m_controlBar:SetClass("collapsed", not showControls)
            m_scrubWrapper:SetClass("collapsed", not element.videoCanSeek)

            -- When finished we pause a hair before dur, so present it as the full duration
            -- (full bar + matching time readout) rather than ~99%.
            local t = element.videoTime or 0
            if m_finished then
                t = dur
            end
            m_timeLabel.text = string.format("%s/%s", FormatTime(t, dur), FormatTime(dur))

            local frac = dur > 0 and math.min(t / dur, 1) or 0
            m_scrubFill.selfStyle.width = string.format("%.1f%%", frac * 100)
        end,

        m_playOverlay,
        m_controlBar,
    }

    -- Restart a finished (or any) video from the beginning. Because the clip always loops
    -- at the engine level (it pauses on the last frame rather than finishing), the player
    -- is still alive, so we just seek to 0 and play it in place -- NOT reassign
    -- bgimageStreamed, which would dirty the whole subtree's styles and flash the control
    -- bar white. Only if the player has actually been evicted do we rebuild from scratch.
    Replay = function()
        if m_videoPanel == nil then
            return
        end

        m_finished = false

        if (m_videoPanel.videoDuration or 0) > 0 then
            m_videoPanel.videoTime = 0
            m_videoPanel:PlayVideo()
            -- the seek-to-0 lands a few frames later; suppress end-detection until then so
            -- a stale near-end reading doesn't immediately re-finish the freshly replayed clip.
            m_seekGuard = 4
        elseif m_image then
            m_guid = dmhub.GenerateGuid()
            m_started = false
            local src = BuildVideoSource(m_image, m_guid)
            m_currentSrc = src
            m_videoPanel.bgimageStreamed = src
        end
    end

    TogglePlayback = function()
        if m_videoPanel == nil or m_currentSrc == nil then
            return
        end

        if m_finished then
            Replay()
        elseif m_videoPanel.videoPlaying then
            m_videoPanel:PauseVideo()
        else
            m_videoPanel:PlayVideo()
        end
    end

    local resultPanel
    resultPanel = gui.Panel {
        width = "auto",
        height = "auto",
        valign = "center",
        halign = self.halign,
        refreshTag = function(element, tag, match, token)
            element.selfStyle.halign = token.justification or (tag or self).halign
        end,

        m_videoPanel,
    }

    return resultPanel
end

function RichVideo.CreateEditor(self)
    local resultPanel

    resultPanel = gui.Panel {
        flow = "none",
        width = 96,
        height = "100%",
        refreshEditor = function(element, richTag)
            self = richTag or self
        end,

        gui.Button {
            classes = { "settingsButton", "sizeXxs" },
            halign = "right",
            valign = "top",
            press = function(element)
                if element.popup ~= nil then
                    element.popup = nil
                    return
                end
                element.popupsInheritStyles = true
                element.popup = gui.Panel {
                    classes = { "bordered", "bg" },
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                    pad = 8,

                    gui.Panel {
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        gui.Label {
                            classes = { "sizeXs" },
                            width = "auto",
                            height = "auto",
                            text = "Scale:",
                        },
                        gui.Slider {
                            width = 160,
                            labelWidth = 40,
                            height = 20,
                            minValue = 0,
                            maxValue = 1,
                            handleSize = "100%",
                            labelFormat = "percent",
                            value = self.uiscale,
                            change = function(element)
                                self.uiscale = element.value
                            end,
                        },
                    },

                    gui.Dropdown {
                        idChosen = self.halign,
                        options = {
                            { id = "left", text = "Align Left" },
                            { id = "center", text = "Align Center" },
                            { id = "right", text = "Align Right" },
                        },
                        change = function(element)
                            self.halign = element.idChosen
                        end,
                    },

                    gui.Check {
                        classes = { "sizeXs" },
                        text = "Loop",
                        value = self.loop,
                        change = function(element)
                            self.loop = element.value
                        end,
                    },

                    gui.Check {
                        classes = { "sizeXs" },
                        text = "Autoplay",
                        value = self.autoplay,
                        change = function(element)
                            self.autoplay = element.value
                        end,
                    },

                    gui.Check {
                        classes = { "sizeXs" },
                        text = "Start Muted",
                        value = self.muted,
                        change = function(element)
                            self.muted = element.value
                        end,
                    },

                    gui.Panel {
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        gui.Label {
                            classes = { "sizeXs" },
                            width = "auto",
                            height = "auto",
                            text = "Volume:",
                        },
                        gui.Slider {
                            width = 160,
                            labelWidth = 40,
                            height = 20,
                            minValue = 0,
                            maxValue = 1,
                            handleSize = "100%",
                            labelFormat = "percent",
                            value = self.volume,
                            change = function(element)
                                self.volume = element.value
                            end,
                        },
                    },
                }
            end,
        },

        gui.IconEditor {
            width = 64,
            height = 64,
            halign = "center",
            valign = "center",
            library = "journal",
            value = self.image or nil,
            change = function(element)
                self.image = element.value
            end,
        },
    }

    return resultPanel
end

MarkdownDocument.RegisterRichTag(RichVideo)
