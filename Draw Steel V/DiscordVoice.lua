local mod = dmhub.GetModLoading()

--Discord voice chat in a game. PROTOTYPE: only admins can switch it on.
--
--A Director who is an admin switches on the game setting "Discord Voice" (only
--admins see it); an Encounter of the Week game an admin hosts has it switched
--on at setup (EncounterOfTheWeek.lua). In a game with it on, everyone who has
--linked their Discord account joins the game's Discord call in the background (the engine's DiscordControllerVoice.cs; one
--Discord lobby per game). The title bar shows a microphone next to the
--network indicator (CodexTitleBar.lua), and its think drives DiscordVoice.Tick.
--Right-clicking it opens the voice menu (DiscordVoice.CreateMenu); the full
--voice settings are a section of Settings > Audio (DiscordVoice.CreateSettingsPanel,
--placed by SettingsScreen.lua). While someone
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
    help = "Prototype: everyone in this game can talk to each other over Discord voice. Only admins see this setting.",
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

--charid -> dmhub.Time() a tick last heard that token's user speaking. A token
--counts as speaking until SPEAKING_LINGER_SECONDS after that, so the balloon
--does not vanish the instant Discord's speaking flag drops between words.
local g_speakingTokens = {}

local SPEAKING_LINGER_SECONDS = 0.6

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

--the Discord Voice setting is on in the real game we are in (any user, any build).
local function VoiceOnInThisGame()
    return dmhub.inGame and (not dmhub.isLobbyGame) and g_setting:Get() == true
end

--- True when voice is on for this user in this game: anyone in a real game
--- with the Discord Voice setting on, in a build with Discord available.
--- @return boolean
function DiscordVoice.Available()
    if not VoiceOnInThisGame() then
        return false
    end
    local account = DiscordVoice.Status().account
    return account ~= "unsupported" and account ~= "off"
end

function DiscordVoice.Link()
    return dmhub.DiscordLink()
end

--the modal layer of the open link offer, so a second click does not stack another.
local g_offerLayer = nil

--- Explains what linking Discord gives before sending the player to Discord's
--- sign-in (Discord requires the benefits to come first). Continue starts the
--- browser sign-in, or the code sign-in when useCode is true. Not Now keeps an
--- unlinked player on a provisional account, so Discord features keep working
--- without one. Outside a real game there is no modal layer to show it on, so
--- it links straight away (the titlescreen has its own offer, the Infernal
--- Contract dialog's Discord card).
--- @param useCode boolean|nil
function DiscordVoice.OfferLink(useCode)
    local gh = rawget(_G, "gamehud")
    if not (dmhub.inGame and not dmhub.isLobbyGame and gh ~= nil) then
        if useCode then
            return DiscordVoice.LinkWithCode()
        end
        return DiscordVoice.Link()
    end
    if g_offerLayer ~= nil then
        return
    end

    local function Close()
        local layer = g_offerLayer
        g_offerLayer = nil
        if layer ~= nil then
            gui.CloseModalInLayer(layer)
        end
    end

    local function NotNow()
        Close()
        local s = dmhub.discordStatus
        if s ~= nil and s.account == "notlinked" and s.provisionalUnavailable ~= true then
            dmhub.DiscordUseProvisional()
        end
    end

    local function Line(text, args)
        args = args or {}
        return gui.Label{
            classes = {"modalMessage"},
            width = "100%",
            height = "auto",
            textWrap = true,
            fontSize = args.fontSize,
            color = args.color,
            lmargin = args.lmargin,
            vmargin = args.vmargin or 3,
            text = text,
        }
    end

    local dialog = gui.Panel{
        classes = {"framedPanel"},
        width = 560,
        height = "auto",
        halign = "center",
        valign = "center",
        flow = "vertical",
        pad = 24,
        borderBox = true,
        swallowPress = true,

        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 32,
            gui.Panel{
                bgimage = "phosphor/discord-logo-fill.png",
                bgcolor = "#5865F2",
                width = 28,
                height = 28,
                valign = "center",
            },
            gui.Label{
                fontSize = 22,
                bold = true,
                width = "auto",
                height = "auto",
                valign = "center",
                lmargin = 10,
                text = "Link Discord",
            },
        },
        gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            vmargin = 14,
            Line("Linking your Discord account lets you:"),
            Line("- See your Discord friends in the Codex, message them, and invite them to your games.", {lmargin = 12}),
            Line("- Let your Discord friends see what you're playing and ask to join you.", {lmargin = 12}),
            Line("- Talk with your party over Discord voice as yourself.", {lmargin = 12}),
            Line("Discord will ask you to approve the Codex. You can unlink at any time in Settings > Account.", {color = "@fgMuted", fontSize = 14, vmargin = 10}),
        },
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "center",
            gui.Button{
                classes = {"sizeL"},
                text = "Continue to Discord",
                hmargin = 6,
                click = function()
                    Close()
                    if useCode then
                        DiscordVoice.LinkWithCode()
                    else
                        DiscordVoice.Link()
                    end
                end,
            },
            gui.Button{
                classes = {"sizeL"},
                text = "Not Now",
                hmargin = 6,
                click = function()
                    NotNow()
                end,
            },
        },
    }

    local backdrop = gui.Panel{
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#000000b0",
        styles = ThemeEngine.GetStyles(),
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function()
            NotNow()
        end,
        destroy = function()
            --swept away by something else (leaving the game).
            g_offerLayer = nil
        end,
        dialog,
    }
    g_offerLayer = gui.ShowModal(backdrop)
end

--- The fallback sign-in: a code the user enters at discord.com/activate on any
--- device, for when the browser sign-in's approval never reaches Codex.
function DiscordVoice.LinkWithCode()
    return dmhub.DiscordLinkWithCode()
end

--- Stops waiting for a sign-in (browser or code).
function DiscordVoice.CancelLink()
    return dmhub.DiscordCancelLink()
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
    if charid == nil then
        return false
    end
    local heard = g_speakingTokens[charid]
    return heard ~= nil and dmhub.Time() - heard < SPEAKING_LINGER_SECONDS
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

    --a token heard now is (re)stamped; one not heard stays until its linger
    --runs out. Emotes refresh only when a token starts or finally stops.
    local now = dmhub.Time()
    local changed = {}
    for charid, _ in pairs(speaking) do
        if g_speakingTokens[charid] == nil then
            changed[#changed + 1] = charid
        end
        g_speakingTokens[charid] = now
    end
    for charid, heard in pairs(g_speakingTokens) do
        if now - heard >= SPEAKING_LINGER_SECONDS then
            g_speakingTokens[charid] = nil
            changed[#changed + 1] = charid
        end
    end
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
        elseif status.account == "notlinked" and status.provisionalUnavailable ~= true and g_leftGameId ~= dmhub.gameid and now >= g_nextJoinAttempt then
            --joining voice is a use of Discord: a player who has not linked
            --gets a provisional account, and the branch above joins once it is ready.
            g_nextJoinAttempt = now + JOIN_RETRY_SECONDS
            dmhub.DiscordUseProvisional()
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
-- Voice UI: the title bar microphone's menu (DiscordVoice.CreateMenu,
-- opened by CodexTitleBar.lua on right-click) and the "Discord Voice"
-- section of Settings > Audio (DiscordVoice.CreateSettingsPanel, placed by
-- SettingsScreen.lua).
----------------------------------------------------------------------

local COLOR_GOOD = "#58b060"
local COLOR_BAD = "#e04545"
local COLOR_WARN = "#d8b23a"
--plain colors for selfStyle writes (theme tokens are for styles and constructors).
local COLOR_ICON = "#e8e8e8"
local COLOR_IDLE = "#7a7a7a"

--shared with the title bar microphone (CodexTitleBar.lua).
DiscordVoice.colors = { good = COLOR_GOOD, bad = COLOR_BAD, warn = COLOR_WARN, icon = COLOR_ICON, idle = COLOR_IDLE }

--the menu's look: the same quiet rows as the Heroes popout.
local g_menuStyles = {
    {
        selectors = {"voiceName"},
        fontSize = 14,
        color = "@fg",
    },
    {
        selectors = {"voiceMuted"},
        fontSize = 11,
        color = "@fgMuted",
    },
    {
        selectors = {"voiceSection"},
        fontSize = 11,
        bold = true,
        color = "@fgMuted",
    },
    {
        selectors = {"voiceHairline"},
        bgimage = "panels/square.png",
        bgcolor = "@border",
        opacity = 0.35,
    },
    {
        selectors = {"voiceChip"},
        bgimage = "panels/square.png",
        bgcolor = "@bg",
        borderWidth = 1,
        borderColor = "@border",
        cornerRadius = 4,
    },
    {
        selectors = {"voiceChip", "hover"},
        bgcolor = "@bgAlt",
    },
}

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
    elseif s.account == "linking" and s.deviceCode ~= nil then
        return "Sign in to Discord with a code."
    elseif s.account == "linking" then
        return "Waiting for you to approve Codex in Discord... Approved and nothing happened? Use a code instead."
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

--- True when the Discord Voice settings section shows, in a build with Discord:
--- for an admin always (devices, volumes and sensitivity belong to this
--- machine, not the game), for anyone else while in a game with voice on.
--- @return boolean
function DiscordVoice.SettingsAvailable()
    if not (dmhub.isAdminAccount or VoiceOnInThisGame()) then
        return false
    end
    local account = DiscordVoice.Status().account
    return account ~= "unsupported" and account ~= "off"
end

--- Opens Settings on the Audio tab, home of the Discord Voice section.
function DiscordVoice.OpenSettings()
    dmhub.ShowPlayerSettings{ tab = "Audio" }
end

--the account / call button for a status: Link Discord, Try again, Join voice, Leave voice, or none.
--- @return string|nil action
--- @return string text
local function VoiceAction(s)
    if s.account == "notlinked" then
        --first sign-in: explain what linking gives before going to Discord.
        return "offer", "Link Discord"
    elseif s.account == "error" then
        return "link", "Link Discord"
    elseif s.account == "linking" and s.deviceCode ~= nil then
        --the code panel has its own Cancel.
        return nil, ""
    elseif s.account == "linking" then
        --the approval can go missing (a closed browser tab, an unseen Discord window); linking again starts over.
        return "link", "Try again"
    elseif s.account == "ready" then
        if s.voice == "off" then
            return "join", "Join voice"
        end
        return "leave", "Leave voice"
    end
    return nil, ""
end

local function RunVoiceAction(action)
    if action == "offer" then
        DiscordVoice.OfferLink(false)
    elseif action == "link" then
        DiscordVoice.Link()
    elseif action == "join" then
        DiscordVoice.Join()
    elseif action == "leave" then
        DiscordVoice.Leave()
    end
end

--a Link / Join / Leave button that follows the status (fire "refreshVoice").
local function ActionButton(args)
    local button
    button = gui.Button{
        classes = args.classes,
        text = "",
        width = "auto",
        height = "auto",
        hpad = 12,
        vpad = 4,
        borderBox = true,
        halign = args.halign,
        valign = "center",
        data = { action = nil },
        click = function(element)
            RunVoiceAction(element.data.action)
        end,
        refreshVoice = function(element, s)
            local action, text = VoiceAction(s)
            element.data.action = action
            element.text = text
            element:SetClass("collapsed", action == nil)
        end,
    }
    return button
end

--"Use a code instead": the code sign-in, offered until signed in (fire "refreshVoice").
--The browser sign-in has to get back to Codex through 127.0.0.1, which some
--browsers and security software block; the code sign-in never needs that.
--args.offer: a player who has not started signing in sees the link offer
--first (leave it off where the benefits are already shown beside the button).
local function CodeLinkButton(args)
    return gui.Button{
        classes = args.classes,
        text = "Use a code instead",
        width = "auto",
        height = "auto",
        hpad = 12,
        vpad = 4,
        lmargin = args.lmargin,
        borderBox = true,
        halign = args.halign,
        valign = "center",
        hover = function(element)
            gui.Tooltip("Sign in by entering a code at discord.com/activate, on this computer or your phone. Use this when the browser sign-in does not come back to Codex.")(element)
        end,
        click = function(element)
            if args.offer and DiscordVoice.Status().account == "notlinked" then
                DiscordVoice.OfferLink(true)
            else
                DiscordVoice.LinkWithCode()
            end
        end,
        refreshVoice = function(element, s)
            local signingIn = s.account == "notlinked" or s.account == "error" or s.account == "linking"
            element:SetClass("collapsed", not signingIn or s.deviceCode ~= nil)
        end,
    }
end

--"Link Discord" for a player on a provisional account, who is signed in
--(so the action button offers voice) but has no Discord account linked
--(fire "refreshVoice").
local function ProvisionalLinkButton(args)
    return gui.Button{
        classes = args.classes,
        text = "Link Discord",
        width = "auto",
        height = "auto",
        hpad = 12,
        vpad = 4,
        lmargin = args.lmargin,
        borderBox = true,
        halign = args.halign,
        valign = "center",
        hover = function(element)
            gui.Tooltip("You are using voice without a Discord account. Link Discord to use your own Discord account and friends.")(element)
        end,
        click = function(element)
            DiscordVoice.OfferLink(false)
        end,
        refreshVoice = function(element, s)
            element:SetClass("collapsed", not (s.account == "ready" and s.provisional == true))
        end,
    }
end

--the code sign-in while it waits: the code, where to enter it, how long it
--lasts, and Open / Copy / Cancel (fire "refreshVoice").
local function DeviceCodePanel(args)
    local instructions = gui.Label{
        fontSize = 13,
        color = "@fg",
        text = "",
        width = "100%",
        height = "auto",
        textWrap = true,
    }
    local codeLabel = gui.Label{
        fontSize = 26,
        bold = true,
        color = "@fg",
        text = "",
        width = "auto",
        height = "auto",
        halign = args.halign,
        vmargin = 4,
    }
    local expiresLabel = gui.Label{
        fontSize = 12,
        color = "@fgMuted",
        text = "",
        width = "100%",
        height = "auto",
        tmargin = 4,
    }
    local function SmallButton(text, click)
        return gui.Button{
            classes = {"sizeS"},
            text = text,
            width = "auto",
            height = "auto",
            hpad = 10,
            vpad = 4,
            rmargin = 6,
            borderBox = true,
            valign = "center",
            click = click,
        }
    end
    return gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 6,
        refreshVoice = function(element, s)
            element:SetClass("collapsed", s.deviceCode == nil)
            if s.deviceCode == nil then
                return
            end
            local site = string.gsub(s.deviceUrl or "https://discord.com/activate", "^https://", "")
            instructions.text = string.format("On any device (your phone works too), go to %s and enter this code:", site)
            codeLabel.text = s.deviceCode
            local seconds = math.floor(s.deviceExpiresIn or 0)
            expiresLabel.text = string.format("The code expires in %d:%02d.", seconds // 60, seconds % 60)
        end,
        instructions,
        codeLabel,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            SmallButton("Open Discord", function()
                dmhub.DiscordOpenLinkCodePage()
            end),
            SmallButton("Copy code", function()
                local code = DiscordVoice.Status().deviceCode
                if code ~= nil then
                    dmhub.CopyToClipboard(code)
                end
            end),
            SmallButton("Cancel", function()
                DiscordVoice.CancelLink()
            end),
        },
        expiresLabel,
    }
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
        classes = {"voiceChip"},
        width = 28,
        height = 28,
        rmargin = args.rmargin or 6,
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

--mute and deafen buttons that follow the status (fire "refreshVoice").
local function MuteToggle()
    return IconToggle{
        icon = "phosphor/microphone-fill.png",
        click = function(element)
            DiscordVoice.ToggleMuted()
        end,
    }
end

local function RefreshMuteToggles(muteToggle, deafenToggle, s)
    if s.muted then
        muteToggle:FireEvent("setState", "phosphor/microphone-slash-fill.png", COLOR_BAD, string.format("Muted. Click to unmute. Push to talk: %s", DiscordVoice.BindingText("pushtotalk")))
    else
        muteToggle:FireEvent("setState", "phosphor/microphone-fill.png", s.transmitting and COLOR_GOOD or COLOR_ICON, "Mic on. Click to mute.")
    end
    if s.deafened then
        deafenToggle:FireEvent("setState", "phosphor/speaker-slash-fill.png", COLOR_BAD, "Deafened: you hear nobody. Click to hear again.")
    else
        deafenToggle:FireEvent("setState", "phosphor/headphones-fill.png", COLOR_ICON, "Click to deafen (hear nobody).")
    end
end

--a labelled volume slider for the menu.
local function MenuSliderRow(label, maxValue, value, onchange)
    return gui.Panel{
        width = "100%",
        height = 28,
        flow = "horizontal",
        gui.Label{
            classes = {"voiceMuted"},
            fontSize = 12,
            text = label,
            width = 84,
            height = "auto",
            valign = "center",
        },
        gui.Slider{
            width = 210,
            height = 24,
            sliderWidth = 160,
            labelWidth = 46,
            labelFormat = "%d%%",
            minValue = 0,
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
            classes = {"voiceName"},
            fontSize = 13,
            text = p.isSelf and (p.name .. " (you)") or p.name,
            width = 104,
            height = "auto",
            valign = "center",
            textWrap = false,
        },
    }
    local muteToggle = nil
    if not p.isSelf then
        children[#children + 1] = gui.Slider{
            width = 152,
            height = 24,
            sliderWidth = 104,
            labelWidth = 44,
            labelFormat = "%d%%",
            minValue = 0,
            maxValue = 200,
            round = true,
            value = p.volume or 100,
            valign = "center",
            hover = function(element)
                gui.Tooltip("How loud they are, for you only.")(element)
            end,
            change = function(element)
                dmhub.DiscordSetParticipantVolume(p.id, element.value)
            end,
        }
        muteToggle = IconToggle{
            icon = "phosphor/speaker-high-fill.png",
            rmargin = 0,
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

local function Hairline()
    return gui.Panel{
        classes = {"voiceHairline"},
        width = "100%",
        height = 1,
        vmargin = 6,
    }
end

--- The title bar microphone's menu: the status with Link / Join / Leave, mute
--- and deafen, mic and voice volume, everyone in the call with their own volume
--- and mute, and a button to the full settings. close dismisses the menu.
--- @param close fun()
--- @return Panel
function DiscordVoice.CreateMenu(close)
    local statusLabel = gui.Label{
        classes = {"voiceName"},
        fontSize = 13,
        text = "",
        width = 190,
        height = "auto",
        valign = "center",
        textWrap = true,
    }

    local actionButton = ActionButton{ classes = {"sizeS"}, halign = "right" }
    local codeButton = CodeLinkButton{ classes = {"sizeS"}, halign = "right", offer = true }
    local provisionalLinkButton = ProvisionalLinkButton{ classes = {"sizeS"}, halign = "right" }
    local deviceCodePanel = DeviceCodePanel{ halign = "center" }

    local muteToggle = MuteToggle()
    local deafenToggle = IconToggle{
        icon = "phosphor/headphones-fill.png",
        click = function(element)
            local s = DiscordVoice.Status()
            dmhub.DiscordSetVoiceDeafened(not s.deafened)
        end,
    }

    local s0 = DiscordVoice.Status()

    local participantsPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
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
                classes = {"voiceMuted"},
                text = "Mute and deafen apply to every Discord call in Codex.",
                width = 220,
                height = "auto",
                valign = "center",
                textWrap = true,
            },
        },

        MenuSliderRow("Mic volume", 100, s0.inputVolume or 100, function(value)
            dmhub.DiscordSetVoiceInputVolume(value)
        end),
        MenuSliderRow("Voice volume", 200, s0.outputVolume or 100, function(value)
            dmhub.DiscordSetVoiceOutputVolume(value)
        end),

        participantsPanel,
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        styles = ThemeEngine.MergeStyles(g_menuStyles),

        create = function(element)
            element:FireEvent("think")
        end,

        thinkTime = 0.2,
        think = function(element)
            local s = DiscordVoice.Status()
            statusLabel.text = DiscordVoice.StatusText()
            actionButton:FireEvent("refreshVoice", s)
            codeButton:FireEvent("refreshVoice", s)
            provisionalLinkButton:FireEvent("refreshVoice", s)
            deviceCodePanel:FireEvent("refreshVoice", s)
            controlsPanel:SetClass("collapsed", s.account ~= "ready")
            RefreshMuteToggles(muteToggle, deafenToggle, s)

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
                    children[1] = Hairline()
                    children[2] = gui.Label{
                        classes = {"voiceSection"},
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

        gui.Label{
            classes = {"voiceSection"},
            text = "Discord Voice",
            width = "100%",
            height = 20,
            valign = "center",
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 2,
            statusLabel,
            actionButton,
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 4,
            codeButton,
        },
        deviceCodePanel,

        controlsPanel,

        Hairline(),

        gui.Button{
            classes = {"sizeS"},
            text = "Voice Settings...",
            width = "auto",
            height = "auto",
            hpad = 12,
            vpad = 4,
            borderBox = true,
            halign = "right",
            click = function(element)
                close()
                DiscordVoice.OpenSettings()
            end,
        },
    }
    return resultPanel
end

----------------------------------------------------------------------
-- The Discord Voice section of Settings > Audio.
----------------------------------------------------------------------

--muted text for notes under settings controls.
local COLOR_NOTE = "#a0a0a0"

--a Settings row: a label on the left, a control on the right (the settings
--screen's formRow / form classes).
local function SettingsRow(label, control, args)
    args = args or {}
    return gui.Panel{
        classes = {"formRow"},
        width = "90%",
        height = args.height or "auto",
        halign = "center",
        flow = "horizontal",
        gui.Label{
            classes = {"form"},
            width = "50%",
            valign = args.labelValign or "center",
            text = label,
        },
        control,
    }
end

local function SettingsCheck(text, value, onchange)
    return gui.Panel{
        classes = {"formRow"},
        width = "90%",
        halign = "center",
        gui.Check{
            value = value,
            text = text,
            change = function(element)
                onchange(element.value)
            end,
        },
    }
end

local function SettingsSlider(maxValue, value, onchange)
    return gui.Slider{
        width = "45%",
        height = 30,
        sliderWidth = 200,
        labelWidth = 60,
        labelFormat = "%d%%",
        minValue = 0,
        maxValue = maxValue,
        round = true,
        value = value,
        valign = "center",
        change = function(element)
            onchange(element.value)
        end,
    }
end

--a microphone or speaker chooser; filled in once Discord lists the devices.
local function DeviceDropdown(kind)
    return gui.Dropdown{
        classes = {"form"},
        width = "45%",
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
        --devices: the table DiscordGetAudioDevices calls back with.
        devices = function(element, devices)
            ---@cast element Dropdown
            local list = kind == "input" and devices.inputs or devices.outputs
            local options = {}
            for _, d in ipairs(list) do
                options[#options + 1] = { id = d.id, text = d.name }
            end
            if #options == 0 then
                options[1] = { id = "", text = "None found" }
            end
            element.options = options
            element.idChosen = (kind == "input" and devices.input or devices.output) or options[1].id
        end,
    }
end

--a hotkey control: what the command is bound to, and a button to change it.
local function HotkeyControl(label, command)
    local keyLabel = gui.Label{
        fontSize = 16,
        text = DiscordVoice.BindingText(command),
        width = 140,
        height = "auto",
        valign = "center",
    }
    return gui.Panel{
        width = "45%",
        height = 30,
        flow = "horizontal",
        valign = "center",
        keyLabel,
        gui.Button{
            classes = {"sizeS"},
            text = "Set Key",
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

--The live mic level, drawn under the sensitivity slider's track on the same
--dB scale (-100 to 0). Manual sensitivity: a tick marks the threshold and the bar
--is green while you are louder than it. Automatic: green while Discord sends
--your voice. sensitivity is {automatic = bool, threshold = dB}, kept current
--by the section.
local function LevelMeter(sensitivity, trackInset)
    local fill = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = COLOR_IDLE,
        width = 1,
        height = "100%",
        halign = "left",
        valign = "center",
        opacity = 0,
    }
    local marker = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = COLOR_ICON,
        width = 2,
        height = "100%",
        halign = "left",
        valign = "center",
    }
    local note = gui.Label{
        fontSize = 13,
        color = COLOR_NOTE,
        text = "",
        width = "100%",
        height = "auto",
        halign = "left",
        tmargin = 2,
    }
    local track = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "#00000099",
        width = string.format("100%%-%d", trackInset),
        height = 8,
        halign = "left",
        tmargin = 2,
        flow = "none",
        fill,
        marker,

        thinkTime = 0.05,
        think = function(element)
            local width = element.renderedWidth
            local s = DiscordVoice.Status()
            local level = dmhub.discordMicLevel

            marker:SetClass("collapsed", sensitivity.automatic)
            marker.x = math.floor(width * (sensitivity.threshold + 100) / 100) - 1

            if level == nil then
                fill.selfStyle.opacity = 0
                if s.voice ~= "connected" then
                    note.text = "Join voice in a game to test your microphone here."
                else
                    note.text = "No sound from your microphone yet."
                end
                return
            end

            local open
            if sensitivity.automatic then
                open = s.transmitting
                note.text = "The bar turns green while your voice is being sent."
            else
                open = level >= sensitivity.threshold
                note.text = "Your voice is sent while the bar passes the marker."
            end
            fill.selfStyle.opacity = 1
            fill.selfStyle.width = math.max(1, math.floor(width * (level + 100) / 100))
            fill.selfStyle.bgcolor = open and COLOR_GOOD or COLOR_WARN
        end,
    }
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        track,
        note,
    }
end

--- The Discord Voice section of Settings > Audio: the account (link, join,
--- leave, unlink), devices, volumes, input sensitivity with a live mic level,
--- voice processing, and the voice hotkeys. Everything but the account row
--- waits until signed in to Discord.
--- @return Panel
function DiscordVoice.CreateSettingsPanel()
    local s0 = DiscordVoice.Status()

    local statusLabel = gui.Label{
        fontSize = 16,
        text = "",
        width = "100%",
        height = "auto",
        textWrap = true,
    }
    local actionButton = ActionButton{ classes = {"sizeS"}, halign = "left" }
    local codeButton = CodeLinkButton{ classes = {"sizeS"}, halign = "left", lmargin = 8, offer = true }
    local provisionalLinkButton = ProvisionalLinkButton{ classes = {"sizeS"}, halign = "left", lmargin = 8 }
    local deviceCodePanel = DeviceCodePanel{ halign = "left" }
    local unlinkButton = gui.Button{
        classes = {"sizeS"},
        text = "Unlink Discord",
        width = "auto",
        height = "auto",
        hpad = 12,
        vpad = 4,
        lmargin = 8,
        borderBox = true,
        valign = "center",
        hover = function(element)
            gui.Tooltip("Sign this Codex account out of Discord voice.")(element)
        end,
        click = function(element)
            DiscordVoice.Unlink()
        end,
    }

    local accountRow = SettingsRow("Discord account", gui.Panel{
        width = "45%",
        height = "auto",
        flow = "vertical",
        valign = "center",
        statusLabel,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 4,
            actionButton,
            codeButton,
            provisionalLinkButton,
            unlinkButton,
        },
        deviceCodePanel,
    })

    --the Discord Voice game setting, for an admin hosting this game. It is
    --here as well as in Settings > Game because a directorless game's host
    --(every Encounter of the Week game) has no Game tab.
    local canSwitchGameVoice = dmhub.isAdminAccount and dmhub.isDMOrPlayerHost and dmhub.inGame and not dmhub.isLobbyGame
    local gameVoiceCheck = gui.Check{
        value = g_setting:Get() == true,
        text = "Voice in this game (for everyone in it)",
        change = function(element)
            if element.value ~= (g_setting:Get() == true) then
                g_setting:Set(element.value)
            end
        end,
    }

    local devices = {
        DeviceDropdown("input"),
        DeviceDropdown("output"),
    }
    local deviceRows = {
        SettingsRow("Microphone", devices[1]),
        SettingsRow("Speakers", devices[2]),
    }

    --the section's view of the input sensitivity, shared with the meter.
    local m_sensitivity = {
        automatic = s0.sensitivityAutomatic ~= false,
        threshold = s0.sensitivity or -60,
    }
    local SENSITIVITY_LABEL_WIDTH = 60
    local sensitivitySlider = gui.Slider{
        classes = {cond(m_sensitivity.automatic, "collapsed")},
        width = "100%",
        height = 30,
        sliderWidth = 200,
        labelWidth = SENSITIVITY_LABEL_WIDTH,
        labelFormat = "%d dB",
        minValue = -100,
        maxValue = 0,
        round = true,
        value = m_sensitivity.threshold,
        valign = "center",
        change = function(element)
            m_sensitivity.threshold = element.value
            dmhub.DiscordSetVoiceSensitivity(false, element.value)
        end,
    }

    --hidden until signed in to Discord.
    local controlsPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        deviceRows[1],
        deviceRows[2],

        SettingsRow("Mic volume", SettingsSlider(100, s0.inputVolume or 100, function(value)
            dmhub.DiscordSetVoiceInputVolume(value)
        end)),
        SettingsRow("Voice volume", SettingsSlider(200, s0.outputVolume or 100, function(value)
            dmhub.DiscordSetVoiceOutputVolume(value)
        end)),

        --input sensitivity: how loud you must be before your voice is sent.
        SettingsCheck("Automatically determine input sensitivity", m_sensitivity.automatic, function(value)
            m_sensitivity.automatic = value
            dmhub.DiscordSetVoiceSensitivity(value, m_sensitivity.threshold)
            sensitivitySlider:SetClass("collapsed", value)
        end),
        SettingsRow("Input sensitivity", gui.Panel{
            width = "45%",
            height = "auto",
            flow = "vertical",
            valign = "center",
            sensitivitySlider,
            LevelMeter(m_sensitivity, SENSITIVITY_LABEL_WIDTH + 4),
        }),

        SettingsCheck(cond(s0.krisp, "Noise suppression (Krisp)", "Noise suppression"), s0.noiseSuppression ~= false, function(value)
            dmhub.DiscordSetVoiceNoiseSuppression(value)
        end),
        SettingsCheck("Echo cancellation", s0.echoCancellation ~= false, function(value)
            dmhub.DiscordSetVoiceEchoCancellation(value)
        end),
        SettingsCheck("Automatic gain control", s0.autoGainControl ~= false, function(value)
            dmhub.DiscordSetVoiceAutoGainControl(value)
        end),

        SettingsRow("Push to talk", HotkeyControl("Push to talk", "pushtotalk")),
        SettingsRow("Toggle mute", HotkeyControl("Toggle mute", "togglevoicemute")),
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        create = function(element)
            if dmhub.DiscordGetAudioDevices(function(list)
                if mod.unloaded or not element.valid then
                    return
                end
                for _, dropdown in ipairs(devices) do
                    dropdown:FireEvent("devices", list)
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
            local s = DiscordVoice.Status()
            statusLabel.text = DiscordVoice.StatusText()
            actionButton:FireEvent("refreshVoice", s)
            codeButton:FireEvent("refreshVoice", s)
            provisionalLinkButton:FireEvent("refreshVoice", s)
            deviceCodePanel:FireEvent("refreshVoice", s)
            --a provisional account has no Discord account to unlink.
            unlinkButton:SetClass("collapsed", s.account ~= "ready" or s.provisional == true)
            controlsPanel:SetClass("collapsed", s.account ~= "ready")
            --follow changes made elsewhere (the Game tab, another session).
            if canSwitchGameVoice and gameVoiceCheck.value ~= (g_setting:Get() == true) then
                gameVoiceCheck.value = g_setting:Get() == true
            end
        end,

        gui.Panel{
            classes = {"formRow", cond(not canSwitchGameVoice, "collapsed")},
            width = "90%",
            halign = "center",
            gameVoiceCheck,
        },
        accountRow,
        controlsPanel,
    }
    return resultPanel
end

--- The Discord block of Settings > Account: whether Discord is linked, what
--- linking gives (shown above the button, before Discord's sign-in, as Discord
--- requires), Link / Use a code instead, and Unlink with a confirmation.
--- Discord wants linking and unlinking in a permanent place next to the other
--- account links, for everyone, not only in voice games. nil when the build has
--- no Discord or the Discord features are off ("discordsocial").
--- @return Panel|nil
function DiscordVoice.CreateAccountSettingsPanel()
    if dmhub.GetSettingValue("discordsocial") ~= true then
        return nil
    end
    local s0 = dmhub.discordStatus
    if s0 == nil or s0.account == "unsupported" then
        return nil
    end

    --true while the unlink confirmation shows in place of the Unlink button.
    local m_confirmUnlink = false

    local function AccountText(s)
        if s.account == "off" then
            return "Discord Integration is off. Turn it on in the General tab to link Discord."
        elseif s.account == "ready" and s.provisional == true then
            return "Not linked. You are using Discord in the Codex without a Discord account."
        elseif s.account == "ready" then
            return string.format("Linked to Discord as %s.", s.displayName or "your Discord account")
        elseif s.account == "notlinked" then
            return "Not linked."
        end
        return DiscordVoice.StatusText()
    end

    local function Label(args)
        return gui.Label{
            width = "100%",
            maxWidth = 600,
            height = "auto",
            fontSize = args.fontSize or 14,
            color = args.color,
            textWrap = true,
            vmargin = 2,
            text = args.text or "",
        }
    end

    local function Button(text, click, lmargin)
        return gui.Button{
            text = text,
            width = "auto",
            minWidth = 120,
            height = 30,
            hpad = 12,
            borderBox = true,
            fontSize = 14,
            halign = "left",
            valign = "center",
            lmargin = lmargin,
            click = click,
        }
    end

    local statusLabel = Label{}
    local benefitsLabel = Label{
        text = "Link your Discord account to see your Discord friends in the Codex, message them, invite them to your games and let them ask to join you, and talk with your party over Discord voice. Your Discord friends will see what you are playing in the Codex. You can unlink here at any time.",
    }

    local linkButton = Button("Link Discord", function()
        DiscordVoice.Link()
    end)
    local codeButton = CodeLinkButton{ halign = "left", lmargin = 8 }
    local unlinkButton = Button("Unlink Discord", function()
        m_confirmUnlink = true
    end)
    local deviceCodePanel = DeviceCodePanel{ halign = "left" }

    local confirmPanel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        Label{
            text = "Unlink your Discord account? Your Discord friends and messages will no longer show in the Codex, and you will leave Discord voice. You can link it again at any time.",
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            vmargin = 4,
            Button("Unlink", function()
                m_confirmUnlink = false
                DiscordVoice.Unlink()
            end),
            Button("Cancel", function()
                m_confirmUnlink = false
            end, 8),
        },
    }

    local buttonRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        vmargin = 4,
        linkButton,
        codeButton,
        unlinkButton,
    }

    local panel
    panel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        vmargin = 16,

        create = function(element)
            element:FireEvent("think")
        end,

        thinkTime = 0.2,
        think = function(element)
            --the titlescreen has no voice tick to refresh the shared status.
            g_status = dmhub.discordStatus
            local s = DiscordVoice.Status()
            local linked = s.account == "ready" and s.provisional ~= true
            local signingIn = s.account == "linking"
            local canLink = s.account == "notlinked" or s.account == "error" or (s.account == "ready" and s.provisional == true)

            statusLabel.text = AccountText(s)
            benefitsLabel:SetClass("collapsed", linked or s.account == "off" or s.account == "connecting")

            --Try again restarts a browser sign-in whose approval never came back.
            linkButton:SetClass("collapsed", not (canLink or (signingIn and s.deviceCode == nil)))
            linkButton.text = cond(signingIn, "Try again", "Link Discord")
            codeButton:FireEvent("refreshVoice", s)
            deviceCodePanel:FireEvent("refreshVoice", s)

            if not linked then
                m_confirmUnlink = false
            end
            unlinkButton:SetClass("collapsed", not linked or m_confirmUnlink)
            confirmPanel:SetClass("collapsed", not m_confirmUnlink)
        end,

        gui.Label{
            bold = true,
            fontSize = 16,
            width = "auto",
            height = "auto",
            text = "Discord",
        },
        statusLabel,
        benefitsLabel,
        buttonRow,
        deviceCodePanel,
        confirmPanel,
    }
    return panel
end
