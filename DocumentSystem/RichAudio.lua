local mod = dmhub.GetModLoading()

---@class RichAudio
RichAudio = RegisterGameType("RichAudio", "RichTag")
RichAudio.tag = "sound"
RichAudio.sound = false
RichAudio.volume = 1.0

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
    elseif maxValue >= 10 then
        return string.format("%d", math.floor(value))
    else
        return string.format("%.1f", value)
    end
end

function RichAudio.Create()
    return RichAudio.new {}
end

local g_audioStyles = {
    {
        selectors = { "audioPanel" },

    },
    {
        selectors = { "audioPanel", "hover", "haveasset" },
        brightness = 1.2,
    },
    {
        selectors = { "playButton" },
        bgimage = "panels/triangle.png",
    },
    {
        selectors = { "playButton", "parent:playing" },
        bgimage = "panels/square.png",
    },
    {
        selectors = { "sliderHandleInner" },
        priority = 10,
        bgcolor = "black",
    },
    {
        selectors = { "sliderHandleBorder" },
        priority = 10,
        borderColor = "black",
    },
    {
        selectors = { "enumSlider" },
        cornerRadius = 4,
    },
}

function RichAudio.CreateDisplay(self)
    local m_audioAsset = nil
    local m_broadcast = true
    local m_player = false
    local m_volume = 1

    local IsBroadcast = function()
        print("PLAY:: m_broadcast =", m_broadcast, "m_player =", m_player)
        return m_broadcast and not m_player
    end

    local m_playButton = gui.Panel {
        classes = { "playButton" },
        bgcolor = "black",
        rotate = 90,
        floating = true,
        halign = "center",
        valign = "center",
        width = 16,
        height = 16,
        y = 10,
    }

    local m_playingEvent = nil


    local m_audioPanel = gui.Panel {
        styles = g_audioStyles,
        classes = { "audioPanel" },
        width = 120,
        height = 64,
        halign = "left",
        valign = "center",
        flow = "vertical",
        cornerRadius = 6,
        bgimage = true,
        bgcolor = Styles.textColor,
        refreshTag = function(element, tag, match, token)
            tag = tag or self
            m_player = token.player or false
            m_audioAsset = assets.audioTable[tag.sound]
            element:SetClass("haveasset", m_audioAsset ~= nil)
        end,

        thinkTime = 0.1,
        think = function(element)
            if m_audioAsset == nil then
                element:SetClass("playing", false)
                return
            end

            local soundEvent = nil
            if m_playingEvent ~= nil then
                if not m_playingEvent.playing then
                    m_playingEvent = nil
                end

                soundEvent = m_playingEvent
            end

            local soundEvent = soundEvent or audio.currentlyPlaying[m_audioAsset.id]
            if soundEvent ~= nil or element:HasClass("playing") then
                element:FireEventTree("refreshPlaying", soundEvent)
            end
            if soundEvent ~= nil then
                element:SetClass("playing", true)
            else
                element:SetClass("playing", false)
            end
        end,

        press = function(element)
            if m_audioAsset == nil then
                return
            end

            if m_playingEvent ~= nil and m_playingEvent.playing then
                print("PLAY:: STOP LOCAL")
                m_playingEvent:Stop()
                m_playingEvent = nil
                return
            end

            if not IsBroadcast() then
                m_playingEvent = m_audioAsset:Play()
                m_playingEvent.volume = m_volume
                return
            end

            local soundEvent = audio.currentlyPlaying[m_audioAsset.id]
            if soundEvent ~= nil then
                audio.StopSoundEvent(m_audioAsset.id)
                element:SetClass("playing", false)
            else
                audio.PlaySoundEvent {
                    asset = m_audioAsset,
                    volume = m_volume,
                }
                element:SetClass("playing", true)
            end
        end,

        gui.Panel {
            cornerRadius = { x1 = 6, y1 = 6, x2 = 0, y2 = 0 },
            width = "100%-2",
            height = 20,
            bgimage = true,
            bgcolor = "black",
            halign = "center",
            valign = "top",
            vmargin = 1,
            clip = true,

            gui.Label {
                width = "auto",
                height = "100%",
                color = "#ffffee",
                refreshTag = function(element, tag)
                    if m_audioAsset == nil then
                        element.text = "(no sound)"
                        return
                    end
                    element.text = m_audioAsset.description
                end,
            },
        },

        gui.Panel {
            width = "100%",
            height = 14,
            flow = "horizontal",
            valign = "top",
            gui.Label {
                bold = true,
                fontSize = 12,
                rmargin = 0,
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
                color = "black",
                refreshTag = function(element, tag)
                    if m_audioAsset == nil then
                        return
                    end

                    element.text = FormatTime(m_audioAsset.duration)
                end,

                refreshPlaying = function(element, soundEvent)
                    if soundEvent == nil then
                        element.text = FormatTime(m_audioAsset.duration)
                        return
                    end

                    element.text = string.format("%s/%s", FormatTime(soundEvent.time, m_audioAsset.duration),
                        FormatTime(m_audioAsset.duration))
                end,

            },
        },

        m_playButton,

        --volume slider.
        gui.Panel {
            width = "100%",
            height = "auto",
            flow = "horizontal",
            valign = "bottom",
            gui.Panel {
                bgimage = 'ui-icons/AudioVolumeButton.png',
                bgcolor = "black",
                width = 12,
                height = 12,
                swallowPress = true,
                press = function(element)

                end,
            },
            gui.Slider {
                width = 80,
                height = 12,
                sliderWidth = 80,
                minValue = 0,
                maxValue = 1,
                handleSize = "100%",
                swallowPress = true,
                preview = function(element)
                    if m_audioAsset == nil then
                        return
                    end

                    local soundEvent = audio.currentlyPlaying[m_audioAsset.id]
                    if soundEvent ~= nil then
                        audio.SetSoundEventVolume(m_audioAsset.id, element.value)
                        return
                    end
                end,
                confirm = function(element)
                    element:FireEvent("preview")
                    m_volume = element.value
                end,
                refreshTag = function(element, tag)
                    if m_audioAsset == nil then
                        return
                    end

                    element.value = m_volume
                end,
            }
        },
    }

    local resultPanel

    resultPanel = gui.Panel {
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        flow = "vertical",
        m_audioPanel,
        gui.EnumeratedSliderControl {
            width = 120,
            height = 16,
            fontSize = 10,
            vmargin = 2,
            halign = "center",
            refreshTag = function(element, tag, match, token)
                element:SetClass("collapsed", token.player)
            end,
            options = {
                { id = false, text = "Self" },
                { id = true,  text = "All" },
            },
            value = m_broadcast,
            change = function(element)
                if m_audioAsset ~= nil then
                    --stop any existing playing when we change mode.
                    if m_playingEvent ~= nil and m_playingEvent.playing then
                        m_playingEvent:Stop()
                        m_playingEvent = nil
                    end

                    local soundEvent = audio.currentlyPlaying[m_audioAsset.id]
                    if soundEvent ~= nil then
                        audio.StopSoundEvent(m_audioAsset.id)
                    end
                end

                m_broadcast = element.value
            end,
        }
    }

    return resultPanel
end

function RichAudio.CreateEditor(self)
    local resultPanel

    local m_asset = nil

    resultPanel = gui.Panel {
        flow = "vertical",
        width = 96,
        height = "100%",
        refreshEditor = function(element, richTag)
            self = richTag or self
            m_asset = assets.audioTable[self.sound]
        end,

        gui.AudioEditor {
            width = 54,
            height = 54,
            halign = "center",
            valign = "center",
            value = self.sound or nil,
            change = function(element)
                self.sound = element.value
                resultPanel:FireEventTree("refreshEditor", self)
            end,
        },

        gui.Slider {
            width = 64,
            height = 12,
            halign = "center",
            sliderWidth = 64,
            value = 1,
            minValue = 0,
            maxValue = 1,
            refreshEditor = function(element, richTag)
                if m_asset == nil then
                    element:SetClass("hidden", true)
                    return
                end

                element:SetClass("hidden", false)
                element.value = m_asset.volume
            end,
            change = function(element)
                m_asset.volume = element.value
                m_asset:Upload()
            end,
        },

        gui.Check {
            width = 60,
            height = 16,
            minWidth = 0,
            halign = "center",
            valign = "center",
            text = "Loop",
            fontSize = 12,
            value = false,
            refreshEditor = function(element, richTag)
                if m_asset == nil then
                    element:SetClass("hidden", true)
                    return
                end

                element:SetClass("hidden", false)
                element.value = m_asset.loop
            end,
            change = function(element)
                m_asset.loop = element.value
                m_asset:Upload()
            end,
        },
    }

    return resultPanel
end

MarkdownDocument.RegisterRichTag(RichAudio)
