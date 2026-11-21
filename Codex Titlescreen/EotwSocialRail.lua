local mod = dmhub.GetModLoading()

--Encounter of the Week: the social rail. A column down the right edge of the
--town, on the map and in every location, holding:
--
--  * Friends: the player's Steam and Discord friends who play the Codex,
--    online first, each with what they are doing and, when it can be joined
--    or watched, the buttons for it. A friend in an Encounter of the Week
--    party is described from the City's own records (the party, its
--    encounter, its slots); anything else from Steam rich presence or the
--    friend's Discord activity.
--  * Public Games: every public party in the City, the ones still taking
--    heroes first. A party whose host blows the horn lights up for a few
--    seconds and keeps a horn and its countdown while the horn sounds.
--  * Town Chat: the town's chat (and, in a party view, the party's), built by
--    EncounterOfTheWeek.lua and handed in as ctx.chat.
--
--The rail collapses to a narrow strip (online friends' faces and the chat's
--unread mark); the town lays itself out in the space left of it.
--
--Who plays the Codex: the codexFriendsLookup cloud function maps Steam and
--Discord ids to Codex accounts. Until it answers (or if it cannot be reached)
--a friend counts when Steam or Discord shows them in the Codex right now.
--
--Design: EncounterOfTheWeek/EncounterOfTheWeek.md, "The social rail".

EotwSocialRail = {}

local T = UIText.T
local TP = UIText.Plural

EotwSocialRail.WIDTH = 380
EotwSocialRail.COLLAPSED_WIDTH = 76

local TEXT = "#f6ead0"
local BODY = "#ece3cf"
local DIM = "#c9bfa9"
local GOLD = "#d9b56a"
local GREEN = "#43b581"
local AMBER = "#e0a83a"
local RED = "#f04747"
local GREY = "#8a8478"

--How long a party lights up when its horn is blown.
local HORN_FLASH_SECONDS = 6
--Ask the lookup again after this long, and never more often than the gap.
local LOOKUP_REFRESH_SECONDS = 10 * 60
local LOOKUP_MIN_GAP_SECONDS = 60
--the most ids of each kind the lookup takes in one call.
local LOOKUP_MAX_IDS = 500

--Fixed row heights, so the lists can be sized to their contents.
local FRIEND_ROW = 58
--a friend in a party has a third line: host and slots.
local FRIEND_ROW_DETAIL = 74
--the buttons sit in a column at a row's right.
local ACTIONS_WIDTH = 104
local OFFLINE_TOGGLE_ROW = 32
local GAME_ROW = 66
local SECTION_TITLE = 38
local HEADER = 64
local FRIENDS_MAX = 340
local GAMES_MAX = 250
local CHAT_MIN = 330

--The account lookup, kept for the session: { [steamId] = uid } and
--{ [discordId] = uid }, which ids were asked about, and when.
local g_lookup = {
    steam = {},
    discord = {},
    askedSteam = {},
    askedDiscord = {},
    at = nil,
    pending = false,
    revision = 0,
}

--The Steam friends list as last read, and the revision it was read at.
local g_steamCache = { list = nil, revision = nil }

--Where the friends come from. Fields so a test can stand in for Steam and
--Discord (a dev build has no Steam): each source is a revision that moves when
--its list changes, and the list.
EotwSocialRail.sources = {
    steamRevision = function()
        return dmhub.steamFriendsRevision or 0
    end,
    steamFriends = function()
        return dmhub.GetSteamFriends() or {}
    end,
    discordFriends = function()
        return dmhub.DiscordGetRelationships() or {}
    end,
}

--Ask the City's account lookup about friends it has not heard of yet, or
--again once the last answer is old.
local function MaybeLookup(steamIds, discordIds)
    if g_lookup.pending then
        return
    end
    local now = dmhub.Time()
    if g_lookup.at ~= nil and now - g_lookup.at < LOOKUP_MIN_GAP_SECONDS then
        return
    end
    local stale = g_lookup.at == nil or now - g_lookup.at >= LOOKUP_REFRESH_SECONDS
    local fresh = false
    for _,id in ipairs(steamIds) do
        if not g_lookup.askedSteam[id] then
            fresh = true
        end
    end
    for _,id in ipairs(discordIds) do
        if not g_lookup.askedDiscord[id] then
            fresh = true
        end
    end
    if not stale and not fresh then
        return
    end
    if #steamIds == 0 and #discordIds == 0 then
        return
    end
    --the lookup takes 500 of each per call.
    local Cap = function(ids)
        if #ids <= LOOKUP_MAX_IDS then
            return ids
        end
        local capped = {}
        for i = 1, LOOKUP_MAX_IDS do
            capped[i] = ids[i]
        end
        return capped
    end
    steamIds = Cap(steamIds)
    discordIds = Cap(discordIds)
    g_lookup.pending = true
    g_lookup.at = now
    net.Post{
        url = dmhub.cloudFunctionsBaseUrl .. "/codexFriendsLookup",
        data = {
            steamIds = steamIds,
            discordIds = discordIds,
        },
        success = function(response)
            g_lookup.pending = false
            for _,id in ipairs(steamIds) do
                g_lookup.askedSteam[id] = true
            end
            for _,id in ipairs(discordIds) do
                g_lookup.askedDiscord[id] = true
            end
            if type(response) == "table" and response.ok then
                if type(response.steam) == "table" then
                    for id,uid in pairs(response.steam) do
                        g_lookup.steam[id] = uid
                    end
                end
                if type(response.discord) == "table" then
                    for id,uid in pairs(response.discord) do
                        g_lookup.discord[id] = uid
                    end
                end
                g_lookup.revision = g_lookup.revision + 1
            else
                printf("EotW rail: friends lookup refused: %s", tostring(type(response) == "table" and response.error or response))
            end
        end,
        error = function(message)
            g_lookup.pending = false
            printf("EotW rail: friends lookup failed: %s", tostring(message))
        end,
    }
end

local function DiscordReady()
    if dmhub.GetSettingValue("discordsocial") ~= true then
        return false
    end
    local status = nil
    pcall(function() status = dmhub.discordStatus end)
    return status ~= nil and status.account == "ready"
end

local function DiscordRevision()
    local status = nil
    pcall(function() status = dmhub.discordStatus end)
    if status == nil then
        return 0
    end
    return status.socialRevision or 0
end

---@class EotwRailFriend
---@field key string
---@field uid string|nil
---@field name string
---@field avatar string|nil
---@field steam table|nil
---@field discord table|nil

--Our friends who play the Codex, merged across Steam and Discord by Codex
--account where the lookup knows it.
---@return EotwRailFriend[]
local function GatherFriends()
    ---@type table<string, EotwRailFriend>
    local byKey = {}
    ---@type EotwRailFriend[]
    local list = {}
    local steamIds = {}
    local discordIds = {}

    local Entry = function(key, uid, name, avatar)
        local entry = byKey[key]
        if entry == nil then
            entry = { key = key, uid = uid, name = name, avatar = avatar }
            byKey[key] = entry
            list[#list+1] = entry
        end
        if entry.avatar == nil then
            entry.avatar = avatar
        end
        return entry
    end

    --Steam builds a fresh list on each call: read it only when it changed.
    local steamRevision = EotwSocialRail.sources.steamRevision()
    if g_steamCache.list == nil or g_steamCache.revision ~= steamRevision then
        g_steamCache.list = EotwSocialRail.sources.steamFriends()
        g_steamCache.revision = steamRevision
    end
    for _,f in ipairs(g_steamCache.list) do
        steamIds[#steamIds+1] = f.steamId
        local uid = g_lookup.steam[f.steamId]
        if uid ~= nil or f.playingCodex then
            --until the lookup answers, a Steam-only account's id is the
            --default one ("steam-" + SteamID64).
            uid = uid or ("steam-" .. f.steamId)
            local entry = Entry(uid, uid, f.name, f.avatar)
            entry.steam = f
        end
    end

    if DiscordReady() then
        for _,r in ipairs(EotwSocialRail.sources.discordFriends()) do
            if r.relationship == "friend" then
                discordIds[#discordIds+1] = r.id
                local uid = g_lookup.discord[r.id]
                if uid ~= nil or r.group == "playing" then
                    local entry = Entry(uid or ("discord:" .. r.id), uid, r.displayName or r.username or "?", r.avatar)
                    entry.discord = r
                end
            end
        end
    end

    MaybeLookup(steamIds, discordIds)
    return list
end

--The party this account belongs to in the City, if any.
local function FindParty(games, uid)
    if uid == nil or games == nil then
        return nil, nil
    end
    for gameid,record in pairs(games) do
        if record.hostUserid == uid or (record.players ~= nil and record.players[uid] ~= nil) then
            return gameid, record
        end
    end
    return nil, nil
end

local function SteamOnline(f)
    return f ~= nil and f.state ~= nil and f.state ~= "offline"
end

local function DiscordOnline(r)
    return r ~= nil and r.status ~= nil and r.status ~= "offline" and r.status ~= "blocked"
end

---@class EotwRailStatus
---@field rank integer 1 = joinable, 2 = in a game, 3 = in town, 4 = in the Codex, 5 = online, 6 = away, 7 = offline
---@field dot string
---@field line string
---@field detail string|nil
---@field buttons {text: string, click: fun()}[]

--What a friend is doing, best source first: their party in the City, their
--being in town, Steam rich presence, Discord activity, then plain online
--state.
---@param friend EotwRailFriend
---@param ctx table
---@param games table|nil
---@param presence table|nil
---@return EotwRailStatus
local function FriendStatus(friend, ctx, games, presence)
    local steam = friend.steam
    local discord = friend.discord
    local online = SteamOnline(steam) or DiscordOnline(discord)
    local away = (steam ~= nil and (steam.state == "away" or steam.state == "snooze"))
        or (discord ~= nil and discord.status == "idle")
    local busy = (steam ~= nil and steam.state == "busy") or (discord ~= nil and discord.status == "dnd")
    local dot = GREY
    if online then
        dot = cond(busy, RED, cond(away, AMBER, GREEN))
    end

    --joining a friend through their Steam "Join Game" (a party they are
    --forming, private ones included: the connect string carries the code)
    --or asking through Discord.
    local PlatformJoin = function(buttons)
        if steam ~= nil and steam.playingCodex and type(steam.connect) == "string" and steam.connect ~= "" then
            buttons[#buttons+1] = {
                text = T("eotw.rail.join_button"),
                click = function()
                    if not dmhub.JoinSteamFriend(steam.steamId) then
                        ctx.Note(T("eotw.rail.join_failed", { name = friend.name }), true)
                    end
                end,
            }
            return true
        end
        if discord ~= nil and discord.activity ~= nil and discord.activity.joinable then
            buttons[#buttons+1] = {
                text = T("eotw.rail.ask_join_button"),
                click = function()
                    DiscordFriends.AskToJoin({ id = discord.id, displayName = friend.name }, function(text, isError)
                        ctx.Note(text, isError)
                    end)
                end,
            }
            return true
        end
        return false
    end

    local gameid, record = FindParty(games, friend.uid)
    if gameid ~= nil and record ~= nil then
        local info = ctx.DescribeGame(gameid, record)
        local buttons = info.buttons
        if #buttons == 0 and record.status == "open" then
            PlatformJoin(buttons)
        end
        local line = cond(record.status == "open",
            T("eotw.rail.friend_forming", { encounter = info.encounter }),
            T("eotw.rail.friend_underway", { encounter = info.encounter }))
        return {
            rank = cond(#buttons > 0 and not info.member, 1, 2),
            dot = dot,
            line = line,
            detail = info.detail,
            buttons = buttons,
        }
    end

    if friend.uid ~= nil and presence ~= nil and presence[friend.uid] ~= nil then
        return { rank = 3, dot = dot, line = T("eotw.rail.friend_in_town"), buttons = {} }
    end

    if (steam ~= nil and steam.playingCodex) or (discord ~= nil and discord.group == "playing") then
        local line = T("eotw.rail.friend_in_codex")
        if steam ~= nil and type(steam.status) == "string" and steam.status ~= "" then
            line = steam.status
        elseif discord ~= nil and discord.activity ~= nil then
            local a = discord.activity
            if type(a.details) == "string" and a.details ~= "" then
                line = a.details
            elseif type(a.state) == "string" and a.state ~= "" then
                line = a.state
            end
        end
        local buttons = {}
        local joinable = PlatformJoin(buttons)
        return { rank = cond(joinable, 1, 4), dot = dot, line = line, buttons = buttons }
    end

    if online then
        local line = T("eotw.rail.friend_online")
        if steam ~= nil and steam.playingOther then
            line = T("eotw.rail.friend_other_game")
        elseif busy then
            line = T("eotw.rail.friend_busy")
        elseif away then
            line = T("eotw.rail.friend_away")
        end
        return { rank = cond(away, 6, 5), dot = dot, line = line, buttons = {} }
    end

    return { rank = 7, dot = dot, line = T("eotw.rail.friend_offline"), buttons = {} }
end

local railStyles = {
    {
        selectors = { "eotwRail" },
        bgimage = "panels/square.png",
        bgcolor = "#0e0b08f2",
        borderWidth = 1,
        borderColor = "#d9b56a40",
    },
    {
        selectors = { "eotwRailIconButton" },
        bgimage = "panels/square.png",
        bgcolor = "#ffffff00",
        borderWidth = 1,
        borderColor = "#d9b56a55",
        cornerRadius = 6,
    },
    {
        selectors = { "eotwRailIconButton", "hover" },
        bgcolor = "#3a2e1ad0",
        borderColor = GOLD,
    },
    {
        selectors = { "eotwRailIcon" },
        bgcolor = GOLD,
    },
    {
        selectors = { "eotwRailIcon", "parent:hover" },
        bgcolor = "#ffe9b0",
    },
    {
        selectors = { "eotwRailSectionTitle" },
        bgimage = "panels/square.png",
        bgcolor = "#ffffff00",
    },
    {
        selectors = { "eotwRailSectionTitle", "hover" },
        bgcolor = "#ffffff0a",
    },
    {
        selectors = { "eotwRailRow" },
        bgimage = "panels/square.png",
        bgcolor = "#ffffff00",
        cornerRadius = 8,
        borderWidth = 1,
        borderColor = "#ffffff00",
        transitionTime = 0.3,
    },
    {
        selectors = { "eotwRailRow", "hover" },
        bgcolor = "#ffffff08",
    },
    {
        selectors = { "eotwRailRow", "horn" },
        bgcolor = "#d9b56a1c",
        borderColor = "#d9b56a66",
    },
    {
        selectors = { "eotwRailRow", "hornFlash" },
        bgcolor = "#d9b56a66",
        borderColor = "#ffe9b0",
    },
    {
        selectors = { "eotwRailButton" },
        bgimage = "panels/square.png",
        bgcolor = "#3a2e1ab0",
        borderWidth = 1,
        borderColor = "#d9b56a99",
        cornerRadius = 5,
    },
    {
        selectors = { "eotwRailButton", "hover" },
        bgcolor = "#5a4a2acc",
        borderColor = "#ffe9b0",
    },
}

--A small square icon button (collapse, close, offline toggle...).
local function IconButton(icon, tooltip, click, size)
    size = size or 32
    return gui.Panel{
        classes = { "eotwRailIconButton" },
        width = size,
        height = size,
        valign = "center",
        hmargin = 3,
        hover = function(element)
            gui.Tooltip(tooltip)(element)
        end,
        press = function(element)
            audio.FireSoundEvent("Mouse.Click")
            click(element)
        end,
        gui.Panel{
            classes = { "eotwRailIcon" },
            interactable = false,
            bgimage = icon,
            width = size * 0.55,
            height = size * 0.55,
            halign = "center",
            valign = "center",
        },
    }
end

--A compact action button in a row's action column.
local function RowAction(action, height)
    return gui.Label{
        classes = { "eotwRailButton" },
        text = action.text,
        fontSize = 13,
        bold = true,
        color = TEXT,
        width = "100%",
        height = height,
        vmargin = 1,
        borderBox = true,
        textAlignment = "center",
        halign = "right",
        hover = function(element)
            audio.FireSoundEvent("Mouse.Hover")
        end,
        press = function(element)
            audio.FireSoundEvent("Mouse.Click")
            action.click()
        end,
    }
end

--A friend's face: their avatar, or their initial on a disc, with a status dot.
local function Avatar(name, avatar, dot, size)
    local initial = string.upper(string.sub(name or "?", 1, 1))
    return gui.Panel{
        width = size,
        height = size,
        valign = "top",
        flow = "none",
        gui.Panel{
            width = size,
            height = size,
            bgimage = avatar or "panels/square.png",
            bgcolor = cond(avatar ~= nil, "white", "#5a4a2a"),
            cornerRadius = size / 2,
            interactable = false,
            gui.Label{
                classes = { cond(avatar ~= nil, "collapsed", "shown") },
                text = initial,
                fontSize = size * 0.45,
                bold = true,
                color = TEXT,
                width = "100%",
                height = "100%",
                textAlignment = "center",
            },
        },
        gui.Panel{
            floating = true,
            halign = "right",
            valign = "bottom",
            width = size * 0.32,
            height = size * 0.32,
            bgimage = "panels/square.png",
            bgcolor = dot,
            cornerRadius = size * 0.16,
            borderWidth = 2,
            borderColor = "#0e0b08",
            interactable = false,
        },
    }
end

--A row's buttons, stacked at its right: one, or two smaller ones.
local function ActionColumn(buttons)
    local height = cond(#buttons > 1, 22, 28)
    local children = {}
    for _,action in ipairs(buttons) do
        children[#children+1] = RowAction(action, height)
    end
    return gui.Panel{
        width = ACTIONS_WIDTH,
        height = "auto",
        halign = "right",
        valign = "center",
        lmargin = 6,
        flow = "vertical",
        children = children,
    }
end

local function SourceIcons(friend)
    local icons = {}
    if friend.steam ~= nil then
        icons[#icons+1] = gui.Panel{
            bgimage = "phosphor/steam-logo-fill.png",
            bgcolor = DIM,
            width = 14,
            height = 14,
            lmargin = 6,
            valign = "center",
            interactable = false,
        }
    end
    if friend.discord ~= nil then
        icons[#icons+1] = gui.Panel{
            bgimage = "phosphor/discord-logo-fill.png",
            bgcolor = DIM,
            width = 14,
            height = 14,
            lmargin = 6,
            valign = "center",
            interactable = false,
        }
    end
    return icons
end

--How tall a friend's row is.
---@param status EotwRailStatus
local function FriendRowHeight(status)
    return cond(status.detail ~= nil, FRIEND_ROW_DETAIL, FRIEND_ROW)
end

---@param friend EotwRailFriend
---@param status EotwRailStatus
local function FriendRow(friend, status)
    local hasButtons = #status.buttons > 0
    local nameRow = { gui.Label{
        text = friend.name,
        fontSize = 17,
        bold = true,
        color = TEXT,
        width = "auto",
        maxWidth = cond(hasButtons, 120, 220),
        height = "auto",
        textOverflow = "ellipsis",
        valign = "center",
    } }
    for _,icon in ipairs(SourceIcons(friend)) do
        nameRow[#nameRow+1] = icon
    end

    local lineColor = cond(status.rank <= 4, GOLD, DIM)
    local body = {
        gui.Panel{
            width = "100%",
            height = 22,
            flow = "horizontal",
            children = nameRow,
        },
        gui.Label{
            text = status.line,
            fontSize = 14,
            color = lineColor,
            width = "100%",
            height = 18,
            textAlignment = "topleft",
            textOverflow = "ellipsis",
        },
    }
    if status.detail ~= nil then
        body[#body+1] = gui.Label{
            text = status.detail,
            fontSize = 13,
            color = DIM,
            width = "100%",
            height = 16,
            textAlignment = "topleft",
            textOverflow = "ellipsis",
        }
    end

    local children = {
        Avatar(friend.name, friend.avatar, status.dot, 38),
        gui.Panel{
            width = cond(hasButtons, "100%-" .. tostring(48 + ACTIONS_WIDTH + 6), "100%-48"),
            height = "100%",
            lmargin = 10,
            flow = "vertical",
            children = body,
        },
    }
    if hasButtons then
        children[#children+1] = ActionColumn(status.buttons)
    end

    return gui.Panel{
        classes = { "eotwRailRow" },
        width = "100%",
        height = FriendRowHeight(status),
        flow = "horizontal",
        hpad = 8,
        vpad = 6,
        borderBox = true,
        children = children,
    }
end

--Milliseconds a party's horn still sounds, or 0.
local function HornRemainingMs(record)
    if type(record.hornUntil) ~= "number" then
        return 0
    end
    return math.max(0, record.hornUntil - dmhub.serverTimeMilliseconds)
end

local function FormatCountdown(ms)
    local secs = math.ceil(ms / 1000)
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

--- Builds the rail.
--- ctx:
---   height          the screen's height in the town's units.
---   conn()          the City connection, or nil.
---   chat            the town chat panel, placed in the rail's chat section.
---   DescribeGame(gameid, record) -> {encounter, detail, buttons, member, joinable}
---   OnWidthChanged(width)  the rail opened or collapsed to width.
---   OnChatShown(shown)     the chat became visible (true) or hidden.
---   ChatUnread() -> boolean
---   CloseTown()
---   created(panel)  optional: called with the rail once it is built.
---   OnChatResized() optional: the chat section changed height.
--- @param ctx table
--- @return Panel
function EotwSocialRail.Create(ctx)
    local height = ctx.height

    local state = {
        collapsed = false,
        friendsOpen = true,
        gamesOpen = true,
        showOffline = false,
        signature = nil,
        cityRevision = 0,
        --horns: the hornUntil last seen per party, and until when it flashes.
        hornSeen = nil,
        hornFlashUntil = {},
        noteUntil = 0,
    }

    --- @type Panel
    local rail = nil
    --- @type Panel
    local expanded = nil
    --- @type Panel
    local mini = nil
    --- @type Panel
    local friendsList = nil
    --- @type Panel
    local friendsTitle = nil
    --- @type Panel
    local gamesList = nil
    --- @type Panel
    local gamesTitle = nil
    --- @type Panel
    local chatHost = nil
    --- @type Panel
    local noteLabel = nil
    --- @type Panel
    local miniFaces = nil
    --- @type Panel
    local miniChatBadge = nil
    --- @type Panel
    local countLabel = nil

    local friendsHeight = 0
    local gamesHeight = 0

    --Sizes the lists to their rows (up to their caps) and gives the chat
    --what is left.
    local Layout = function()
        if friendsList == nil or not friendsList.valid then
            return
        end
        local fh = cond(state.friendsOpen, math.min(friendsHeight, FRIENDS_MAX), 0)
        local gh = cond(state.gamesOpen, math.min(gamesHeight, GAMES_MAX), 0)
        friendsList.selfStyle.height = fh
        friendsList:SetClass("collapsed", fh <= 0)
        gamesList.selfStyle.height = gh
        gamesList:SetClass("collapsed", gh <= 0)
        local noteHeight = cond(noteLabel ~= nil and noteLabel.valid and not noteLabel:HasClass("collapsed"), 26, 0)
        local chatHeight = height - HEADER - SECTION_TITLE * 2 - fh - gh - noteHeight - 12
        if chatHeight < CHAT_MIN then
            --the chat keeps its minimum; the games list gives way first.
            local over = CHAT_MIN - chatHeight
            local cut = math.min(over, gh)
            gh = gh - cut
            over = over - cut
            gamesList.selfStyle.height = gh
            fh = math.max(0, fh - over)
            friendsList.selfStyle.height = fh
            chatHeight = CHAT_MIN
        end
        if chatHost.data.height ~= chatHeight then
            chatHost.data.height = chatHeight
            chatHost.selfStyle.height = chatHeight
            if ctx.OnChatResized ~= nil then
                ctx.OnChatResized()
            end
        end
    end

    local SectionTitle = function(text, isOpen, toggle, created)
        return gui.Panel{
            classes = { "eotwRailSectionTitle" },
            width = "100%",
            height = SECTION_TITLE,
            flow = "horizontal",
            hpad = 14,
            borderBox = true,
            press = function(element)
                audio.FireSoundEvent("Mouse.Click")
                toggle()
            end,
            gui.Panel{
                classes = { "eotwRailIcon" },
                bgimage = cond(isOpen, "phosphor/caret-down-bold.png", "phosphor/caret-right-bold.png"),
                width = 12,
                height = 12,
                valign = "center",
                rmargin = 8,
                interactable = false,
                data = { open = isOpen },
                refreshCaret = function(element, open)
                    element.bgimage = cond(open, "phosphor/caret-down-bold.png", "phosphor/caret-right-bold.png")
                end,
            },
            gui.Label{
                text = "",
                fontSize = 15,
                bold = true,
                color = GOLD,
                width = "100%-24",
                height = "auto",
                valign = "center",
                interactable = false,
                create = function(element)
                    created(element, text)
                end,
            },
        }
    end

    local Note = function(text, isError)
        if noteLabel == nil or not noteLabel.valid then
            return
        end
        noteLabel.text = text
        noteLabel.selfStyle.color = cond(isError, "#ff8888", BODY)
        noteLabel:SetClass("collapsed", false)
        state.noteUntil = dmhub.Time() + 6
        Layout()
    end
    ctx.Note = Note

    --The friends list and the collapsed strip's faces.
    local RefreshFriends = function()
        local conn = ctx.conn()
        local games = conn ~= nil and conn:GetPath("/state/games") or nil
        local presence = conn ~= nil and conn:GetPath("/presence") or nil
        local friends = GatherFriends()
        local rows = {}
        for _,friend in ipairs(friends) do
            rows[#rows+1] = { friend = friend, status = FriendStatus(friend, ctx, games, presence) }
        end
        table.sort(rows, function(a, b)
            if a.status.rank ~= b.status.rank then
                return a.status.rank < b.status.rank
            end
            return string.lower(a.friend.name) < string.lower(b.friend.name)
        end)

        local children = {}
        local total = 0
        local onlineCount = 0
        local offline = {}
        local faces = {}
        for _,row in ipairs(rows) do
            if row.status.rank >= 7 then
                offline[#offline+1] = row
            else
                onlineCount = onlineCount + 1
                children[#children+1] = FriendRow(row.friend, row.status)
                total = total + FriendRowHeight(row.status)
                if #faces < 8 then
                    faces[#faces+1] = gui.Panel{
                        width = 44,
                        height = 44,
                        halign = "center",
                        vmargin = 4,
                        hover = function(element)
                            gui.Tooltip(string.format("%s\n%s", row.friend.name, row.status.line))(element)
                        end,
                        press = function(element)
                            ctx.Expand()
                        end,
                        Avatar(row.friend.name, row.friend.avatar, row.status.dot, 40),
                    }
                end
            end
        end
        if #offline > 0 then
            children[#children+1] = gui.Panel{
                classes = { "eotwRailRow" },
                width = "100%",
                height = OFFLINE_TOGGLE_ROW,
                flow = "horizontal",
                hpad = 10,
                borderBox = true,
                press = function(element)
                    state.showOffline = not state.showOffline
                    state.signature = nil
                end,
                gui.Panel{
                    classes = { "eotwRailIcon" },
                    bgimage = cond(state.showOffline, "phosphor/caret-down-bold.png", "phosphor/caret-right-bold.png"),
                    width = 11,
                    height = 11,
                    valign = "center",
                    rmargin = 8,
                    interactable = false,
                },
                gui.Label{
                    text = T("eotw.rail.offline_toggle", { count = #offline }),
                    fontSize = 15,
                    color = DIM,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    interactable = false,
                },
            }
            total = total + OFFLINE_TOGGLE_ROW
            if state.showOffline then
                for _,row in ipairs(offline) do
                    children[#children+1] = FriendRow(row.friend, row.status)
                    total = total + FriendRowHeight(row.status)
                end
            end
        end
        if #rows == 0 then
            local hint = T("eotw.rail.no_friends")
            if not DiscordReady() and dmhub.GetSettingValue("discordsocial") == true then
                hint = T("eotw.rail.no_friends_link_discord")
            end
            children[#children+1] = gui.Label{
                text = hint,
                fontSize = 15,
                color = DIM,
                italics = true,
                width = "100%",
                height = 60,
                hpad = 14,
                borderBox = true,
                textAlignment = "topleft",
            }
            total = 60
        end

        friendsList.children = children
        friendsHeight = total
        if friendsTitle ~= nil and friendsTitle.valid then
            friendsTitle.text = string.upper(T("eotw.rail.friends_title")) .. "  <color=#c9bfa9><size=85%>" .. T("eotw.rail.friends_online", { count = onlineCount }) .. "</size></color>"
        end
        if miniFaces ~= nil and miniFaces.valid then
            miniFaces.children = faces
        end
    end

    --The public parties: still taking heroes first, then the ones under way.
    local RefreshGames = function()
        local conn = ctx.conn()
        local games = conn ~= nil and conn:GetPath("/state/games") or nil
        local now = dmhub.Time()

        --a horn newly blown (a hornUntil we had not seen) lights its party up;
        --the first look only learns what is already sounding.
        local firstLook = state.hornSeen == nil
        state.hornSeen = state.hornSeen or {}
        for gameid,record in pairs(games or {}) do
            local until_ = record.hornUntil
            if type(until_) == "number" and state.hornSeen[gameid] ~= until_ then
                if not firstLook then
                    state.hornFlashUntil[gameid] = now + HORN_FLASH_SECONDS
                    audio.FireSoundEvent("Notify.Ping")
                end
                state.hornSeen[gameid] = until_
            end
        end

        local entries = {}
        for gameid,record in pairs(games or {}) do
            if record.public == true then
                local info = ctx.DescribeGame(gameid, record)
                local sounding = HornRemainingMs(record) > 0 and record.status == "open"
                local rank = 4
                if info.joinable and record.status == "open" then
                    rank = cond(sounding, 1, 2)
                elseif info.joinable then
                    rank = 3
                end
                entries[#entries+1] = { gameid = gameid, record = record, info = info, rank = rank, sounding = sounding }
            end
        end
        table.sort(entries, function(a, b)
            if a.rank ~= b.rank then
                return a.rank < b.rank
            end
            return a.gameid > b.gameid
        end)

        local children = {}
        for _,entry in ipairs(entries) do
            local gameid = entry.gameid
            local record = entry.record
            local info = entry.info
            local hasButtons = #info.buttons > 0
            local stateText = cond(record.status == "open", T("eotw.rail.game_forming"), T("eotw.rail.game_underway"))
            children[#children+1] = gui.Panel{
                classes = { "eotwRailRow", cond(entry.sounding, "horn", "quiet") },
                width = "100%",
                height = GAME_ROW,
                flow = "horizontal",
                hpad = 10,
                vpad = 6,
                borderBox = true,
                vmargin = 1,
                thinkTime = 0.25,
                data = { pulse = false },
                think = function(element)
                    local flashUntil = state.hornFlashUntil[gameid]
                    if flashUntil ~= nil and dmhub.Time() < flashUntil then
                        element.data.pulse = not element.data.pulse
                        element:SetClass("hornFlash", element.data.pulse)
                    elseif element:HasClass("hornFlash") then
                        element:SetClass("hornFlash", false)
                    end
                end,
                gui.Panel{
                    width = cond(hasButtons, "100%-" .. tostring(ACTIONS_WIDTH + 6), "100%"),
                    height = "100%",
                    flow = "vertical",
                    gui.Panel{
                        width = "100%",
                        height = 20,
                        flow = "horizontal",
                        gui.Panel{
                            classes = { cond(entry.sounding, "shown", "collapsed") },
                            --the horn. (game-icons/hunting-horn.png is not among the
                            --game-icons the app ships.)
                            bgimage = "phosphor/megaphone-fill.png",
                            bgcolor = GOLD,
                            width = 18,
                            height = 18,
                            rmargin = 6,
                            valign = "center",
                            interactable = false,
                        },
                        gui.Label{
                            text = record.name or info.encounter,
                            fontSize = 16,
                            bold = true,
                            color = TEXT,
                            width = "100%-74",
                            height = "auto",
                            textOverflow = "ellipsis",
                            valign = "center",
                        },
                        gui.Label{
                            text = stateText,
                            fontSize = 13,
                            color = cond(record.status == "open", GREEN, DIM),
                            width = "auto",
                            height = "auto",
                            halign = "right",
                            valign = "center",
                            thinkTime = 0.5,
                            think = function(element)
                                local remaining = HornRemainingMs(record)
                                if remaining > 0 and record.status == "open" then
                                    element.text = T("eotw.rail.horn_countdown", { time = FormatCountdown(remaining) })
                                    element.selfStyle.color = GOLD
                                else
                                    element.text = stateText
                                end
                            end,
                        },
                    },
                    gui.Label{
                        text = info.encounter,
                        fontSize = 13,
                        color = BODY,
                        width = "100%",
                        height = 17,
                        textOverflow = "ellipsis",
                    },
                    gui.Label{
                        text = info.detail,
                        fontSize = 13,
                        color = DIM,
                        width = "100%",
                        height = 17,
                        textOverflow = "ellipsis",
                    },
                },
                --built only when there are buttons (a panel built and not used
                --is flagged as a leak).
                hasButtons and ActionColumn(info.buttons) or nil,
            }
        end
        local total = #entries * (GAME_ROW + 2)
        if #entries == 0 then
            children[#children+1] = gui.Label{
                text = T("eotw.rail.no_games"),
                fontSize = 15,
                color = DIM,
                italics = true,
                width = "100%",
                height = 48,
                hpad = 14,
                borderBox = true,
                textAlignment = "topleft",
            }
            total = 48
        end
        gamesList.children = children
        gamesHeight = total
        if gamesTitle ~= nil and gamesTitle.valid then
            gamesTitle.text = string.upper(T("eotw.rail.games_title")) .. cond(#entries > 0, "  <color=#c9bfa9><size=85%>" .. tostring(#entries) .. "</size></color>", "")
        end
    end

    local Rebuild = function()
        if state.collapsed then
            RefreshFriends()
            return
        end
        RefreshFriends()
        RefreshGames()
        Layout()
    end

    local SetCollapsed = function(collapsed)
        if state.collapsed == collapsed then
            return
        end
        state.collapsed = collapsed
        expanded:SetClass("collapsed", collapsed)
        mini:SetClass("collapsed", not collapsed)
        local width = cond(collapsed, EotwSocialRail.COLLAPSED_WIDTH, EotwSocialRail.WIDTH)
        rail.selfStyle.width = width
        state.signature = nil
        ctx.OnChatShown(not collapsed)
        ctx.OnWidthChanged(width)
    end
    ctx.Expand = function()
        SetCollapsed(false)
    end

    expanded = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",

        --header: the town, who is here, collapse and close.
        gui.Panel{
            width = "100%",
            height = HEADER,
            flow = "horizontal",
            hpad = 14,
            borderBox = true,
            bgimage = "panels/square.png",
            bgcolor = "#00000040",
            gui.Panel{
                width = "100%-80",
                height = "auto",
                valign = "center",
                flow = "vertical",
                gui.Label{
                    text = T("eotw.town.plaque_name"),
                    fontFace = "display",
                    fontSize = 24,
                    color = TEXT,
                    width = "auto",
                    height = "auto",
                },
                gui.Label{
                    text = "",
                    fontSize = 13,
                    color = DIM,
                    width = "auto",
                    height = "auto",
                    create = function(element)
                        countLabel = element
                    end,
                },
            },
            IconButton("phosphor/caret-double-right-bold.png", T("eotw.rail.collapse_tooltip"), function()
                SetCollapsed(true)
            end),
            IconButton("phosphor/x-bold.png", T("eotw.rail.close_town_tooltip"), function()
                ctx.CloseTown()
            end),
        },

        SectionTitle("friends", state.friendsOpen, function()
            state.friendsOpen = not state.friendsOpen
            friendsTitle.parent:FireEventTree("refreshCaret", state.friendsOpen)
            Layout()
        end, function(element)
            friendsTitle = element
        end),
        gui.Panel{
            width = "100%",
            height = 0,
            flow = "vertical",
            vscroll = true,
            hpad = 6,
            rpad = 12,
            borderBox = true,
            create = function(element)
                friendsList = element
            end,
        },
        gui.Label{
            classes = { "collapsed" },
            text = "",
            fontSize = 14,
            color = BODY,
            width = "100%",
            height = 26,
            hpad = 14,
            borderBox = true,
            textOverflow = "ellipsis",
            create = function(element)
                noteLabel = element
            end,
        },

        SectionTitle("games", state.gamesOpen, function()
            state.gamesOpen = not state.gamesOpen
            gamesTitle.parent:FireEventTree("refreshCaret", state.gamesOpen)
            Layout()
        end, function(element)
            gamesTitle = element
        end),
        gui.Panel{
            width = "100%",
            height = 0,
            flow = "vertical",
            vscroll = true,
            hpad = 6,
            rpad = 12,
            borderBox = true,
            create = function(element)
                gamesList = element
            end,
        },

        --the chat fills the rest.
        gui.Panel{
            width = "100%",
            height = CHAT_MIN,
            tmargin = 6,
            flow = "vertical",
            bgimage = "panels/square.png",
            bgcolor = "#00000030",
            data = { height = nil },
            create = function(element)
                chatHost = element
            end,
            children = { ctx.chat },
        },
    }

    mini = gui.Panel{
        classes = { "collapsed" },
        width = "100%",
        height = "100%",
        flow = "vertical",
        IconButton("phosphor/caret-double-left-bold.png", T("eotw.rail.expand_tooltip"), function()
            SetCollapsed(false)
        end, 40),
        gui.Panel{
            width = "100%",
            height = "100%-130",
            tmargin = 12,
            flow = "vertical",
            create = function(element)
                miniFaces = element
            end,
        },
        gui.Panel{
            classes = { "eotwRailIconButton" },
            width = 48,
            height = 48,
            halign = "center",
            valign = "bottom",
            bmargin = 16,
            flow = "none",
            hover = function(element)
                gui.Tooltip(T("eotw.chat.title"))(element)
            end,
            press = function(element)
                audio.FireSoundEvent("Mouse.Click")
                SetCollapsed(false)
            end,
            gui.Panel{
                classes = { "eotwRailIcon" },
                interactable = false,
                bgimage = "phosphor/chat-circle-dots-fill.png",
                width = 26,
                height = 26,
                halign = "center",
                valign = "center",
            },
            gui.Panel{
                classes = { "collapsed" },
                floating = true,
                halign = "right",
                valign = "top",
                width = 12,
                height = 12,
                bgimage = "panels/square.png",
                bgcolor = RED,
                cornerRadius = 6,
                interactable = false,
                create = function(element)
                    miniChatBadge = element
                end,
            },
        },
    }

    rail = gui.Panel{
        classes = { "eotwRail" },
        styles = railStyles,
        floating = true,
        halign = "right",
        valign = "top",
        width = EotwSocialRail.WIDTH,
        height = height,
        flow = "none",

        thinkTime = 0.5,
        think = function(element)
            local conn = ctx.conn()
            if countLabel ~= nil and countLabel.valid and conn ~= nil then
                local n = 0
                for _,_ in pairs(conn:GetPath("/presence") or {}) do
                    n = n + 1
                end
                countLabel.text = cond(n > 0, TP("eotw.town.plaque_adventurers", n), "")
            end
            if miniChatBadge ~= nil and miniChatBadge.valid then
                miniChatBadge:SetClass("collapsed", not (state.collapsed and ctx.ChatUnread()))
            end
            if noteLabel ~= nil and noteLabel.valid and not noteLabel:HasClass("collapsed") and dmhub.Time() > state.noteUntil then
                noteLabel:SetClass("collapsed", true)
                Layout()
            end
            local signature = string.format("%d|%d|%d|%d|%s|%s", EotwSocialRail.sources.steamRevision(), DiscordRevision(),
                g_lookup.revision, state.cityRevision, tostring(state.showOffline), tostring(state.collapsed))
            if signature ~= state.signature then
                state.signature = signature
                Rebuild()
            end
        end,

        --the City changed (games, presence): rebuild on the next think.
        eotwRailCity = function(element)
            state.cityRevision = state.cityRevision + 1
        end,

        expanded,
        mini,
    }
    if ctx.created ~= nil then
        ctx.created(rail)
    end
    return rail
end

--- Tell the rail the City's games or presence changed.
--- @param rail Panel|nil
function EotwSocialRail.CityChanged(rail)
    if rail ~= nil and rail.valid then
        rail:FireEvent("eotwRailCity")
    end
end
