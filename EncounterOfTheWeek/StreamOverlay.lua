local mod = dmhub.GetModLoading()

--Stream overlay publisher. Streamers add a web page (an OBS browser source) that
--draws a live band of the fight: heroes' stamina, monsters standing, round, turn
--and a ticker of recent events. This file is the in-game half: one host client
--builds a small, player-safe summary of the fight and writes it to the
--"streamOverlay" document, which the game server forwards to the overlay page.
--Design and plan: STREAM_OVERLAY_PLAN.md in the dmhubclient repo.
--
--Everything published must be something the players can already see: the
--server and the page treat the document as public. The publisher runs on the
--host, which sees Director-level information, so every value below is filtered
--to the players' view explicitly (see IsShownToPlayers and MonsterStamina).

StreamOverlay = {}

--The summary the overlay page draws. Rewritten whole on every change.
local SUMMARY_DOC = "streamOverlay"
--On/off switch, and later the overlay's link id and key hash (plan, Part 4).
local SETTINGS_DOC = "streamOverlaySettings"

local FORMAT_VERSION = 1
--How often the loop looks for changes, and the shortest gap between writes.
local POLL_SECONDS = 0.5
local MIN_WRITE_SECONDS = 1
--Rewrite even when nothing changed, so the page can tell a quiet fight from a
--dead publisher (it dims the band once "updated" is 60 s old).
local HEARTBEAT_SECONDS = 30
local MAX_EVENTS = 20
--The document downloads to every client in the game, so keep it small.
local MAX_BYTES = 16000

--- Is the overlay switched on for this game?
--- @return boolean
function StreamOverlay.IsEnabled()
    local enabled = false
    pcall(function() enabled = mod:GetDocumentSnapshot(SETTINGS_DOC).data.enabled == true end)
    return enabled
end

--- Switch the overlay on or off for this game. Any host may call it; the elected
--- host's client is the one that publishes. Turning it off clears the summary.
--- @param enabled boolean
function StreamOverlay.SetEnabled(enabled)
    local doc = mod:GetDocumentSnapshot(SETTINGS_DOC)
    doc:BeginChange()
    doc.data.enabled = enabled == true
    doc:CompleteChange(cond(enabled, "Stream overlay on", "Stream overlay off"), {undoable = false})
end

--- The summary as last published, for checking from the console.
--- @return table
function StreamOverlay.CurrentSummary()
    return mod:GetDocumentSnapshot(SUMMARY_DOC).data
end

--Only EotW games (and authoring tests of an encounter) publish in v1.
local function InEotwGame()
    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    if eotw == nil then
        return false
    end
    local result = false
    pcall(function() result = eotw.IsEotwGame() or eotw.IsTestRunning() end)
    return result
end

--One client publishes: the same host LiveEncounter elects for its own
--host-only work, so co-Directors never both write.
local function IsPublisher()
    local electedHost = rawget(rawget(_G, "LiveEncounter") or {}, "IsElectedHost")
    if electedHost == nil then
        return false
    end
    local result = false
    pcall(function() result = electedHost() == true end)
    return result
end

-- ---------------------------------------------------------------------------
-- What players can see
-- ---------------------------------------------------------------------------

--- Would a player see this creature token on the map right now? Hidden by the
--- Director, a pending summon, or Hidden while hidden creatures are invisible
--- (always on in EotW) all mean no.
--- @param token CharacterToken
--- @return boolean
local function IsShownToPlayers(token)
    if token == nil or not token.valid or token.properties == nil or token.isObject then
        return false
    end
    if token.invisibleToPlayers then
        return false
    end
    local hidden = false
    pcall(function() hidden = token.properties:IsHidden() and creature.HiddenCreaturesInvisible() end)
    return not hidden
end

--- The name players see for a token: "???" when the Director keeps it private.
--- Minion tokens usually have no name of their own; the game shows them by their
--- description (the monster type, e.g. "Clawfish").
--- @param token CharacterToken
--- @return string
local function PublicName(token)
    if token.namePrivate then
        return "???"
    end
    local name = token.name
    if name == nil or name == "" then
        name = token.description
    end
    if name == nil or name == "" then
        return "???"
    end
    return name
end

--- "Vex" -> "VX", "Ashwyn Hale" -> "AH".
--- @param name string
--- @return string
local function Initials(name)
    local words = {}
    for word in string.gmatch(name, "%w+") do
        words[#words + 1] = word
    end
    if #words >= 2 then
        return string.upper(string.sub(words[1], 1, 1) .. string.sub(words[2], 1, 1))
    end
    if #words == 1 then
        return string.upper(string.sub(words[1], 1, 2))
    end
    return "?"
end

--- How the players' own stamina bar shows this monster: "none", "bar", "pct" or
--- "val" (exact numbers). Mirrors the token HUD's lifebar (DrawSteelTokenHud.lua)
--- from a player's side: the game setting, upgraded to exact numbers once the
--- players have learned this monster's stamina.
--- @param token CharacterToken
--- @return string
local function MonsterStaminaDisplay(token)
    local showAs = dmhub.GetSettingValue("enemystambardisplay")
    if type(showAs) ~= "string" or showAs == "" then
        showAs = "val"
    end
    local knowledge = rawget(_G, "MonsterKnowledge")
    if showAs ~= "val" and knowledge ~= nil then
        local exact = false
        pcall(function() exact = knowledge.PlayersKnowStaminaExactly(token.properties, token) end)
        if exact then
            showAs = "val"
        end
    end
    return showAs
end

--- Conditions on a hero, as { {id, name} }. Uses exactly what the token HUD
--- shows; a hero is always friendly to the players, so nothing here is secret.
--- @param token CharacterToken
--- @return {id: string, name: string}[]
local function HeroConditions(token)
    local result = {}
    local icons = {}
    pcall(function() icons = TokenUI.CalculateStatusIcons(token) end)
    local seen = {}
    for _, icon in ipairs(icons) do
        local name = icon.statusText
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            result[#result + 1] = { id = string.lower(name), name = name }
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

-- ---------------------------------------------------------------------------
-- Building the summary
-- ---------------------------------------------------------------------------

--- @param props Creature
--- @return string "ok" | "winded" | "dying" | "dead"
local function HeroState(props)
    if props:IsDead() then
        return "dead"
    end
    if props:IsDying() then
        return "dying"
    end
    if props:CurrentHitpoints() <= props:MaxHitpoints() / 2 then
        return "winded"
    end
    return "ok"
end

--- @param token CharacterToken
--- @param activeTokenIds table<string, boolean>
--- @return table
local function HeroEntry(token, activeTokenIds)
    local props = token.properties
    local name = PublicName(token)
    local entry = {
        id = token.charid,
        name = name,
        initials = Initials(name),
        cur = props:CurrentHitpoints(),
        max = props:MaxHitpoints(),
        temp = props:TemporaryHitpoints(),
        state = HeroState(props),
        active = activeTokenIds[token.charid] == true,
        conditions = HeroConditions(token),
    }
    pcall(function()
        entry.rec = props:RecoveriesAvailableToSpend()
        entry.recMax = props:GetResources()[CharacterResource.recoveryResourceId] or 0
    end)
    pcall(function()
        entry.resource = {
            name = props:GetHeroicResourceName(),
            value = props:GetHeroicOrMaliceResources(),
        }
    end)
    return entry
end

--The heroes on the map, in EotW's own order (by name).
--- @return CharacterToken[]
local function HeroTokens()
    local result = {}
    local montage = rawget(_G, "EncounterMontage")
    if montage ~= nil then
        pcall(function()
            for _, hero in ipairs(montage.Heroes()) do
                result[#result + 1] = hero.token
            end
        end)
    end
    return result
end

--Every monster we have seen this combat, by token id, so one that is removed
--from the map when it dies still counts in "6 of 8 standing". Reset when a new
--combat starts.
local g_seenMonsters = {}
local g_seenMonstersCombat = nil

--- The monster tokens players can see, grouped: a minion squad is one group,
--- other monsters group by bestiary type (two Goblin Snipers are one group).
--- @param q nil|InitiativeQueue
--- @return table monsters { standing, total, groups }
local function MonsterSummary(q)
    local combatid = nil
    if q ~= nil and not q.hidden then
        combatid = q.guid
    end
    if combatid ~= g_seenMonstersCombat then
        g_seenMonsters = {}
        g_seenMonstersCombat = combatid
    end

    local bystanders = nil
    local eotw = rawget(_G, "EncounterOfTheWeekGame")

    local groups = {}
    local groupOrder = {}
    for _, token in ipairs(dmhub.GetTokens{unaffiliated = true}) do
        local include = IsShownToPlayers(token)
        if include and eotw ~= nil then
            pcall(function() include = not eotw.IsBystander(token, bystanders) end)
        end
        if include then
            local props = token.properties
            local squad = props:MinionSquad()
            local key = squad or props:GetMonsterType() or token.name or token.charid
            if token.namePrivate then
                key = "private:" .. tostring(key)
            end
            local group = groups[key]
            if group == nil then
                local name = PublicName(token)
                if squad ~= nil and not token.namePrivate then
                    name = squad
                elseif not token.namePrivate then
                    name = props:GetMonsterType() or name
                end
                group = { key = key, name = name, minion = squad ~= nil, standing = 0, total = 0, cur = 0, max = 0, display = "val" }
                groups[key] = group
                groupOrder[#groupOrder + 1] = key
            end
            local dead = props:IsDead()
            group.total = group.total + 1
            if not dead then
                group.standing = group.standing + 1
            end
            if squad == nil then
                group.cur = group.cur + math.max(0, props:CurrentHitpoints())
                group.max = group.max + props:MaxHitpoints()
                --the most guarded display among a group's members wins.
                local display = MonsterStaminaDisplay(token)
                if display ~= "val" then
                    group.display = display
                end
            end
            if combatid ~= nil then
                g_seenMonsters[token.charid] = true
            end
        end
    end

    --monsters seen earlier this combat that have since left the map.
    local goneTotal = 0
    for tokenid, _ in pairs(g_seenMonsters) do
        if dmhub.GetTokenById(tokenid) == nil then
            goneTotal = goneTotal + 1
        end
    end

    local result = { standing = 0, total = goneTotal, groups = {} }
    for _, key in ipairs(groupOrder) do
        local group = groups[key]
        result.standing = result.standing + group.standing
        result.total = result.total + group.total
        local entry = {
            name = group.name,
            standing = group.standing,
            total = group.total,
        }
        if group.standing == 0 then
            entry.state = "defeated"
        elseif not group.minion and group.max > 0 then
            local frac = group.cur / group.max
            if frac <= 0.5 then
                entry.state = "winded"
            else
                entry.state = "healthy"
            end
            if group.display == "val" then
                entry.cur = group.cur
                entry.max = group.max
                entry.frac = frac
            elseif group.display ~= "none" then
                entry.frac = math.floor(frac * 100 + 0.5) / 100
            end
        end
        result.groups[#result.groups + 1] = entry
    end
    return result
end

--- Whose turn it is, as { kind, name }. Draw Steel alternates sides with no
--- fixed order, so between turns it reports which side is choosing.
--- @param q InitiativeQueue
--- @return table turn, table<string, boolean> activeTokenIds
local function TurnInfo(q)
    local active = {}
    local initid = q:CurrentInitiativeId()
    if initid == nil then
        local players = false
        pcall(function() players = q:IsPlayersTurn() end)
        return { kind = cond(players, "heroes-choosing", "monsters-choosing") }, active
    end

    local isPlayer = q:IsEntryPlayer(initid) == true
    local names = {}
    for _, token in ipairs(InitiativeQueue.GetTokensForInitiativeId(initid)) do
        if IsShownToPlayers(token) then
            active[token.charid] = true
            local name = PublicName(token)
            if not isPlayer and not token.namePrivate then
                name = token.properties:MinionSquad() or token.properties:GetMonsterType() or name
            end
            names[name] = true
        end
    end
    local list = {}
    for name, _ in pairs(names) do
        list[#list + 1] = name
    end
    table.sort(list)
    --a monster turn by creatures players cannot see still shows as a monster turn.
    local turn = { kind = cond(isPlayer, "hero", "monster") }
    if #list > 0 then
        turn.name = table.concat(list, ", ")
    end
    return turn, active
end

--- The encounter's title as players see it, e.g. "The Goblin Ambush".
--- @return nil|string
local function EncounterTitle()
    local title = nil
    pcall(function()
        local info = EncounterOfTheWeekGame.EncounterInfo()
        if info ~= nil then
            title = info.title
        end
    end)
    return title
end

-- ---------------------------------------------------------------------------
-- Events for the ticker
-- ---------------------------------------------------------------------------
--
--Damage resolves on whichever client used the ability, and nothing broadcasts
--it, so events come from comparing synced state between ticks: each creature's
--damageEntries (the records behind the floating damage numbers) and each
--creature's state (winded, dying, dead).

--Per creature token: last published state, to spot changes.
local g_lastState = {}
--Damage entry id -> amount already reported. An entry can grow when more damage
--lands under the same id, so only the increase is reported.
local g_reportedDamage = {}
--False until the first tick has recorded a baseline; nothing that happened
--before this client started publishing is reported.
local g_baselineTaken = false
local g_events = {}
local g_eventSeq = 0

local function PushEvent(event)
    g_eventSeq = g_eventSeq + 1
    event.seq = g_eventSeq
    event.t = dmhub.serverTimeMilliseconds
    g_events[#g_events + 1] = event
    while #g_events > MAX_EVENTS do
        table.remove(g_events, 1)
    end
end

--- @param tokenid nil|string
--- @return nil|string name, nil|string side "hero" | "monster"
local function EventParty(tokenid)
    if tokenid == nil then
        return nil, nil
    end
    local token = dmhub.GetTokenById(tokenid)
    if token == nil or not IsShownToPlayers(token) then
        return nil, nil
    end
    local side = "monster"
    local isHero = false
    pcall(function() isHero = token.properties:IsHero() end)
    if isHero or token.playerControlled then
        side = "hero"
    end
    return PublicName(token), side
end

--- Look at one creature for new damage, healing and state changes.
--- @param token CharacterToken
--- @param state string the creature's state this tick
local function CollectEvents(token, state)
    local props = token.properties
    local tokenid = token.charid
    local targetName, targetSide = EventParty(tokenid)

    local entries = props:try_get("damageEntries")
    if type(entries) == "table" then
        for id, entry in pairs(entries) do
            local key = tokenid .. "/" .. tostring(id)
            local damage = tonumber(entry.damage) or 0
            local heal = tonumber(entry.heal) or 0
            local reported = g_reportedDamage[key]
            if reported == nil then
                reported = { damage = 0, heal = 0, at = dmhub.Time() }
                g_reportedDamage[key] = reported
                if not g_baselineTaken then
                    reported.damage = damage
                    reported.heal = heal
                end
            end
            reported.at = dmhub.Time()
            if targetName ~= nil and damage > reported.damage then
                local who, whoSide = EventParty(entry.attackerid)
                PushEvent{
                    kind = "damage",
                    who = who,
                    whoSide = whoSide,
                    target = targetName,
                    targetSide = targetSide,
                    amount = damage - reported.damage,
                    damageType = entry.damage_type,
                }
            end
            if targetName ~= nil and heal > reported.heal then
                PushEvent{
                    kind = "heal",
                    target = targetName,
                    targetSide = targetSide,
                    amount = heal - reported.heal,
                }
            end
            reported.damage = damage
            reported.heal = heal
        end
    end

    local previous = g_lastState[tokenid]
    g_lastState[tokenid] = state
    if previous == nil or previous == state or not g_baselineTaken or targetName == nil then
        return
    end
    if state == "winded" and previous ~= "dying" and previous ~= "dead" then
        PushEvent{ kind = "winded", target = targetName, targetSide = targetSide }
    elseif state == "dying" then
        PushEvent{ kind = "dying", target = targetName, targetSide = targetSide }
    elseif state == "dead" then
        PushEvent{ kind = cond(targetSide == "hero", "dead", "defeated"), target = targetName, targetSide = targetSide }
    end
end

--Forget damage entries the creatures themselves have pruned (after 60 s).
local function PruneReportedDamage()
    local now = dmhub.Time()
    for key, reported in pairs(g_reportedDamage) do
        if now - reported.at > 120 then
            g_reportedDamage[key] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- The publish loop
-- ---------------------------------------------------------------------------

local g_lastCombat = nil

--- Build the summary from the board as players see it.
--- @return table
local function BuildSummary()
    local q = dmhub.initiativeQueue
    if q ~= nil and q.hidden then
        q = nil
    end

    --combat start and end are events too.
    local combatid = nil
    if q ~= nil then
        combatid = q.guid
    end
    if g_baselineTaken and combatid ~= g_lastCombat then
        if combatid ~= nil then
            PushEvent{ kind = "combat-start" }
        else
            PushEvent{ kind = "combat-end" }
        end
    end
    g_lastCombat = combatid

    local summary = {
        v = FORMAT_VERSION,
        mode = "none",
        encounter = { title = EncounterTitle() },
        heroes = {},
    }

    local activeTokenIds = {}
    if q ~= nil then
        summary.mode = "combat"
        summary.round = q.round
        summary.turn, activeTokenIds = TurnInfo(q)
    end

    for _, token in ipairs(HeroTokens()) do
        if token.valid and token.properties ~= nil then
            local entry = HeroEntry(token, activeTokenIds)
            summary.heroes[#summary.heroes + 1] = entry
            CollectEvents(token, entry.state)
        end
    end

    summary.monsters = MonsterSummary(q)
    for _, token in ipairs(dmhub.GetTokens{unaffiliated = true}) do
        if IsShownToPlayers(token) then
            local state = "ok"
            if token.properties:IsDead() then
                state = "dead"
            elseif token.properties:CurrentHitpoints() <= token.properties:MaxHitpoints() / 2 then
                state = "winded"
            end
            CollectEvents(token, state)
        end
    end

    PruneReportedDamage()
    g_baselineTaken = true

    summary.events = {}
    for i, event in ipairs(g_events) do
        summary.events[i] = event
    end
    return summary
end

--- Shrink a summary that has grown past the size cap: drop older events, then
--- the monster groups (the band only needs the totals).
--- @param summary table
--- @return string json
local function FitToSize(summary)
    local text = dmhub.ToJson(summary)
    while #text > MAX_BYTES and #summary.events > 1 do
        table.remove(summary.events, 1)
        text = dmhub.ToJson(summary)
    end
    if #text > MAX_BYTES then
        summary.monsters.groups = {}
        text = dmhub.ToJson(summary)
    end
    return text
end

local g_lastWritten = nil
local g_lastWriteTime = -1000
local g_lastSeq = nil

local function Write(summary)
    local doc = mod:GetDocumentSnapshot(SUMMARY_DOC)
    doc:BeginChange()
    for k, _ in pairs(doc.data) do
        doc.data[k] = nil
    end
    for k, v in pairs(summary) do
        doc.data[k] = v
    end
    doc.data.updated = dmhub.serverTimeMilliseconds
    doc:CompleteChange("Stream overlay", {undoable = false})
end

local function Tick()
    if not StreamOverlay.IsEnabled() or not InEotwGame() or not IsPublisher() then
        --start fresh if we become the publisher later.
        g_baselineTaken = false
        g_lastSeq = nil
        return
    end

    if not g_baselineTaken then
        --carry on the event numbering of whoever published before us, so the
        --page never mistakes our first events for ones it has already shown.
        local previous = mod:GetDocumentSnapshot(SUMMARY_DOC).data
        local events = previous.events
        if type(events) == "table" and #events > 0 then
            g_eventSeq = math.max(g_eventSeq, tonumber(events[#events].seq) or 0)
        end
    end

    local now = dmhub.Time()
    local seq = dmhub.gameContentUpdateSeq
    local heartbeatDue = now - g_lastWriteTime >= HEARTBEAT_SECONDS
    if seq == g_lastSeq and g_baselineTaken and not heartbeatDue then
        return
    end
    if now - g_lastWriteTime < MIN_WRITE_SECONDS then
        --too soon after the last write; try again next poll.
        return
    end
    g_lastSeq = seq

    local summary = BuildSummary()
    local text = FitToSize(summary)
    if text == g_lastWritten and not heartbeatDue then
        return
    end
    Write(summary)
    g_lastWritten = text
    g_lastWriteTime = now
end

dmhub.Coroutine(function()
    while not mod.unloaded do
        local ok, err = pcall(Tick)
        if not ok then
            print("StreamOverlay:: publish failed:", err)
        end
        coroutine.yield(POLL_SECONDS)
    end
end)
