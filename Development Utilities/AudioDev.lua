local mod = dmhub.GetModLoading()

local function track(eventType, fields)
	if dmhub.GetSettingValue("telemetry_enabled") == false then
		return
	end
	fields.type = eventType
	fields.userid = dmhub.userid
	fields.gameid = dmhub.gameid
	fields.version = dmhub.version
	analytics.Event(fields)
end

local AudioDevPanel

DockablePanel.Register{
	name = "Audio Dev",
    folder = "Development Tools",
    vscroll = false,
	content = function()
		track("panel_open", {
			panel = "Audio Dev",
			dailyLimit = 30,
		})
        return AudioDevPanel()
	end,
}

local function CreateSoundEventPanel(name)
    local SoundEvent = function()
        return audio.soundEvents[name]
    end


    local m_soundEvent = audio.soundEvents[name]

    local resultPanel

    resultPanel = gui.Panel{
        width = "90%",
        height = 30,
        halign = "left",
        lmargin = 4,
        refreshAudioDev = function(element, search)
            m_soundEvent = audio.soundEvents[name]

            if search == nil or string.find(string.lower(m_soundEvent.name), string.lower(search), 1, true) ~= nil then
                element:SetClass("collapsed", false)
            else
                element:SetClass("collapsed", true)
            end

        end,
        data = {
            ord = name,
        },
        gui.Label{
            text = m_soundEvent.name,
            fontSize = 14,
            width = "auto",
            height = "auto",
            bold = true,
            halign = "left",
            valign = "top",
            hmargin = 4,
            vmargin = 4,
        },
        gui.Button{
            text = "Play",
            width = 50,
            height = 20,
            fontSize = 14,
            halign = "right",
            valign = "top",
            hmargin = 4,
            vmargin = 4,
            click = function()
                audio.FireSoundEvent(name)
            end,
        },
    }

    return resultPanel
end

AudioDevPanel = function()

    local m_search = ""

    local resultPanel

    local m_count = 0

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "100%",

        data = {
            seq = -1,
        },

        thinkTime = 0.1,
        think = function(element)
            m_count = m_count + 1
            if element.data.seq == audio.nUpdateSeq and (m_count < 10) then
                return
            end

            element:FireEventTree("refreshAudioDev", m_search)
            m_count = 0
        end,

        refreshAudioDev = function(element)
            element.data.seq = audio.nUpdateSeq
            print("AudioDev: REFRESH")
        end,

        gui.Panel{
            flow = "horizontal",
            width = "90%",
            height = 30,
            gui.Button{
                width = "48%",
                height = 20,
                halign = "left",
                fontSize = 12,
                text = "Open Sound Folder",
                click = function()
                    audio.OpenAudioDevDir()
                end,
            },

            gui.Button{
                width = "48%",
                height = 20,
                halign = "left",
                fontSize = 12,
                text = "Upload Audio Assets",
                click = function()
                    audio.UploadAudio()
                end,
            },
        },

        gui.Input{
            width = "90%",
            height = 20,
            halign = "left",
            placeholderText = "Filter Sound Events...",
            text = "",
            fontSize = 14,
            edit = function(element)
                m_search = element.text
                resultPanel:FireEventTree("refreshAudioDev", m_search)
            end,
            editlag = 0.2,
        },

        gui.Panel{
            width = "100%",
            height = "100%-240",
            vscroll = true,
            flow = "vertical",
            data = {
                panels = {},
            },
            refreshAudioDev = function(element)
                local newPanels = {}
                local soundEvents = audio.soundEvents
                local children = {}

                for k, soundEvent in pairs(soundEvents) do
                    local panel = element.data.panels[k] or CreateSoundEventPanel(k)

                    newPanels[k] = panel
                    children[#children+1] = panel
                end

                table.sort(children, function(a, b)
                    return a.data.ord < b.data.ord
                end)

                element.data.panels = newPanels
                element.children = children
            end,
        },

        gui.Panel{
            width = "100%",
            height = 160,
            flow = "vertical",
            vscroll = true,
            create = function(element)
                audio.events:Listen(element)
            end,
            log = function(element, message)
                local logPanel = gui.Label{
                    width = "100%",
                    height = "auto",
                    textWrap = true,
                    fontSize = 14,
                    text = message,
                    halign = "left",
                    valign = "top",
                    hmargin = 4,
                    vmargin = 0,
                }

                element:AddChild(logPanel)
            end,
            soundEvent = function(element, name, handled, args)
                element:FireEvent("log", string.format("Sound Event: \"%s\", %s", name, cond(handled, "Handled", "Unhandled")))
            end,
        },
    }

    resultPanel:FireEventTree("refreshAudioDev", m_search)

    return resultPanel
end