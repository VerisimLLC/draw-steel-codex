local mod = dmhub.GetModLoading()

--Encounter of the Week: players leaving and coming back.
--
--When a player leaves mid-game (quits, crashes, loses their connection),
--the HOST takes over everything they controlled -- heroes, allies,
--companions -- as "free agents". The host may hand a free agent to another
--player from the popout under the title bar's players row. When the player
--comes back, their free agents go straight back to them. Every change shows
--a notice beneath the players row on every screen.
--
--Because every wait in the game (narrative votes, montage turns, the
--preparation Proceed, the arrangement) is keyed on who controls a hero, a
--leaver's heroes passing to the host is also what keeps the story moving.
--
--Authority: the HOST is the only writer of the document below, from the
--map script's host tick (EncounterPresence.HostTick) and the host's own
--Give action. Every client reads it to show the notices and the popout.
--
--The shared document ("eotwpresence", this codemod's namespace):
--  data.away   = { [userid] = { name, at, abandoned } }
--                players who have left and not come back (at = serverTime).
--                An ABANDONED player's free agents stay free agents: they
--                are never handed back.
--  data.agents = { [charid] = { owner, controller } }
--                tokens of an away player and who runs them meanwhile. The
--                record goes when the owner comes back.
--  data.events = { { seq, kind = "left"|"abandoned"|"returned"|"given", userid, name,
--                    controller, controllerName, heroNames, at }, ... }
--                the newest MAX_EVENTS changes, for the notices
--  data.seq    = the last event's seq
--  data.host   = the userid whose host tick last ran here; when another
--                client's tick takes over, it records itself and adds a
--                "newhost" event (who took over from whom)
--
--A player who abandons writes their own document, "eotwleave-<userid>":
--  data.abandoned = serverTime
--(one writer per document, so nothing else's write can clobber it). The
--host reads it to tell the others and keep the heroes.
--
--Design: EncounterOfTheWeek.md, "Players leaving and coming back".

local T = UIText.T

EncounterPresence = rawget(_G, "EncounterPresence") or {}

local DOC_ID = "eotwpresence"
local STATE_DOC_ID = "eotwstate"

--a player silent this long (no session ping; they ping every ~12s) has
--gone. A clean exit is seen at once (the session says loggedOut).
local LEAVE_SECONDS = 35
--...and must keep looking gone this long before the host acts. After a
--reconnect the game server re-sends session records with their stored
--timestamps, which are rounded down to 5 minutes, so a player who is here
--can look silent until their next ping (<= ~12s).
local LEAVE_CONFIRM_SECONDS = 15
--a clean exit (the engine sets loggedOut before it quits or leaves) is
--acted on at the next check. A present player's record never carries the
--flag: their every ping rewrites the record without it.
local LOGGED_OUT_CONFIRM_SECONDS = 0
--a returning player must be pinging again...
local RETURN_FRESH_SECONDS = 20
--...and have finished arriving (their client re-stamps eotwstate.arrived
--once its heroes are placed), or have been back this long regardless.
local RETURN_FALLBACK_SECONDS = 30
--the host makes no decisions for this long after loading, so sessions it
--has not heard from yet are not mistaken for departures.
local STARTUP_GRACE_SECONDS = 10
local MAX_EVENTS = 16

local m_loadedAt = dmhub.Time()

local function GetDoc()
    return mod:GetDocumentSnapshot(DOC_ID)
end

function EncounterPresence.DocPath()
    return mod:GetDocumentPath(DOC_ID)
end

function EncounterPresence.GetData()
    local data = nil
    pcall(function() data = GetDoc().data end)
    return data or {}
end

local function DisplayName(userid)
    local name = nil
    pcall(function() name = dmhub.GetDisplayName(userid) end)
    if name == nil or name == "" then
        pcall(function()
            local info = dmhub.GetSessionInfo(userid)
            name = info ~= nil and info.displayName or nil
        end)
    end
    if name == nil or name == "" then
        return T("presence.player_fallback")
    end
    return name
end
EncounterPresence.DisplayName = DisplayName

local function HeroName(tok)
    local montage = rawget(_G, "EncounterMontage")
    if montage ~= nil then
        return montage.HeroDisplayName(tok)
    end
    return tok.name or T("presence.hero_fallback")
end

local function IsHero(tok)
    local hero = false
    pcall(function() hero = tok.properties ~= nil and tok.properties:IsHero() end)
    return hero
end

--"A", "A and B", "A, B and C".
local function JoinNames(names)
    if #names <= 1 then
        return names[1] or ""
    end
    return T("presence.names_and", { list = table.concat(names, ", ", 1, #names - 1), last = names[#names] })
end
EncounterPresence.JoinNames = JoinNames

--Is this player in the game right now? (Not loggedOut, pinging.) A player
--with no session record at all has never been here.
function EncounterPresence.IsOnline(userid)
    local info = dmhub.GetSessionInfo(userid)
    if info == nil or info.loggedOut or not info.lastContactKnown then
        return false
    end
    return info.timeSinceLastContact < LEAVE_SECONDS
end

--host-local: when each player first looked gone, and whether by a clean
--logout.
local m_goneSince = {}

local function HasLeft(userid)
    local info = dmhub.GetSessionInfo(userid)
    local gone = false
    local loggedOut = false
    if info ~= nil then
        loggedOut = info.loggedOut
        gone = loggedOut or not info.lastContactKnown or info.timeSinceLastContact >= LEAVE_SECONDS
    end
    if not gone then
        m_goneSince[userid] = nil
        return false
    end
    local now = dmhub.Time()
    if m_goneSince[userid] == nil then
        m_goneSince[userid] = now
    end
    local confirm = loggedOut and LOGGED_OUT_CONFIRM_SECONDS or LEAVE_CONFIRM_SECONDS
    return now - m_goneSince[userid] >= confirm
end

--host-local: when each away player was first seen pinging again.
local m_backSince = {}

local function HasReturned(userid, rec)
    local info = dmhub.GetSessionInfo(userid)
    if info == nil or info.loggedOut or not info.lastContactKnown
        or info.timeSinceLastContact >= RETURN_FRESH_SECONDS then
        m_backSince[userid] = nil
        return false
    end
    local now = dmhub.Time()
    if m_backSince[userid] == nil then
        m_backSince[userid] = now
    end

    --their client stamps its arrival once its heroes are placed again.
    local arrivedAt = nil
    pcall(function()
        local arrived = mod:GetDocumentSnapshot(STATE_DOC_ID).data.arrived
        arrivedAt = type(arrived) == "table" and tonumber(arrived[userid]) or nil
    end)
    if arrivedAt ~= nil and arrivedAt > (tonumber(rec.at) or 0) then
        return true
    end
    return now - m_backSince[userid] >= RETURN_FALLBACK_SECONDS
end

local function AddEvent(data, event)
    data.seq = (tonumber(data.seq) or 0) + 1
    event.seq = data.seq
    event.at = dmhub.serverTime
    local events = {}
    for _, e in ipairs(data.events or {}) do
        events[#events + 1] = e
    end
    events[#events + 1] = event
    while #events > MAX_EVENTS do
        table.remove(events, 1)
    end
    data.events = events

    --analytics (the host writes these): who left, came back, abandoned or
    --took over hosting, and where the party was when it happened.
    local heroCount = type(event.heroNames) == "table" and #event.heroNames or nil
    EotwAnalytics.Track("eotw_presence", {
        event = event.kind,
        member = event.userid,
        memberHeroes = heroCount,
        phase = EotwAnalytics.CurrentPhase(),
    })
end

--- abandoning ------------------------------------------------------------------

local ABANDON_DOC_PREFIX = "eotwleave-"

function EncounterPresence.HasAbandoned(userid)
    local abandoned = false
    pcall(function()
        abandoned = mod:GetDocumentSnapshot(ABANDON_DOC_PREFIX .. userid).data.abandoned ~= nil
    end)
    return abandoned
end

--Everyone who has played in this game: the players the launch expected,
--everyone who placed heroes, and anyone controlling a hero now.
function EncounterPresence.Members()
    local seen = {}
    local result = {}
    local function Add(userid)
        if type(userid) == "string" and userid ~= "PARTY" and not seen[userid] then
            seen[userid] = true
            result[#result + 1] = userid
        end
    end
    pcall(function()
        local state = mod:GetDocumentSnapshot(STATE_DOC_ID).data
        for _, userid in ipairs(state.expectedUsers or {}) do
            Add(userid)
        end
        for userid, _ in pairs(state.placedHeroes or {}) do
            Add(userid)
        end
    end)
    for _, tok in ipairs(dmhub.allTokens) do
        if tok ~= nil and tok.valid then
            Add(tok.ownerId)
        end
    end
    for _, rec in pairs(EncounterPresence.GetData().agents or {}) do
        if type(rec) == "table" then
            Add(rec.owner)
        end
    end
    return result
end

--Is this user the only member who has not abandoned the game? (Players
--who merely left still count: they mean to come back.)
function EncounterPresence.IsLastMember(userid)
    for _, other in ipairs(EncounterPresence.Members()) do
        if other ~= userid and not EncounterPresence.HasAbandoned(other) then
            return false
        end
    end
    return true
end

--Every token on the map this user controls.
local function TokensOwnedBy(userid)
    local result = {}
    for _, tok in ipairs(dmhub.allTokens) do
        if tok ~= nil and tok.valid and tok.ownerId == userid then
            result[#result + 1] = tok
        end
    end
    return result
end

--- the host side ---------------------------------------------------------------

--The player has gone: the host takes over everything they control.
--`abandoned`: for good -- their heroes will not be handed back.
local function Depart(userid, host, abandoned)
    local tokens = TokensOwnedBy(userid)
    local heroNames = {}
    for _, tok in ipairs(tokens) do
        if IsHero(tok) then
            heroNames[#heroNames + 1] = HeroName(tok)
        end
    end
    table.sort(heroNames)

    local doc = GetDoc()
    doc:BeginChange()
    local data = doc.data
    data.away = data.away or {}
    data.agents = data.agents or {}
    data.away[userid] = { name = DisplayName(userid), at = dmhub.serverTime, abandoned = abandoned or nil }
    for _, tok in ipairs(tokens) do
        --a free agent this player was looking after keeps its real owner.
        local rec = data.agents[tok.charid] or { owner = userid }
        rec.controller = host
        data.agents[tok.charid] = rec
    end
    AddEvent(data, {
        kind = abandoned and "abandoned" or "left",
        userid = userid,
        name = DisplayName(userid),
        controller = host,
        controllerName = DisplayName(host),
        heroNames = heroNames,
    })
    doc:CompleteChange("Encounter of the Week: a player left", { undoable = false })

    for _, tok in ipairs(tokens) do
        tok.ownerId = host
    end
    m_goneSince[userid] = nil
    printf("EotW presence: %s %s; the host now controls %d tokens (%s)", tostring(userid),
        abandoned and "abandoned the game" or "left", #tokens, JoinNames(heroNames))
end

--A player who already left has now been seen to have abandoned the game
--(their leave arrived before their abandon note): say so, and keep their
--heroes.
local function MarkAbandoned(userid)
    local doc = GetDoc()
    local heroNames = {}
    local controller = nil
    for charid, rec in pairs(doc.data.agents or {}) do
        if type(rec) == "table" and rec.owner == userid then
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil and tok.valid and IsHero(tok) then
                heroNames[#heroNames + 1] = HeroName(tok)
                controller = controller or rec.controller
            end
        end
    end
    table.sort(heroNames)
    controller = controller or dmhub.loginUserid
    doc:BeginChange()
    doc.data.away[userid].abandoned = true
    AddEvent(doc.data, {
        kind = "abandoned",
        userid = userid,
        name = DisplayName(userid),
        controller = controller,
        controllerName = DisplayName(controller),
        heroNames = heroNames,
    })
    doc:CompleteChange("Encounter of the Week: a player abandoned the game", { undoable = false })
    printf("EotW presence: %s abandoned the game", tostring(userid))
end

--The player is back: everything of theirs comes home.
local function Return(userid)
    local doc = GetDoc()
    local data = doc.data
    local tokens = {}
    local heroNames = {}
    for charid, rec in pairs(data.agents or {}) do
        if type(rec) == "table" and rec.owner == userid then
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil and tok.valid then
                tokens[#tokens + 1] = tok
                if IsHero(tok) then
                    heroNames[#heroNames + 1] = HeroName(tok)
                end
            end
        end
    end

    table.sort(heroNames)

    doc:BeginChange()
    data = doc.data
    for charid, rec in pairs(data.agents or {}) do
        if type(rec) == "table" and rec.owner == userid then
            data.agents[charid] = nil
        end
    end
    if data.away ~= nil then
        data.away[userid] = nil
    end
    AddEvent(data, {
        kind = "returned",
        userid = userid,
        name = DisplayName(userid),
        heroNames = heroNames,
    })
    doc:CompleteChange("Encounter of the Week: a player came back", { undoable = false })

    for _, tok in ipairs(tokens) do
        tok.ownerId = userid
    end
    m_backSince[userid] = nil
    printf("EotW presence: %s is back; %d tokens returned (%s)", tostring(userid), #tokens, JoinNames(heroNames))
end

--Host only: hand a free agent (and any montage allies that came with it) to
--another player who is here. Returns an error string, or nil on success.
function EncounterPresence.Give(charid, toUserid)
    if not IsDMOrPlayerHost() then
        return "only the host may hand heroes over"
    end
    local doc = GetDoc()
    local agents = doc.data.agents or {}
    local rec = agents[charid]
    if type(rec) ~= "table" then
        return "that hero is not a free agent"
    end
    if toUserid ~= dmhub.loginUserid and not EncounterPresence.IsOnline(toUserid) then
        return "that player is not here"
    end
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or not tok.valid then
        return "that hero is not on the map"
    end

    --allies a montage gave this hero travel with it, if they are free
    --agents too.
    local charids = { charid }
    pcall(function()
        local allies = EncounterMontage.GetDoc().data.allies
        for _, allyid in ipairs((type(allies) == "table" and allies[charid]) or {}) do
            if type(agents[allyid]) == "table" then
                charids[#charids + 1] = allyid
            end
        end
    end)

    doc:BeginChange()
    for _, id in ipairs(charids) do
        doc.data.agents[id].controller = toUserid
    end
    AddEvent(doc.data, {
        kind = "given",
        userid = rec.owner,
        name = DisplayName(rec.owner),
        controller = toUserid,
        controllerName = DisplayName(toUserid),
        heroNames = { HeroName(tok) },
        abandoned = EncounterPresence.HasAbandoned(rec.owner) or nil,
    })
    doc:CompleteChange("Encounter of the Week: a free agent changed hands", { undoable = false })

    for _, id in ipairs(charids) do
        local t = dmhub.GetCharacterById(id)
        if t ~= nil and t.valid then
            t.ownerId = toUserid
        end
    end
    return nil
end

--Dev helpers (host, from the debug console / MCP): play a departure or a
--return for a userid without that player really leaving, to see the
--notices, the popout and the montage hand-over on one machine.
function EncounterPresence.DevSimulateLeave(userid)
    Depart(userid, dmhub.loginUserid)
end

function EncounterPresence.DevSimulateReturn(userid)
    Return(userid)
end

local m_lastTick = 0

--Called by the map script's host tick (EncounterOfTheWeek.lua) on the host
--of a real EotW game. Checks once a second.
function EncounterPresence.HostTick()
    local now = dmhub.Time()
    if now - m_lastTick < 1 or now - m_loadedAt < STARTUP_GRACE_SECONDS then
        return
    end
    m_lastTick = now

    local host = dmhub.loginUserid
    local data = GetDoc().data

    --hosting moved to this client: record it, and tell everyone when it
    --took over from someone (the very first tick of a game just records).
    if data.host ~= host then
        local previous = data.host
        local doc = GetDoc()
        doc:BeginChange()
        doc.data.host = host
        if type(previous) == "string" then
            AddEvent(doc.data, {
                kind = "newhost",
                userid = host,
                name = DisplayName(host),
                previous = previous,
                previousName = DisplayName(previous),
            })
        end
        doc:CompleteChange("Encounter of the Week: a new host", { undoable = false })
        printf("EotW presence: this client is now the host (was %s)", tostring(previous))
        data = GetDoc().data
    end

    local away = data.away or {}

    --who has gone: anyone (but the host) controlling something on the map.
    local owners = {}
    for _, tok in ipairs(dmhub.allTokens) do
        local owner = tok ~= nil and tok.valid and tok.ownerId or nil
        if owner ~= nil and owner ~= "PARTY" and owner ~= host then
            owners[owner] = true
        end
    end
    for userid, _ in pairs(owners) do
        if away[userid] == nil then
            --an abandon note goes out just before the player quits, so it
            --usually beats their logout here.
            local abandoned = EncounterPresence.HasAbandoned(userid)
            if abandoned or HasLeft(userid) then
                Depart(userid, host, abandoned)
            end
        end
    end

    --who abandoned after we had already seen them leave.
    away = GetDoc().data.away or {}
    for userid, rec in pairs(away) do
        if type(rec) == "table" and not rec.abandoned and EncounterPresence.HasAbandoned(userid) then
            MarkAbandoned(userid)
        end
    end

    --who is back (never a player who abandoned).
    away = GetDoc().data.away or {}
    for userid, rec in pairs(away) do
        if type(rec) == "table" and not rec.abandoned and HasReturned(userid, rec) then
            Return(userid)
        end
    end

    --a montage turn follows its hero to whoever controls it now.
    local montage = rawget(_G, "EncounterMontage")
    if montage ~= nil then
        local awaySet = {}
        for userid, _ in pairs(GetDoc().data.away or {}) do
            awaySet[userid] = true
        end
        local ok, err = pcall(montage.SyncTurnToOwners, awaySet)
        if not ok then
            printf("EotW presence: montage turn sync failed: %s", tostring(err))
        end
    end
end

--- the notices (every client) ------------------------------------------------------

--What this client says about one event, or nil to say nothing.
local function EventText(e)
    local me = dmhub.loginUserid
    local heroes = JoinNames(e.heroNames or {})
    if e.kind == "left" then
        if e.userid == me then
            return nil
        end
        if e.controller == me then
            if heroes == "" then
                return T("presence.left.you_control_nothing", { name = e.name })
            end
            return T("presence.left.you_control", { name = e.name, heroes = heroes })
        end
        if heroes == "" then
            return T("presence.left.no_heroes", { name = e.name })
        end
        return T("presence.left.other_controls", { name = e.name, controller = e.controllerName, heroes = heroes })
    elseif e.kind == "abandoned" then
        if e.userid == me then
            return nil
        end
        if heroes == "" then
            return T("presence.abandoned.no_heroes", { name = e.name })
        end
        if e.controller == me then
            return T("presence.abandoned.you_control", { name = e.name, heroes = heroes })
        end
        return T("presence.abandoned.other_controls", { name = e.name, controller = e.controllerName, heroes = heroes })
    elseif e.kind == "newhost" then
        if e.userid == me then
            return T("presence.newhost.you", { previous = e.previousName or T("presence.newhost.previous_fallback") })
        end
        return T("presence.newhost.other", { name = e.name })
    elseif e.kind == "returned" then
        if e.userid == me then
            if heroes == "" then
                return T("presence.returned.you")
            end
            return T("presence.returned.you_control", { heroes = heroes })
        end
        if heroes == "" then
            return T("presence.returned.no_heroes", { name = e.name })
        end
        return T("presence.returned.other_controls", { name = e.name, heroes = heroes })
    elseif e.kind == "given" then
        if e.controller == me then
            if e.abandoned then
                return T("presence.given.you_control_abandoned", { heroes = heroes })
            end
            return T("presence.given.you_control", { heroes = heroes, name = e.name })
        end
        if IsDMOrPlayerHost() then
            --the host did this themselves.
            return nil
        end
        if e.abandoned then
            return T("presence.given.other_controls_abandoned", { controller = e.controllerName, heroes = heroes })
        end
        return T("presence.given.other_controls", { controller = e.controllerName, heroes = heroes, name = e.name })
    end
    return nil
end

local function ShowToast(text, e)
    local titleBar = rawget(_G, "CodexTitleBar")
    if titleBar == nil or titleBar.ShowPlayersToast == nil then
        return
    end
    local actions = nil
    --the host is offered the hand-over straight from the notice.
    if (e.kind == "left" or e.kind == "abandoned") and e.controller == dmhub.loginUserid and #(e.heroNames or {}) > 0
        and titleBar.OpenPlayersPopout ~= nil then
        actions = {
            { text = T("presence.notice.reassign_button"), click = function() titleBar.OpenPlayersPopout() end },
        }
    end
    titleBar.ShowPlayersToast{
        text = text,
        actions = actions,
        duration = 10,
    }
end

--the game the watcher below last read, the newest event it has dealt with,
--and when it started watching that game (older events are history).
local m_watchGame = nil
local m_seenSeq = 0
local m_watchStart = 0

local function WatchEvents()
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    if eotw == nil or not eotw.IsEotwGame() or eotw.IsTestRunning() then
        return
    end
    if m_watchGame ~= dmhub.gameid then
        m_watchGame = dmhub.gameid
        m_seenSeq = 0
        m_watchStart = dmhub.serverTime
    end
    local data = EncounterPresence.GetData()
    for _, e in ipairs(data.events or {}) do
        local seq = tonumber(e.seq) or 0
        if seq > m_seenSeq then
            m_seenSeq = seq
            --a moment's slack: an event written just before this client
            --started watching is still news (a returning player's own
            --"welcome back" can land as they arrive).
            if (tonumber(e.at) or 0) >= m_watchStart - 5 then
                local text = EventText(e)
                if text ~= nil then
                    ShowToast(text, e)
                end
            end
        end
    end
end

--- the host leaving and coming back --------------------------------------------------

--How long a notice dismissed by a click elsewhere stays down before it is
--shown again, while the situation it is about still holds.
local HOST_NOTICE_REPEAT_SECONDS = 30
local HOSTGONE_TOAST = "eotw-hostgone"
local RECLAIM_TOAST = "eotw-reclaim"

--The players who host this game right now (GameInfo.IsDM: the owner unless
--they handed hosting over, plus the game's dm list), among everyone known.
local function CurrentHosts()
    local seen = {}
    local result = {}
    local function Consider(userid)
        if type(userid) == "string" and not seen[userid] then
            seen[userid] = true
            local isHost = false
            pcall(function() isHost = dmhub.IsUserDM(userid) == true end)
            if isHost then
                result[#result + 1] = userid
            end
        end
    end
    for _, userid in ipairs(EncounterPresence.Members()) do
        Consider(userid)
    end
    for _, userid in ipairs(dmhub.users or {}) do
        Consider(userid)
    end
    return result
end

--this client's view of how long every host has looked gone, and when it
--last showed each host notice.
local m_hostGoneSince = nil
local m_noticeShownAt = {}
local m_hostRequestBusy = false
local m_lastHostCheck = 0

local function ShowHostNotice(id, text, actions)
    local titleBar = rawget(_G, "CodexTitleBar")
    if titleBar == nil or titleBar.ShowPlayersToast == nil then
        return
    end
    if titleBar.HasPlayersToast(id) then
        return
    end
    local now = dmhub.Time()
    if m_noticeShownAt[id] ~= nil and now - m_noticeShownAt[id] < HOST_NOTICE_REPEAT_SECONDS then
        return
    end
    m_noticeShownAt[id] = now
    titleBar.ShowPlayersToast{ id = id, text = text, actions = actions, duration = 0 }
end

local function DismissHostNotice(id)
    m_noticeShownAt[id] = nil
    local titleBar = rawget(_G, "CodexTitleBar")
    if titleBar ~= nil and titleBar.DismissPlayersToast ~= nil then
        titleBar.DismissPlayersToast(id)
    end
end

--Ask the eotwSetHost cloud function to make this player the host ("claim")
--or, for the owner, to take hosting back ("reclaim"). The change lands in
--the game record; the new host's tick then announces it to everyone.
local function RequestHost(action)
    if m_hostRequestBusy then
        return
    end
    m_hostRequestBusy = true
    local gameid = dmhub.gameid
    net.Post{
        url = dmhub.cloudFunctionsBaseUrl .. "/eotwSetHost",
        data = { gameid = gameid, action = action },
        success = function(data)
            m_hostRequestBusy = false
            if type(data) == "table" and data.ok then
                printf("EotW presence: %s of game %s accepted", action, tostring(gameid))
                return
            end
            local message = type(data) == "table" and data.error or T("presence.host_request.invalid_response")
            printf("EotW presence: %s refused: %s", action, tostring(message))
            local titleBar = rawget(_G, "CodexTitleBar")
            if titleBar ~= nil and titleBar.ShowPlayersToast ~= nil then
                titleBar.ShowPlayersToast{ text = T("presence.host_request.refused", { message = tostring(message) }) }
            end
        end,
        error = function(message)
            m_hostRequestBusy = false
            printf("EotW presence: %s failed: %s", action, tostring(message))
            local titleBar = rawget(_G, "CodexTitleBar")
            if titleBar ~= nil and titleBar.ShowPlayersToast ~= nil then
                titleBar.ShowPlayersToast{ text = T("presence.host_request.unreachable", { message = tostring(message) }) }
            end
        end,
    }
end

--Every client, once a second. Not the host: when no host is left in the
--game (a clean exit at once, a silent one after the same wait as any
--player), offer Claim Host. The owner back in a game someone else is
--hosting: offer Reclaim Host.
local function WatchHost()
    local now = dmhub.Time()
    if now - m_lastHostCheck < 1 or now - m_loadedAt < STARTUP_GRACE_SECONDS then
        return
    end
    m_lastHostCheck = now

    if IsDMOrPlayerHost() then
        m_hostGoneSince = nil
        DismissHostNotice(HOSTGONE_TOAST)
        DismissHostNotice(RECLAIM_TOAST)
        return
    end

    local hosts = CurrentHosts()
    local present = {}
    local anyGone = false
    for _, userid in ipairs(hosts) do
        local info = dmhub.GetSessionInfo(userid)
        local live = info ~= nil and not info.loggedOut and info.lastContactKnown
            and info.timeSinceLastContact < LEAVE_SECONDS
        if live then
            present[#present + 1] = userid
        elseif info ~= nil and info.loggedOut then
            anyGone = true
        end
    end

    if #present > 0 then
        m_hostGoneSince = nil
        DismissHostNotice(HOSTGONE_TOAST)
        --the owner, back in a game another player is now hosting.
        if dmhub.isGameOwner then
            ShowHostNotice(RECLAIM_TOAST,
                T("presence.reclaim.notice", { hosts = JoinNames((function()
                    local names = {}
                    for _, userid in ipairs(present) do
                        names[#names + 1] = DisplayName(userid)
                    end
                    return names
                end)()) }),
                { { text = T("presence.reclaim.button"), click = function() RequestHost("reclaim") end } })
        end
        return
    end
    DismissHostNotice(RECLAIM_TOAST)

    if m_hostGoneSince == nil then
        m_hostGoneSince = now
    end
    local confirm = anyGone and LOGGED_OUT_CONFIRM_SECONDS or LEAVE_CONFIRM_SECONDS
    if now - m_hostGoneSince < confirm then
        return
    end

    local hostName = (#hosts > 0) and JoinNames((function()
        local names = {}
        for _, userid in ipairs(hosts) do
            names[#names + 1] = DisplayName(userid)
        end
        return names
    end)()) or T("presence.hostgone.host_fallback")
    ShowHostNotice(HOSTGONE_TOAST,
        T("presence.hostgone.notice", { host = hostName }),
        { { text = T("presence.hostgone.button"), click = function() RequestHost("claim") end } })
end

dmhub.Coroutine(function()
    while not mod.unloaded do
        local ok, err = pcall(WatchEvents)
        if not ok then
            printf("EotW presence: notice watcher failed: %s", tostring(err))
        end
        local eotw = rawget(_G, "EncounterOfTheWeekGame")
        if eotw ~= nil and eotw.IsEotwGame() and not eotw.IsTestRunning() then
            ok, err = pcall(WatchHost)
            if not ok then
                printf("EotW presence: host watcher failed: %s", tostring(err))
            end
        end
        coroutine.yield(0.5)
    end
end)

--- leaving the game ----------------------------------------------------------------

--Ask the eotwAbandonGame cloud function to delete this game now, if no
--other member still holds it. Fire and forget: the game's Lua unloads as
--we leave, so the callbacks only log. The titlescreen repeats the call
--(eotw:abandonedgame), which also catches a quit that cut this one off.
local function RequestAbandonDelete(gameid)
    net.Post{
        url = dmhub.cloudFunctionsBaseUrl .. "/eotwAbandonGame",
        data = { gameid = gameid },
        success = function(data)
            if type(data) == "table" and data.ok then
                printf("EotW presence: abandoned game %s is deleted (storage released: %s)", tostring(gameid), tostring(data.released))
            else
                printf("EotW presence: abandoned game %s stays for the others: %s", tostring(gameid),
                    tostring(type(data) == "table" and data.error or "invalid response"))
            end
        end,
        error = function(message)
            printf("EotW presence: could not reach eotwAbandonGame for %s: %s", tostring(gameid), tostring(message))
        end,
    }
end

--Abandon this game for good, then go: proceed() quits the app or leaves the
--game, whichever the player asked for. Our heroes stay behind as free
--agents and we get nothing from the encounter. A note in our own
--"eotwleave-" document tells the host. As we go we ask eotwAbandonGame to
--delete the game (it does when no other member still holds it, owner or
--not); the titlescreen's next refresh (eotw:abandonedgame) asks again and
--takes us off the game's player list.
function EncounterPresence.Abandon(proceed)
    local me = dmhub.loginUserid
    local gameid = dmhub.gameid

    local doc = mod:GetDocumentSnapshot(ABANDON_DOC_PREFIX .. me)
    doc:BeginChange()
    doc.data.abandoned = dmhub.serverTime
    doc:CompleteChange("Encounter of the Week: abandoned the game", { undoable = false })

    dmhub.SetSettingValue("eotw:abandonedgame", dmhub.ToJson{ gameid = gameid })
    printf("EotW presence: abandoning game %s", tostring(gameid))

    --the beta survey asks what made us leave, back in town.
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    if eotw ~= nil and eotw.RecordPendingSurvey ~= nil then
        local ok, err = pcall(eotw.RecordPendingSurvey, "abandoned")
        if not ok then
            printf("EotW presence: could not leave the survey invitation: %s", tostring(err))
        end
    end
    --analytics: this player's run ends here, abandoned.
    if eotw ~= nil and eotw.AnalyticsEndRun ~= nil then
        pcall(eotw.AnalyticsEndRun, "abandoned", "abandon")
    end

    --a moment for the note to reach the server before the connection goes.
    --Not tied to mod.unloaded: the player must get out regardless. The
    --delete is sent in the same frame we leave, after the note has landed;
    --sent first so a quit cannot skip it.
    dmhub.Schedule(0.75, function()
        RequestAbandonDelete(gameid)
        proceed()
    end)
end

local EXIT_DIALOG_STYLES = {
    {
        selectors = {"label", "button", "abandon"},
        bgcolor = "@danger",
        borderColor = "@danger",
        color = "@fg",
    },
    {
        selectors = {"label", "button", "abandon", "hover"},
        brightness = 1.25,
    },
}

local m_exitDialog = nil

--The EotW interface's exit confirmation (GameHud's confirmExit hook):
--leaving or quitting a game in progress asks whether the player means to
--come back (Leave) or give the game up (Abandon Game). Returns false --
--let the exit go ahead unasked -- outside a real game in progress: in an
--authoring test, or once the encounter is decided (the game is over).
function EncounterPresence.ConfirmExit(kind, proceed)
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    if eotw == nil or not eotw.IsEotwGame() or eotw.IsTestRunning() or eotw.OutcomeDecided() then
        return false
    end
    local hud = rawget(_G, "gamehud")
    if hud == nil then
        return false
    end
    if m_exitDialog ~= nil and m_exitDialog.valid then
        return true
    end

    local me = dmhub.loginUserid
    local isHost = IsDMOrPlayerHost()
    local othersPlaying = not EncounterPresence.IsLastMember(me)

    local notes = {}
    if isHost and othersPlaying then
        notes[#notes + 1] = T("presence.exit.note_host")
    end
    if othersPlaying then
        notes[#notes + 1] = T("presence.exit.note_abandon")
    else
        notes[#notes + 1] = T("presence.exit.note_abandon_last")
    end

    local function Close()
        if m_exitDialog ~= nil and m_exitDialog.valid then
            hud:CloseModal()
        end
        m_exitDialog = nil
    end

    --analytics: what the player chose at the exit prompt ("leave" keeps the
    --run open for a resume; "abandon" also ends it, see Abandon).
    local function TrackChoice(choice)
        EotwAnalytics.Track("eotw_exit_choice", {
            kind = kind,
            choice = choice,
            phase = EotwAnalytics.CurrentPhase(),
            host = isHost,
            othersPlaying = othersPlaying,
        })
    end

    local abandonButton
    abandonButton = gui.Button{
        classes = {"sizeL", "abandon"},
        text = T("presence.exit.abandon_button"),
        width = 220,
        halign = "right",
        hmargin = 8,
        data = { confirming = false },
        resetConfirm = function(element)
            element.data.confirming = false
            element.text = T("presence.exit.abandon_button")
        end,
        click = function(element)
            --a second click confirms: abandoning cannot be undone.
            if not element.data.confirming then
                element.data.confirming = true
                element.text = T("presence.exit.abandon_confirm")
                element:ScheduleEvent("resetConfirm", 4)
                return
            end
            Close()
            TrackChoice("abandon")
            EncounterPresence.Abandon(proceed)
        end,
    }

    m_exitDialog = gui.Panel{
        classes = {"framedPanel"},
        styles = ThemeEngine.MergeStyles(EXIT_DIALOG_STYLES),
        width = 760,
        height = 380,
        flow = "vertical",
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        captureEscape = true,
        escape = function(element)
            Close()
            TrackChoice("cancel")
        end,

        gui.Label{
            classes = {"dialogTitle"},
            text = kind == "quit" and T("presence.exit.title_quit") or T("presence.exit.title_leave"),
            hmargin = 16,
            tmargin = 12,
        },
        gui.Label{
            text = T("presence.exit.body"),
            fontSize = 20,
            width = "100%-48",
            height = "auto",
            halign = "center",
            tmargin = 16,
            textWrap = true,
        },
        gui.Label{
            text = table.concat(notes, "\n\n"),
            fontSize = 15,
            opacity = 0.75,
            width = "100%-48",
            height = "auto",
            halign = "center",
            tmargin = 14,
            textWrap = true,
        },
        gui.Panel{
            width = "100%-32",
            height = 60,
            halign = "center",
            valign = "bottom",
            bmargin = 12,
            flow = "horizontal",
            gui.Button{
                classes = {"sizeL"},
                text = T("presence.exit.cancel_button"),
                halign = "left",
                hmargin = 8,
                click = function()
                    Close()
                    TrackChoice("cancel")
                end,
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
                flow = "horizontal",
                gui.Button{
                    classes = {"sizeL"},
                    text = kind == "quit" and T("presence.exit.quit_button") or T("presence.exit.leave_button"),
                    hmargin = 8,
                    click = function()
                        Close()
                        TrackChoice(kind == "quit" and "quit" or "leave")
                        proceed()
                    end,
                },
                abandonButton,
            },
        },
    }
    hud:ShowModal(m_exitDialog)
    return true
end

--- the players popout ------------------------------------------------------------

--Everyone in the game who has heroes or ever had them, the host first:
--{ userid, name, status = "online"|"away", host = bool }.
local function Players(data)
    local host = nil
    local seen = {}
    local result = {}
    local function Add(userid)
        if userid == nil or userid == "PARTY" or seen[userid] then
            return
        end
        seen[userid] = true
        local status = "online"
        local awayRec = (data.away or {})[userid]
        if type(awayRec) == "table" and awayRec.abandoned then
            status = "abandoned"
        elseif awayRec ~= nil or not EncounterPresence.IsOnline(userid) then
            status = "away"
        end
        local info = dmhub.GetSessionInfo(userid)
        local isHost = info ~= nil and info.dm == true
        result[#result + 1] = { userid = userid, name = DisplayName(userid), status = status, host = isHost }
    end
    for _, tok in ipairs(dmhub.allTokens) do
        if tok ~= nil and tok.valid and IsHero(tok) then
            Add(tok.ownerId)
        end
    end
    for userid, _ in pairs(data.away or {}) do
        Add(userid)
    end
    for _, rec in pairs(data.agents or {}) do
        if type(rec) == "table" then
            Add(rec.owner)
        end
    end
    table.sort(result, function(a, b)
        if a.host ~= b.host then
            return a.host
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.userid < b.userid
    end)
    return result
end

--The heroes a user controls right now (by name).
local function HeroesControlledBy(userid)
    local result = {}
    for _, tok in ipairs(dmhub.allTokens) do
        if tok ~= nil and tok.valid and tok.ownerId == userid and IsHero(tok) then
            result[#result + 1] = tok
        end
    end
    table.sort(result, function(a, b) return HeroName(a) < HeroName(b) end)
    return result
end

local function HeroRow(tok, data, players)
    local rec = (data.agents or {})[tok.charid]
    local isAgent = type(rec) == "table"

    local children = {
        gui.CreateTokenImage(tok, {
            width = 30,
            height = 30,
            halign = "left",
            valign = "center",
            rmargin = 8,
        }),
        gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            gui.Label{
                text = HeroName(tok),
                fontSize = 14,
                color = "#e8e8e8",
                width = "auto",
                height = "auto",
                halign = "left",
            },
            gui.Label{
                text = isAgent and (EncounterPresence.HasAbandoned(rec.owner)
                    and T("presence.players.free_agent_abandoned", { owner = DisplayName(rec.owner) })
                    or T("presence.players.free_agent", { owner = DisplayName(rec.owner) })) or "",
                fontSize = 11,
                italics = true,
                color = "#c9a860",
                width = "auto",
                height = "auto",
                halign = "left",
                classes = { cond(isAgent, nil, "collapsed") },
            },
        },
    }

    --the host may hand a free agent to anyone who is here.
    if isAgent and IsDMOrPlayerHost() then
        local options = {}
        for _, p in ipairs(players) do
            if p.status == "online" or p.userid == dmhub.loginUserid then
                options[#options + 1] = { id = p.userid, text = p.name }
            end
        end
        children[#children + 1] = gui.Dropdown{
            classes = { "sizeS" },
            width = 140,
            height = 24,
            halign = "right",
            valign = "center",
            options = options,
            idChosen = tok.ownerId,
            change = function(element)
                ---@cast element Dropdown
                local to = element.idChosen --[[@as string]]
                if to == nil or to == tok.ownerId then
                    return
                end
                local err = EncounterPresence.Give(tok.charid, to)
                if err ~= nil then
                    printf("EotW presence: could not hand %s over: %s", HeroName(tok), err)
                end
            end,
        }
    end

    return gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = "auto",
        vmargin = 2,
        lpad = 14,
        rpad = 4,
        borderBox = true,
        children = children,
    }
end

local function PlayerBlock(p, data, players)
    local statusText = T("presence.players.status_here")
    if p.status == "away" then
        statusText = T("presence.players.status_away")
    elseif p.status == "abandoned" then
        statusText = T("presence.players.status_abandoned")
    end
    if p.host then
        statusText = T("presence.players.status_host", { status = statusText })
    end
    local rows = {
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            gui.Panel{
                width = 9,
                height = 9,
                valign = "center",
                rmargin = 6,
                bgimage = "game-icons/plain-circle.png",
                bgcolor = p.status == "online" and "#58b060" or "#7a7a7a",
            },
            gui.Label{
                text = p.name,
                fontSize = 15,
                bold = true,
                color = "#f0f0f0",
                width = "auto",
                height = "auto",
                valign = "center",
            },
            gui.Label{
                text = statusText,
                fontSize = 12,
                color = "#a0a0a0",
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
            },
        },
    }
    local heroes = HeroesControlledBy(p.userid)
    for _, tok in ipairs(heroes) do
        rows[#rows + 1] = HeroRow(tok, data, players)
    end
    if #heroes == 0 then
        local text = T("presence.players.no_heroes")
        if p.status == "away" then
            text = T("presence.players.no_heroes_away")
        elseif p.status == "abandoned" then
            text = T("presence.players.no_heroes_abandoned")
        end
        rows[#rows + 1] = gui.Label{
            text = text,
            fontSize = 12,
            italics = true,
            color = "#909090",
            width = "auto",
            height = "auto",
            lmargin = 14,
        }
    end
    return gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        bmargin = 10,
        children = rows,
    }
end

--The popout under the title bar's players row in an EotW game (the EotW
--interface's playersPopout hook): every player, whether they are here, the
--heroes each controls, and -- for the host -- who gets each free agent.
function EncounterPresence.CreatePlayersPopout()
    local list = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
    }

    --rebuilt only when what it shows changes, so an open dropdown is not
    --torn down under the pointer.
    local shown = nil
    local function Rebuild()
        local data = EncounterPresence.GetData()
        local players = Players(data)
        local parts = {}
        for _, p in ipairs(players) do
            parts[#parts + 1] = string.format("%s:%s", p.userid, p.status)
            for _, tok in ipairs(HeroesControlledBy(p.userid)) do
                parts[#parts + 1] = string.format("%s:%s", tok.charid, (data.agents or {})[tok.charid] ~= nil and "agent" or "own")
            end
        end
        local signature = table.concat(parts, "|")
        if signature == shown then
            return
        end
        shown = signature
        local children = {}
        for _, p in ipairs(players) do
            children[#children + 1] = PlayerBlock(p, data, players)
        end
        list.children = children
    end

    local hint = T("presence.players.hint")
    if IsDMOrPlayerHost() then
        hint = T("presence.players.hint_host")
    end

    return gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "100%",
        monitorGame = EncounterPresence.DocPath(),
        refreshGame = function(element)
            Rebuild()
        end,
        create = function(element)
            Rebuild()
        end,
        --presence changes nothing in the document while a player is
        --merely going quiet, so look again now and then.
        thinkTime = 3,
        think = function(element)
            Rebuild()
        end,

        gui.Label{
            text = T("presence.players.title"),
            fontSize = 18,
            bold = true,
            color = "#f0f0f0",
            width = "auto",
            height = "auto",
            bmargin = 4,
        },
        gui.Label{
            text = hint,
            fontSize = 12,
            color = "#a8a8a8",
            width = "100%",
            height = "auto",
            textWrap = true,
            bmargin = 10,
        },
        gui.Panel{
            width = "100%",
            height = "100%",
            vscroll = true,
            flow = "vertical",
            list,
        },
    }
end
