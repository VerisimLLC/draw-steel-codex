local mod = dmhub.GetModLoading()

--Discord voice chat in a game. PROTOTYPE: admins only for now.
--
--A Director who is an admin switches on the game setting "Discord Voice". In
--that game every admin who has linked their Discord account joins the game's
--Discord call in the background (the engine's DiscordControllerVoice.cs; one
--Discord lobby per game). The title bar shows a microphone next to the
--network indicator (CodexTitleBar.lua), and its think drives DiscordVoice.Tick.
--The Heroes popout gets a voice section (HeroesPanel.lua). While someone
--talks, the token they are acting as shows the "Talk" emote, on every client
--and only locally (DiscordVoice.IsTokenSpeaking, read by
--creature:CalculateLoopingEmotes). Which token that is -- their selected token,
--else their primary character -- each speaker's client announces with a
--non-persistent remote event. See DISCORD_REFERENCE.md.
--
--Hotkeys: "Push to Talk" (the engine's held game input "pushtotalk": the mic is
--open while it is down, even when muted) and "Toggle Voice Mute".

DiscordVoice = {}

--the "Talk" emoji asset: a looping speech balloon.
DiscordVoice.TALK_EMOTE = "5d398acd-fcf1-47e1-8feb-6f94c1a48d27"

local TOKEN_EVENT = "discordvoice:token"

--seconds between automatic join attempts, so a failing join cannot burn
--Discord's app-wide lobby join cap (100 per 2 hours before approval).
local JOIN_RETRY_SECONDS = 30

--how often our voice token is re-announced, for people who arrive later.
local ANNOUNCE_REFRESH_SECONDS = 20

local g_setting = setting{
    id = "discordvoice",
    description = "Discord Voice",
    help = "Prototype: people in this game talk to each other over Discord voice. Admins only for now.",
    storage = "game",
    section = "game",
    editor = "check",
    default = false,
    classes = {"dmonly"},
    visible = function()
        return dmhub.isAdminAccount
    end,
}

--the status table from the engine, refreshed each tick.
local g_status = nil

--userid -> charid of the token that user's voice shows on, as they announced it.
local g_userTokens = {}

--charid -> true for tokens whose user is speaking now.
local g_speakingTokens = {}

local g_nextJoinAttempt = 0
--the gameid the user chose to leave voice in; no auto-join there until they rejoin.
local g_leftGameId = nil

--false = nothing announced yet (nil is a real value: "no token").
---@type string|nil|false
local g_lastAnnouncedToken = false
local g_lastAnnounceTime = 0
local g_nextAnnounceCheck = 0

--- @return table
function DiscordVoice.Status()
    if g_status == nil then
        g_status = dmhub.discordStatus
    end
    return g_status
end

--- True when voice is on for this user in this game: an admin, in a real game
--- with the Discord Voice setting on, in a build with Discord available.
--- @return boolean
function DiscordVoice.Available()
    if (not dmhub.inGame) or dmhub.isLobbyGame or (not dmhub.isAdminAccount) then
        return false
    end
    if g_setting:Get() ~= true then
        return false
    end
    local account = DiscordVoice.Status().account
    return account ~= "unsupported" and account ~= "off"
end

function DiscordVoice.Link()
    return dmhub.DiscordLink()
end

function DiscordVoice.Unlink()
    dmhub.DiscordUnlink()
end

--- Joins this game's call now (also clears a previous Leave).
--- @return string|nil error
function DiscordVoice.Join()
    g_leftGameId = nil
    g_nextJoinAttempt = dmhub.Time() + JOIN_RETRY_SECONDS
    return dmhub.DiscordJoinVoice()
end

--- Leaves the call; it is not rejoined automatically in this game.
function DiscordVoice.Leave()
    g_leftGameId = dmhub.gameid
    dmhub.DiscordLeaveVoice()
end

function DiscordVoice.SetMuted(muted)
    dmhub.DiscordSetVoiceMuted(muted)
    g_status = nil
end

function DiscordVoice.ToggleMuted()
    DiscordVoice.SetMuted(not DiscordVoice.Status().muted)
end

--- @param charid string|nil
--- @return boolean
function DiscordVoice.IsTokenSpeaking(charid)
    return charid ~= nil and g_speakingTokens[charid] == true
end

local function PrimaryCharacterOf(userid)
    local info = dmhub.GetSessionInfo(userid)
    if info == nil or info.primaryCharacter == nil or info.primaryCharacter == "" then
        return nil
    end
    return info.primaryCharacter
end

local function RefreshTokenEmotes(charid)
    local tok = dmhub.GetTokenById(charid)
    if tok ~= nil and tok.sheet ~= nil then
        tok.sheet:FireEventTree("refresh")
    end
end

--tell everyone which token our voice shows on.
local function AnnounceMyToken(status)
    if status.voice ~= "connected" then
        g_lastAnnouncedToken = false
        return
    end
    local now = dmhub.Time()
    if now < g_nextAnnounceCheck then
        return
    end
    g_nextAnnounceCheck = now + 0.5

    local tok = dmhub.selectedOrPrimaryTokens[1]
    local charid = tok ~= nil and tok.charid or nil
    g_userTokens[dmhub.loginUserid] = charid
    if charid == g_lastAnnouncedToken and now - g_lastAnnounceTime < ANNOUNCE_REFRESH_SECONDS then
        return
    end
    g_lastAnnouncedToken = charid
    g_lastAnnounceTime = now
    dmhub.BroadcastRemoteEvent(TOKEN_EVENT, dmhub.loginUserid, {
        gameid = dmhub.gameid,
        userid = dmhub.loginUserid,
        tokenid = charid or "",
    }, false, true)
end

dmhub.RegisterRemoteEvent(TOKEN_EVENT, function(info)
    if mod.unloaded or type(info) ~= "table" or info.gameid ~= dmhub.gameid or type(info.userid) ~= "string" then
        return
    end
    if info.userid == dmhub.loginUserid then
        return
    end
    g_userTokens[info.userid] = (type(info.tokenid) == "string" and info.tokenid ~= "") and info.tokenid or nil
end)

local function UpdateSpeakingTokens(status)
    local speaking = {}
    if status.voice == "connected" then
        for _, p in ipairs(status.participants) do
            local talking = p.speaking
            if p.isSelf then
                talking = status.transmitting
            end
            if talking and p.userid ~= nil then
                local charid = g_userTokens[p.userid] or PrimaryCharacterOf(p.userid)
                if charid ~= nil then
                    speaking[charid] = true
                end
            end
        end
    end

    local changed = {}
    for charid, _ in pairs(speaking) do
        if not g_speakingTokens[charid] then
            changed[#changed + 1] = charid
        end
    end
    for charid, _ in pairs(g_speakingTokens) do
        if not speaking[charid] then
            changed[#changed + 1] = charid
        end
    end
    g_speakingTokens = speaking
    for _, charid in ipairs(changed) do
        RefreshTokenEmotes(charid)
    end
end

--- Called often (the title bar's microphone thinks at ~10 Hz in a game):
--- joins or leaves the call as the setting and account allow, announces our
--- voice token, and updates the speaking emotes.
function DiscordVoice.Tick()
    g_status = dmhub.discordStatus
    local status = g_status

    if DiscordVoice.Available() then
        local now = dmhub.Time()
        if status.account == "ready" and status.voice == "off" and g_leftGameId ~= dmhub.gameid and now >= g_nextJoinAttempt then
            g_nextJoinAttempt = now + JOIN_RETRY_SECONDS
            dmhub.DiscordJoinVoice()
        end
    elseif status.voice ~= "off" then
        dmhub.DiscordLeaveVoice()
    end

    AnnounceMyToken(status)
    UpdateSpeakingTokens(status)
end

Keybinds.Register{
    command = "togglevoicemute",
    name = "Toggle Voice Mute",
    section = "gameplay",
}

Commands.togglevoicemute = function(str)
    if DiscordVoice.Available() then
        DiscordVoice.ToggleMuted()
    end
end

----------------------------------------------------------------------
-- The voice section of the Heroes popout (HeroesPanel.lua places it).
----------------------------------------------------------------------

local COLOR_GOOD = "#58b060"
local COLOR_BAD = "#e04545"
local COLOR_WARN = "#d8b23a"
--plain colors for selfStyle writes (theme tokens are for styles and constructors).
local COLOR_ICON = "#e8e8e8"
local COLOR_IDLE = "#7a7a7a"

--shared with the title bar microphone (CodexTitleBar.lua).
DiscordVoice.colors = { good = COLOR_GOOD, bad = COLOR_BAD, warn = COLOR_WARN, icon = COLOR_ICON, idle = COLOR_IDLE }

--- The key bound to a command, for display ("Not bound" when none).
--- @param command string
--- @return string
function DiscordVoice.BindingText(command)
    local key = dmhub.GetCommandBinding(command)
    if key == nil or key == "" then
        return "Not bound"
    end
    return key
end

--- One line of text describing the voice state, for tooltips and the section.
--- @return string
function DiscordVoice.StatusText()
    local s = DiscordVoice.Status()
    if s.account == "notlinked" then
        return "Discord is not linked."
    elseif s.account == "linking" then
        return "Waiting for you to approve Codex in Discord..."
    elseif s.account == "connecting" then
        return "Connecting to Discord..."
    elseif s.account == "error" then
        return s.accountError or "Discord sign-in failed."
    elseif s.voice == "joining" or s.voice == "connecting" then
        return "Joining voice..."
    elseif s.voice == "connected" then
        if s.pushToTalk then
            return "Talking (push to talk)"
        elseif s.muted then
            return "In voice, muted"
        end
        return "In voice, mic on"
    elseif s.voiceError ~= nil then
        return s.voiceError
    end
    return "Not in voice."
end

--a small square icon button with an on/off look.
local function IconToggle(args)
    local iconPanel = gui.Panel{
        width = 16,
        height = 16,
        halign = "center",
        valign = "center",
        bgimage = args.icon,
        bgcolor = "@fg",
        interactable = false,
    }
    local resultPanel
    resultPanel = gui.Panel{
        classes = {"heroChip"},
        width = 28,
        height = 28,
        rmargin = 6,
        valign = "center",
        hover = function(element)
            gui.Tooltip(element.data.tooltip or "")(element)
        end,
        click = args.click,
        data = { tooltip = nil },
        --icon, color and tooltip for the current state.
        setState = function(element, icon, color, tooltip)
            iconPanel.bgimage = icon
            iconPanel.selfStyle.bgcolor = color
            element.data.tooltip = tooltip
        end,
        iconPanel,
    }
    return resultPanel
end

--a labelled slider row.
local function SliderRow(label, minValue, maxValue, value, onchange)
    return gui.Panel{
        width = "100%",
        height = 28,
        flow = "horizontal",
        gui.Label{
            classes = {"heroMuted"},
            fontSize = 12,
            text = label,
            width = 96,
            height = "auto",
            valign = "center",
        },
        gui.Slider{
            width = 300,
            height = 26,
            sliderWidth = 240,
            labelWidth = 50,
            labelFormat = "%d%%",
            minValue = minValue,
            maxValue = maxValue,
            round = true,
            value = value,
            valign = "center",
            change = function(element)
                onchange(element.value)
            end,
        },
    }
end

--a microphone or speaker chooser; filled in once Discord lists the devices.
local function DeviceRow(label, kind)
    local dropdown
    dropdown = gui.Dropdown{
        width = 300,
        height = 26,
        valign = "center",
        options = {{ id = "", text = "Loading..." }},
        idChosen = "",
        change = function(element)
            ---@cast element Dropdown
            local deviceId = element.idChosen --[[@as string]]
            if deviceId ~= "" then
                dmhub.DiscordSetAudioDevice(kind, deviceId)
            end
        end,
    }
    return gui.Panel{
        width = "100%",
        height = 30,
        flow = "horizontal",
        tmargin = 2,
        --devices: the table DiscordGetAudioDevices calls back with.
        devices = function(element, devices)
            local list = kind == "input" and devices.inputs or devices.outputs
            local options = {}
            for _, d in ipairs(list) do
                options[#options + 1] = { id = d.id, text = d.name }
            end
            if #options == 0 then
                options[1] = { id = "", text = "None found" }
            end
            dropdown.options = options
            dropdown.idChosen = (kind == "input" and devices.input or devices.output) or options[1].id
        end,
        gui.Label{
            classes = {"heroMuted"},
            fontSize = 12,
            text = label,
            width = 96,
            height = "auto",
            valign = "center",
        },
        dropdown,
    }
end

--a hotkey row: what it is bound to, and a button to change it.
local function HotkeyRow(label, command)
    local keyLabel = gui.Label{
        fontSize = 12,
        color = "@fg",
        text = DiscordVoice.BindingText(command),
        width = 120,
        height = "auto",
        valign = "center",
    }
    return gui.Panel{
        width = "100%",
        height = 28,
        flow = "horizontal",
        gui.Label{
            classes = {"heroMuted"},
            fontSize = 12,
            text = label,
            width = 96,
            height = "auto",
            valign = "center",
        },
        keyLabel,
        gui.Button{
            classes = {"sizeS"},
            text = "Set key",
            width = "auto",
            height = "auto",
            hpad = 10,
            vpad = 2,
            borderBox = true,
            valign = "center",
            click = function(element)
                element.popup = Keybinds.ShowBindPopup{
                    command = command,
                    name = label,
                    destroy = function()
                        if keyLabel.valid then
                            keyLabel.text = DiscordVoice.BindingText(command)
                        end
                    end,
                }
            end,
        },
    }
end

--one person in the call: who, whether they are talking, and how loud they are for us.
local function ParticipantRow(p)
    local dot = gui.Panel{
        width = 8,
        height = 8,
        cornerRadius = 4,
        bgimage = "panels/square.png",
        bgcolor = "@fgMuted",
        valign = "center",
        rmargin = 6,
    }
    local children = {
        dot,
        gui.Label{
            classes = {"heroName"},
            fontSize = 13,
            text = p.isSelf and (p.name .. " (you)") or p.name,
            width = 130,
            height = "auto",
            valign = "center",
            textWrap = false,
        },
    }
    local muteToggle = nil
    if not p.isSelf then
        children[#children + 1] = gui.Slider{
            width = 170,
            height = 24,
            sliderWidth = 120,
            labelWidth = 44,
            labelFormat = "%d%%",
            minValue = 0,
            maxValue = 200,
            round = true,
            value = p.volume or 100,
            valign = "center",
            change = function(element)
                dmhub.DiscordSetParticipantVolume(p.id, element.value)
            end,
        }
        muteToggle = IconToggle{
            icon = "phosphor/speaker-high-fill.png",
            click = function(element)
                local status = DiscordVoice.Status()
                for _, q in ipairs(status.participants) do
                    if q.id == p.id then
                        dmhub.DiscordSetParticipantLocalMute(p.id, not q.localMute)
                    end
                end
            end,
        }
        children[#children + 1] = muteToggle
    end
    return gui.Panel{
        width = "100%",
        height = 30,
        flow = "horizontal",
        --q: this participant's entry in the latest status.
        updateParticipant = function(element, q)
            dot.selfStyle.bgcolor = q.speaking and COLOR_GOOD or COLOR_IDLE
            if muteToggle ~= nil then
                if q.localMute then
                    muteToggle:FireEvent("setState", "phosphor/speaker-slash-fill.png", COLOR_BAD, "Muted for you. Click to hear them again.")
                else
                    muteToggle:FireEvent("setState", "phosphor/speaker-high-fill.png", COLOR_ICON, "Click to mute them, for you only.")
                end
            end
        end,
        children = children,
    }
end

--- The voice section for the Heroes popout: status, join/leave and linking,
--- mute and deafen, volumes, devices, noise suppression, hotkeys, and the
--- people in the call. Collapsed while voice is not available in this game.
--- @return Panel
function DiscordVoice.CreatePanel()
    local statusLabel = gui.Label{
        classes = {"heroName"},
        fontSize = 13,
        text = "",
        width = 250,
        height = "auto",
        valign = "center",
        textWrap = true,
    }

    local actionButton = gui.Button{
        classes = {"sizeS"},
        text = "",
        width = "auto",
        height = "auto",
        hpad = 12,
        vpad = 4,
        borderBox = true,
        halign = "right",
        valign = "center",
        data = { action = nil },
        click = function(element)
            local action = element.data.action
            if action == "link" then
                DiscordVoice.Link()
            elseif action == "join" then
                DiscordVoice.Join()
            elseif action == "leave" then
                DiscordVoice.Leave()
            end
        end,
    }

    local muteToggle = IconToggle{
        icon = "phosphor/microphone-fill.png",
        click = function(element)
            DiscordVoice.ToggleMuted()
        end,
    }

    local deafenToggle = IconToggle{
        icon = "phosphor/headphones-fill.png",
        click = function(element)
            local s = DiscordVoice.Status()
            dmhub.DiscordSetVoiceDeafened(not s.deafened)
        end,
    }

    local s0 = DiscordVoice.Status()

    local deviceRows = {
        DeviceRow("Microphone", "input"),
        DeviceRow("Speakers", "output"),
    }

    local participantsPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 4,
        data = { rows = {}, key = "" },
    }

    --everything below the status line, shown once signed in to Discord.
    local controlsPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 6,

        gui.Panel{
            width = "100%",
            height = 32,
            flow = "horizontal",
            muteToggle,
            deafenToggle,
            gui.Label{
                classes = {"heroMuted"},
                fontSize = 11,
                text = "Mute and deafen apply to every Discord call in Codex.",
                width = 300,
                height = "auto",
                valign = "center",
                textWrap = true,
            },
        },

        SliderRow("Mic volume", 0, 100, s0.inputVolume or 100, function(value)
            dmhub.DiscordSetVoiceInputVolume(value)
        end),
        SliderRow("Voice volume", 0, 200, s0.outputVolume or 100, function(value)
            dmhub.DiscordSetVoiceOutputVolume(value)
        end),

        deviceRows[1],
        deviceRows[2],

        gui.Check{
            text = "Noise suppression",
            value = s0.noiseSuppression ~= false,
            fontSize = 12,
            tmargin = 4,
            change = function(element)
                dmhub.DiscordSetVoiceNoiseSuppression(element.value)
            end,
        },

        HotkeyRow("Push to talk", "pushtotalk"),
        HotkeyRow("Toggle mute", "togglevoicemute"),

        participantsPanel,

        gui.Label{
            classes = {"heroMuted"},
            fontSize = 11,
            text = "Unlink Discord",
            width = "auto",
            height = "auto",
            tmargin = 6,
            halign = "right",
            hover = function(element)
                gui.Tooltip("Sign this Codex account out of Discord voice.")(element)
            end,
            click = function(element)
                DiscordVoice.Unlink()
            end,
        },
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        tmargin = 4,

        create = function(element)
            if dmhub.DiscordGetAudioDevices(function(devices)
                if mod.unloaded or not element.valid then
                    return
                end
                for _, row in ipairs(deviceRows) do
                    row:FireEvent("devices", devices)
                end
            end) == false then
                for _, row in ipairs(deviceRows) do
                    row:SetClass("collapsed", true)
                end
            end
            element:FireEvent("think")
        end,

        thinkTime = 0.2,
        think = function(element)
            local available = DiscordVoice.Available()
            element:SetClass("collapsed", not available)
            if not available then
                return
            end
            local s = DiscordVoice.Status()
            statusLabel.text = DiscordVoice.StatusText()

            local action, actionText = nil, ""
            if s.account == "notlinked" or s.account == "error" then
                action, actionText = "link", "Link Discord"
            elseif s.account == "ready" then
                if s.voice == "off" then
                    action, actionText = "join", "Join voice"
                else
                    action, actionText = "leave", "Leave voice"
                end
            end
            actionButton.data.action = action
            actionButton.text = actionText
            actionButton:SetClass("collapsed", action == nil)

            controlsPanel:SetClass("collapsed", s.account ~= "ready")

            local pttKey = DiscordVoice.BindingText("pushtotalk")
            if s.muted then
                muteToggle:FireEvent("setState", "phosphor/microphone-slash-fill.png", COLOR_BAD, string.format("Muted. Click to unmute. Push to talk: %s", pttKey))
            else
                muteToggle:FireEvent("setState", "phosphor/microphone-fill.png", s.transmitting and COLOR_GOOD or COLOR_ICON, "Mic on. Click to mute.")
            end
            if s.deafened then
                deafenToggle:FireEvent("setState", "phosphor/speaker-slash-fill.png", COLOR_BAD, "Deafened: you hear nobody. Click to hear again.")
            else
                deafenToggle:FireEvent("setState", "phosphor/headphones-fill.png", COLOR_ICON, "Click to deafen (hear nobody).")
            end

            --rebuild the people rows only when who is in the call changes.
            local ids = {}
            for _, p in ipairs(s.participants) do
                ids[#ids + 1] = p.id
            end
            local key = table.concat(ids, ",")
            if key ~= participantsPanel.data.key then
                participantsPanel.data.key = key
                local rows = {}
                local children = {}
                if #s.participants > 0 then
                    children[1] = gui.Label{
                        classes = {"heroSection"},
                        text = "In the call",
                        width = "100%",
                        height = 20,
                        valign = "center",
                    }
                end
                for _, p in ipairs(s.participants) do
                    local row = ParticipantRow(p)
                    rows[p.id] = row
                    children[#children + 1] = row
                end
                participantsPanel.data.rows = rows
                participantsPanel.children = children
            end
            for _, p in ipairs(s.participants) do
                local row = participantsPanel.data.rows[p.id]
                if row ~= nil then
                    row:FireEvent("updateParticipant", p)
                end
            end
        end,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Label{
                classes = {"heroSection"},
                text = "Voice",
                width = "100%",
                height = 20,
                hpad = 12,
                borderBox = true,
                valign = "center",
            },
            gui.Panel{
                classes = {"heroHairline"},
                width = "100%",
                height = 1,
            },
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            hpad = 12,
            vpad = 6,
            borderBox = true,

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                statusLabel,
                actionButton,
            },

            controlsPanel,
        },
    }
    return resultPanel
end
