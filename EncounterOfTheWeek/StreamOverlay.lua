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

--- The creature id behind a casterInfo, as the feed keys creatures.
--- @param casterInfo any
--- @return nil|string
local function CasterId(casterInfo)
    if type(casterInfo) ~= "table" or type(casterInfo.tokenid) ~= "string" then
        return nil
    end
    local id = casterInfo.tokenid
    pcall(function()
        local tok = dmhub.GetTokenById(casterInfo.tokenid)
        if tok ~= nil and tok.charid ~= nil then
            id = tok.charid
        end
    end)
    return id
end

--- Who put each of a creature's conditions on it, by lower-cased condition
--- name: from Draw Steel's inflicted conditions and from ongoing effects,
--- both of which record the caster. A condition with no recorded caster, or
--- one the creature put on itself, is left out.
--- @param token CharacterToken
--- @return table<string, string> conditionName -> caster creature id
local function ConditionSources(token)
    local result = {}
    pcall(function()
        local props = token.properties
        local conditions = dmhub.GetTable(CharacterCondition.tableName) or {}
        for condid, entry in pairs(props:try_get("inflictedConditions", {})) do
            local info = conditions[condid]
            local id = type(entry) == "table" and CasterId(entry.casterInfo) or nil
            if info ~= nil and type(info.name) == "string" and id ~= nil and id ~= token.charid then
                result[string.lower(info.name)] = id
            end
        end
        local effects = dmhub.GetTable("characterOngoingEffects") or {}
        for _, effect in ipairs(props:ActiveOngoingEffects()) do
            local info = effects[effect.ongoingEffectid]
            if info ~= nil then
                local condInfo = conditions[info.condition]
                local name = (condInfo ~= nil and condInfo.name) or info.name
                local id = CasterId(effect:try_get("casterInfo"))
                if type(name) == "string" and id ~= nil and id ~= token.charid and result[string.lower(name)] == nil then
                    result[string.lower(name)] = id
                end
            end
        end
    end)
    return result
end

--- Marks each condition with byId, the creature that put it on, where known.
--- @param list table
--- @param token CharacterToken
--- @return table list
local function WithSources(list, token)
    local sources = ConditionSources(token)
    for _, c in ipairs(list) do
        c.byId = sources[string.lower(c.name or "")]
    end
    return list
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

--- Stamina can arrive as a float (33.0); the page shows whole numbers.
--- @param n nil|number
--- @return integer
local function Whole(n)
    return math.floor((tonumber(n) or 0) + 0.5)
end

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
        cur = Whole(props:CurrentHitpoints()),
        max = Whole(props:MaxHitpoints()),
        temp = Whole(props:TemporaryHitpoints()),
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
                group.cur = group.cur + math.max(0, Whole(props:CurrentHitpoints()))
                group.max = group.max + Whole(props:MaxHitpoints())
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

--- A combatant's turn this round, as the initiative bar shows it: "now" while
--- its turn runs, "acted" once taken, "waiting" before. Nil out of combat.
--- @param q nil|InitiativeQueue
--- @param token CharacterToken
--- @param activeTokenIds table<string, boolean>
--- @return nil|string
local function TurnStatusOf(q, token, activeTokenIds)
    if q == nil then
        return nil
    end
    if activeTokenIds[token.charid] then
        return "now"
    end
    local status = nil
    pcall(function()
        local initid = InitiativeQueue.GetInitiativeId(token)
        if initid ~= nil and q:HasInitiative(initid) then
            status = cond(q:HasHadTurn(initid), "acted", "waiting")
        end
    end)
    return status
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

--Events carry the token ids of who and target as whoId / targetId (only for
--tokens players can see) so the Streamer Kit's redaction can name them from
--its own snapshot. The overlay page ignores them.
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
                    whoId = cond(who ~= nil, entry.attackerid, nil),
                    target = targetName,
                    targetSide = targetSide,
                    targetId = tokenid,
                    amount = damage - reported.damage,
                    damageType = entry.damage_type,
                }
            end
            if targetName ~= nil and heal > reported.heal then
                PushEvent{
                    kind = "heal",
                    target = targetName,
                    targetSide = targetSide,
                    targetId = tokenid,
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
        PushEvent{ kind = "winded", target = targetName, targetSide = targetSide, targetId = tokenid }
    elseif state == "dying" then
        PushEvent{ kind = "dying", target = targetName, targetSide = targetSide, targetId = tokenid }
    elseif state == "dead" then
        PushEvent{ kind = cond(targetSide == "hero", "dead", "defeated"), target = targetName, targetSide = targetSide, targetId = tokenid }
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
--- @return table summary, nil|InitiativeQueue q, table<string, boolean> activeTokenIds
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
    return summary, q, activeTokenIds
end

-- ---------------------------------------------------------------------------
-- The Streamer Kit viewer feed
-- ---------------------------------------------------------------------------
--
--The viewer page (Streamer Kit, Phase 1) gets more than the band: hero cards
--with characteristics and surges, and foe cards with the abilities and
--villain actions a monster has used. This section gathers a RAW snapshot of
--that and passes it through StreamerKitRedact.Redact, the one gate that
--decides what viewers may see (EncounterOfTheWeek/StreamerKitRedact.lua; its
--header documents the raw shape). Only the redacted result is written, to its
--own document, so the raw snapshot never leaves this client.

local VIEWER_DOC = "streamerKitViewer"
--Ability text makes this document bigger than the band's; it is still
--downloaded by every client in the game, so keep a firm cap.
local VIEWER_MAX_BYTES = 48000

--Abilities each monster has used this combat: tokenid -> { [name] = true }.
--Built from each creature's synced "used this round" record
--(creature:AbilitiesUsedThisRound), which resets every round, so the union is
--kept here. A publisher that takes over mid-combat starts from what it sees
--then: it can under-report, never over-report.
local g_usedAbilities = {}
local g_usedAbilitiesCombat = nil
--each monster's initiative group from the last combat (charid -> {group,
--title}), kept after it ends; cleared when the next combat starts.
local g_monsterGroups = {}
local g_monsterGroupsCombat = nil

--- A characteristic's value, or nil.
--- @param props Creature
--- @param attrid string
--- @return nil|number
local function Characteristic(props, attrid)
    local value = nil
    pcall(function() value = props:GetAttribute(attrid):Value() end)
    return value
end

--The stored image id behind each portrait asset, by asset id: the lookup
--logs on every call, and a portrait seldom changes.
local g_portraitImageIds = {}

--- The hero's card art as the viewer page draws it: the stored image id (a
--- content-addressed id the server can fetch) and the crop the in-app hero
--- card cuts it with. nil while the portrait's asset record has not loaded,
--- or when the hero has no art.
--- @param token CharacterToken
--- @return nil|{image: string, rect: {x1: number, y1: number, x2: number, y2: number}}
local function HeroPortrait(token)
    local portrait = nil
    pcall(function() portrait = token.offTokenPortrait end)
    if type(portrait) ~= "string" or portrait == "" then
        return nil
    end
    local image = g_portraitImageIds[portrait]
    if image == nil then
        local known = false
        pcall(function() known = assets.allAssets[portrait] ~= nil end)
        if not known then
            return nil
        end
        pcall(function() image = dmhub.GetRawImageId(portrait) end)
        --an id that comes back unchanged was not an image asset.
        if type(image) ~= "string" or image == portrait then
            return nil
        end
        g_portraitImageIds[portrait] = image
    end
    local width, height = 132, 188
    local card = rawget(_G, "EotwHeroCard")
    if type(card) == "table" and type(card.CARD_WIDTH) == "number" and type(card.CARD_HEIGHT) == "number" then
        width, height = card.CARD_WIDTH, card.CARD_HEIGHT
    end
    local rect = { x1 = 0, y1 = 0, x2 = 1, y2 = 1 }
    pcall(function()
        local r = CardPortraitRect(token, width / height, portrait)
        if r ~= nil then
            rect = { x1 = r.x1, y1 = r.y1, x2 = r.x2, y2 = r.y2 }
        end
    end)
    return { image = image, rect = rect }
end

--- The name of the player who controls a hero, as the hero card shows it
--- (without the Player Tag). nil for an unclaimed or party hero.
--- @param token CharacterToken
--- @return nil|string
local function HeroPlayer(token)
    local owner = nil
    pcall(function() owner = token.ownerId end)
    if type(owner) ~= "string" or owner == "" or owner == "PARTY" then
        return nil
    end
    local name = nil
    pcall(function() name = dmhub.GetDisplayName(owner) end)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return name
end

--The card back's slow reads (abilities, skills, kit), per hero, reused for
--a while: the sheet's ability list builds a feature index each time.
local BACK_CACHE_SECONDS = 10
local g_backCache = {}

--the hero's own ability groups the back lists (free strikes and the standard
--actions are every hero's, so they stay off).
local BACK_ABILITY_GROUPS = { main = true, maneuver = true, triggered = true, other = true }

--- The slow part of the card back: subclass, kit, skills and abilities.
--- @param token CharacterToken
--- @param props creature
--- @return table
local function HeroBackSlow(token, props)
    local now = dmhub.Time()
    local cached = g_backCache[token.charid]
    if cached ~= nil and now - cached.at < BACK_CACHE_SECONDS then
        return cached.back
    end
    local back = { skills = {}, abilities = {} }
    --a hero's class reads live on character (GetClass, GetSubClass).
    local hero = props --[[@as character]]
    pcall(function()
        local classItem = hero:GetClass()
        if classItem ~= nil then
            back.className = classItem.name
            local sub = hero:GetSubClass(classItem)
            back.subclass = sub ~= nil and sub.name or nil
        end
    end)
    pcall(function() back.ancestry = props:RaceOrMonsterType() end)
    pcall(function()
        local kit = props:Kit()
        back.kit = kit ~= nil and kit.name or nil
    end)
    pcall(function()
        for _, skill in ipairs(Skill.SkillsInfo) do
            if props:ProficientInSkill(skill) then
                back.skills[#back.skills + 1] = skill.name
            end
        end
        table.sort(back.skills)
    end)
    pcall(function()
        local sheet = rawget(_G, "EotwHeroSheet")
        local d = sheet ~= nil and sheet.Data(token, {"resource", "abilities"}) or nil
        for _, group in ipairs(d ~= nil and d.abilities or {}) do
            if BACK_ABILITY_GROUPS[group.id] then
                for _, item in ipairs(group.items or {}) do
                    local kind = group.id
                    local cost = nil
                    if item.category == "Signature Ability" then
                        kind = "signature"
                    elseif item.ability ~= nil then
                        pcall(function()
                            if item.ability.resourceCost == CharacterResource.heroicResourceId then
                                cost = tonumber(item.ability:try_get("resourceNumber", 1))
                            end
                        end)
                        if cost ~= nil then
                            kind = "heroic"
                        end
                    end
                    back.abilities[#back.abilities + 1] = { name = item.name, kind = kind, cost = cost }
                end
            end
        end
    end)
    g_backCache[token.charid] = { at = now, back = back }
    return back
end

--- The back of the hero's card, as every player can turn it over in the
--- app (HeroCardBack.lua): the tac panel's public reads. Never the hero's
--- notes, gear, complications or downtime.
--- @param token CharacterToken
--- @param props creature
--- @return table
local function HeroBack(token, props)
    local slow = HeroBackSlow(token, props)
    local back = {
        className = slow.className, subclass = slow.subclass, ancestry = slow.ancestry, kit = slow.kit,
        skills = slow.skills, abilities = slow.abilities,
    }
    pcall(function() back.winded = props:BloodiedThreshold() end)
    pcall(function() back.death = props:KillThresholdStamina() end)
    pcall(function() back.recoveryValue = props:RecoveryAmount() end)
    pcall(function() back.heroTokens = props:GetHeroTokens() end)
    pcall(function() back.speed = props:CurrentMovementSpeed() end)
    pcall(function()
        back.disengage = props:GetCustomAttribute(CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"])
    end)
    pcall(function() back.stability = props:Stability() end)
    return back
end

--- @param token CharacterToken
--- @param activeTokenIds table<string, boolean>
--- @return table raw hero (see StreamerKitRedact)
local function RawHero(token, activeTokenIds)
    local props = token.properties
    local hero = {
        id = token.charid,
        name = token.name,
        namePrivate = token.namePrivate == true,
        stamina = {
            cur = props:CurrentHitpoints(),
            max = props:MaxHitpoints(),
            temp = props:TemporaryHitpoints(),
        },
        dead = props:IsDead(),
        dying = HeroState(props) == "dying",
        characteristics = {
            might = Characteristic(props, "mgt"),
            agility = Characteristic(props, "agl"),
            reason = Characteristic(props, "rea"),
            intuition = Characteristic(props, "inu"),
            presence = Characteristic(props, "prs"),
        },
        conditions = WithSources(HeroConditions(token), token),
        active = activeTokenIds[token.charid] == true,
    }
    if hero.name == nil or hero.name == "" then
        hero.name = PublicName(token)
    end
    pcall(function()
        hero.resource = { name = props:GetHeroicResourceName(), value = props:GetHeroicOrMaliceResources() }
    end)
    pcall(function()
        hero.recoveries = {
            cur = props:RecoveriesAvailableToSpend(),
            max = props:GetResources()[CharacterResource.recoveryResourceId] or 0,
        }
    end)
    pcall(function() hero.surges = props:GetAvailableSurges() end)
    pcall(function() hero.victories = props:GetVictories() end)
    pcall(function() hero.level = props:CharacterLevel() end)
    pcall(function() hero.portrait = HeroPortrait(token) end)
    pcall(function() hero.player = HeroPlayer(token) end)
    pcall(function()
        hero.back = HeroBack(token, props)
        hero.className = hero.back.className
        hero.ancestry = hero.back.ancestry
    end)
    return hero
end

--- A monster's conditions in the raw shape, each flagged hiddenFromEnemies from
--- its ongoing-effect record. Read from the effects, not from
--- TokenUI.CalculateStatusIcons: the HUD shows secret effects to a Director and
--- to whoever controls the token (the host running the Monster AI), and its
--- icons do not say which ones were secret. The redaction drops flagged ones.
--- @param props Creature
--- @return table
local function MonsterConditions(props)
    local result = {}
    pcall(function()
        local effects = dmhub.GetTable("characterOngoingEffects") or {}
        local conditions = dmhub.GetTable(CharacterCondition.tableName) or {}
        for _, effect in ipairs(props:ActiveOngoingEffects()) do
            local info = effects[effect.ongoingEffectid]
            if info ~= nil and info.statusEffect and not info.hiddenOnToken then
                local condInfo = conditions[info.condition]
                local name = (condInfo ~= nil and condInfo.name) or info.name
                if type(name) == "string" and name ~= "" then
                    result[#result + 1] = {
                        id = string.lower(name),
                        name = name,
                        hiddenFromEnemies = info.hiddenFromEnemies == true,
                    }
                end
            end
        end
    end)
    return result
end

--- Does this creature's own ability list carry a villain action? A cheap gate
--- before GetActivatedAbilities (about 2 ms a creature), as the initiative
--- bar's villain-action strip does.
--- @param props Creature
--- @return boolean
local function MayOwnVillainActions(props)
    local found = false
    pcall(function()
        for _, ability in ipairs(props:try_get("innateActivatedAbilities") or {}) do
            local key = ability:try_get("villainAction")
            if key ~= nil and key ~= "" then
                found = true
                return
            end
        end
    end)
    return found
end

--- A monster's abilities and villain actions in the raw shape. Used flags come
--- from g_usedAbilities and the shared villain-action state.
--- @param token CharacterToken
--- @param used table<string, boolean>
--- @return table abilities, table villainActions
local function RawMonsterAbilities(token, used)
    local abilities, villainActions = {}, {}
    local props = token.properties
    local wantVillain = MayOwnVillainActions(props)
    if next(used) == nil and not wantVillain then
        return abilities, villainActions
    end

    local list = nil
    pcall(function() list = props:GetActivatedAbilities() end)
    if type(list) ~= "table" then
        return abilities, villainActions
    end

    local seen = {}
    for _, ability in ipairs(list) do
        local name = nil
        local key = nil
        pcall(function()
            name = ability.name
            key = ability:try_get("villainAction")
        end)
        local description = nil
        pcall(function() description = ability.description end)
        if key ~= nil and key ~= "" then
            local wasUsed = false
            pcall(function() wasUsed = VillainActionState.HasUsed(token.charid, key) end)
            villainActions[#villainActions + 1] = { key = key, name = name, text = description, used = wasUsed }
        elseif type(name) == "string" and used[name] and not seen[name] then
            seen[name] = true
            abilities[#abilities + 1] = { name = name, text = description, used = true }
        end
    end
    --slot order: "Villain Action 1", "Villain Action 2", ...
    table.sort(villainActions, function(a, b) return tostring(a.key) < tostring(b.key) end)
    return abilities, villainActions
end

--how the last combat ended ("victory" or nil) and which combat that was.
local g_outcome = nil
local g_outcomeCombat = nil

--- How many recent History entries the viewer feed looks back over, and how
--- many of the newest it reads again each time (a reveal or an Undo rewrites
--- an entry in place).
local HISTORY_LOOKBACK = 40
local HISTORY_REREAD = 6

--key -> the players' cut of a History entry (false when players get none).
local g_historyCache = {}
local g_historyMap = nil

--- A creature from a History entry, as the viewer feed keeps it.
--- @param c any
--- @return nil|table
local function RawHistoryCreature(c)
    if type(c) ~= "table" then
        return nil
    end
    return { id = c.id, name = c.name, secret = c.secret == true, hero = c.hero == true }
end

--- This combat's actions from History (Draw Steel V/History.lua), in the cut
--- players read (History.PlayerEntry): who used what, on whom, the roll, and
--- what it did to each target. Nil when History is off.
--- @param q table the initiative queue
--- @return nil|table
local function RawActions(q)
    local history = rawget(_G, "History")
    if history == nil or history.PlayerEntry == nil or not history.Enabled() then
        return nil
    end
    local mapid = history.CurrentMap()
    if mapid == nil then
        return nil
    end
    if mapid ~= g_historyMap then
        g_historyCache = {}
        g_historyMap = mapid
    end
    local keys = history.Keys(mapid)
    local actions = {}
    local first = math.max(1, #keys - HISTORY_LOOKBACK + 1)
    for i = first, #keys do
        local key = keys[i]
        local entry = g_historyCache[key]
        if entry == nil or i > #keys - HISTORY_REREAD then
            entry = history.PlayerEntry(mapid, key) or false
            g_historyCache[key] = entry
        end
        if entry and entry.kind == "action" and entry.encounter == q.guid and entry.reverted == nil and entry.ability ~= nil then
            local action = {
                t = entry.t,
                round = entry.round,
                actor = RawHistoryCreature(entry.actor),
                ability = entry.ability.name,
                villain = entry.ability.villainaction ~= nil,
                targets = {},
            }
            if type(entry.roll) == "table" and not entry.secretroll then
                action.roll = { total = entry.roll.total, tier = entry.roll.tier }
            end
            for _, target in ipairs(entry.targets or {}) do
                local t = RawHistoryCreature(target)
                if t ~= nil then
                    t.tier = target.tier
                    t.taken = target.taken
                    t.healed = target.healed
                    t.state = target.state
                    t.conds = {}
                    for _, c in ipairs(target.conds or {}) do
                        if type(c) == "table" and not c.secret then
                            t.conds[#t.conds + 1] = c.name
                        end
                    end
                    action.targets[#action.targets + 1] = t
                end
            end
            actions[#actions + 1] = action
        end
    end
    --drop cached entries that have scrolled out of the look-back.
    if first > 1 then
        for i = 1, first - 1 do
            g_historyCache[keys[i]] = nil
        end
    end
    return actions
end

--- The montage as the party's screen shows it, or nil when no montage is
--- running. Only what every player can see goes in: entries already on the
--- board (EncounterMontage.EntryHidden keeps locked, removed and expired ones
--- out, and later rounds are not on it yet), the option a hero has chosen
--- once it is chosen, and the montage log. StreamerKitRedact still decides
--- what leaves.
--- @return nil|table
--The last montage seen to finish (its block as of its "done" phase): the
--feed keeps it as pastMontage, so viewers can still look back at it after
--the next beat starts. Replaced when another montage finishes; after a
--reload it comes back from the saved totals (SavedMontage).
local g_pastMontage = nil

--- The last finished montage from the encounter doc's saved totals, for when
--- g_pastMontage was lost (a reload): title and totals, no board or log.
--- @return nil|table
local function SavedMontage()
    local montage = rawget(_G, "EncounterMontage")
    if montage == nil then
        return nil
    end
    local doc = montage.GetDoc()
    local script = montage.FindMapScript()
    local beats = script and script.parse and script.parse.beats or {}
    local bestIndex, best = nil, nil
    for key, totals in pairs(doc.data.montageTotals or {}) do
        local index = tonumber(string.match(tostring(key), "^b(%d+)$"))
        local beat = index ~= nil and beats[index] or nil
        if type(totals) == "table" and beat ~= nil and beat.kind == "montage" and (bestIndex == nil or index > bestIndex) then
            bestIndex = index
            local rounds = #(beat.rounds or {})
            best = {
                title = beat.title,
                round = math.max(rounds, 1),
                rounds = rounds,
                phase = "done",
                successes = tonumber(totals.successes) or 0,
                failures = tonumber(totals.failures) or 0,
                unvanquished = tonumber(totals.unvanquished) or 0,
                board = {},
                log = {},
            }
        end
    end
    return best
end

--- The montage block (see StreamerKitRedact), phase "done" included.
--- @return nil|table
local function RawMontage()
    local montage = rawget(_G, "EncounterMontage")
    if montage == nil then
        return nil
    end
    local m = montage.GetState()
    if m == nil then
        return nil
    end
    local beat = montage.CurrentBeat()
    if beat == nil or beat.kind ~= "montage" then
        return nil
    end
    local round = tonumber(m.round) or 1

    local totals = montage.TotalsFromLog(m)
    local raw = {
        title = beat.title,
        round = round,
        rounds = #(beat.rounds or {}),
        phase = m.phase,
        successes = totals.successes,
        failures = totals.failures,
        unvanquished = totals.unvanquished,
        board = {},
        log = {},
    }

    for _, r in ipairs(beat.rounds or {}) do
        for _, entry in ipairs(r.entries or {}) do
            if (tonumber(entry.round) or 1) <= round and not montage.EntryHidden(m, beat, entry) then
                local state = "open"
                if entry.kind == "opportunity" and (m.taken or {})[entry.id] then
                    state = "taken"
                elseif entry.kind == "threat" and (m.vanquished or {})[entry.id] then
                    state = "vanquished"
                end
                raw.board[#raw.board + 1] = {
                    id = entry.id,
                    kind = entry.kind,
                    name = entry.name,
                    state = state,
                    temporary = entry.temporary == true,
                    remaining = cond(entry.kind == "threat", montage.ThreatRemaining(m, entry), nil),
                }
            end
        end
    end

    local t = m.turn
    if type(t) == "table" and t.status ~= "resolved" then
        local heroName = nil
        for _, hero in ipairs(montage.Heroes()) do
            if hero.charid == t.heroid then
                heroName = hero.name
            end
        end
        local entry = montage.TurnEntry(beat, t)
        local turn = {
            hero = heroName,
            entry = entry ~= nil and entry.name or nil,
            status = t.status,
        }
        --the option once the hero has picked it (not while choosing).
        if t.optionIndex ~= nil and t.status ~= "choosing" and entry ~= nil then
            local option = (entry.options or {})[t.optionIndex]
            turn.option = option ~= nil and option.name or nil
        end
        if t.tier ~= nil then
            turn.tier = tonumber(t.tier)
        end
        raw.turn = turn
    end

    for _, e in ipairs(m.log or {}) do
        if type(e) == "table" then
            raw.log[#raw.log + 1] = {
                round = tonumber(e.round),
                hero = e.heroName,
                entry = e.entryName,
                option = e.optionName,
                tier = tonumber(e.tier),
                passed = e.passed == true,
                consequence = e.consequence == true,
            }
        end
    end
    return raw
end

-- ---------------------------------------------------------------------------
-- The box score (per-round tallies for the viewer page's Box score view)
-- ---------------------------------------------------------------------------
--
--Each publish pass during combat compares every combatant's stamina (temporary
--stamina included) and conditions with the last pass, and adds the change to
--the current round: damage taken, healing (heroes only) and conditions gained
--or ended. Sampling stamina catches every source (abilities, ongoing damage,
--edits by hand), which History does not. Minions share their squad's pool, so
--a squad is sampled once. Foes are tallied per initiative group.
--
--The tallies live in their own document as JSON, so a reload picks them up
--where they were; a new combat starts them over, and after the combat they
--stay as the fight's recap until the next one.
--
--Each round also keeps its turns in the order taken: a turn starts when a
--different hero or foe group becomes the one acting, and everything that
--changes until the next turn starts counts in it (triggered actions between
--turns included). A turn credits its actor with the damage dealt to, and the
--creatures downed on, the other side. Changes before a round's first turn
--count in the round only.

local BOX_DOC = "streamerKitBoxScore"
local BOX_MAX_ROUNDS = 30
local BOX_MAX_TURNS = 20
local g_box = nil

--- @return table
local function NewBox(combatid)
    return { combat = combatid, maxRound = 0, rows = {}, order = {}, pools = {}, conds = {}, down = {}, turns = {} }
end

--- The saved tallies, or nil.
--- @return nil|table
local function LoadBox()
    local box = nil
    pcall(function()
        local text = mod:GetDocumentSnapshot(BOX_DOC).data.box
        if type(text) == "string" then
            box = dmhub.FromJson(text)
        end
    end)
    if type(box) ~= "table" or type(box.rows) ~= "table" then
        return nil
    end
    box.order = type(box.order) == "table" and box.order or {}
    box.pools = type(box.pools) == "table" and box.pools or {}
    box.conds = type(box.conds) == "table" and box.conds or {}
    box.down = type(box.down) == "table" and box.down or {}
    box.turns = type(box.turns) == "table" and box.turns or {}
    box.maxRound = tonumber(box.maxRound) or 0
    return box
end

--- A cell in a table of cells, made on first use.
local function BoxCell(cells, key)
    local cell = cells[key]
    if type(cell) ~= "table" then
        cell = { t = 0, h = 0, d = 0, g = {}, e = {} }
        cells[key] = cell
    end
    cell.g = type(cell.g) == "table" and cell.g or {}
    cell.e = type(cell.e) == "table" and cell.e or {}
    return cell
end

--- Where a change lands this pass: the round, the turn in play (if any), and
--- that turn's record, for crediting its actor.
--- @return table
local function BoxAt(round, turnIndex, turn)
    return { round = round, ti = turnIndex, turn = turn }
end

--- The cells a change for this row adds to: the round's, and the turn's.
--- @return table[]
local function BoxCells(row, at)
    local cells = { BoxCell(row.r, "r" .. at.round) }
    if at.ti ~= nil then
        cells[2] = BoxCell(row.t, "r" .. at.round .. "t" .. at.ti)
    end
    return cells
end

--- Credit the turn's actor when the change lands on the other side.
local function BoxCredit(row, at, field, amount)
    local turn = at.turn
    if turn ~= nil and turn.s ~= nil and turn.s ~= row.side then
        turn[field] = (tonumber(turn[field]) or 0) + amount
    end
end

--- The row for a key, made on first use.
local function BoxRow(box, key, side, id, group)
    local row = box.rows[key]
    if type(row) ~= "table" then
        row = { side = side, id = id, group = group, r = {}, t = {} }
        box.rows[key] = row
        box.order[#box.order + 1] = key
    end
    row.r = type(row.r) == "table" and row.r or {}
    row.t = type(row.t) == "table" and row.t or {}
    return row
end

--- Add a stamina sample's change. Returns true if it changed.
local function BoxStamina(box, poolKey, sample, row, at, countHealing)
    local prev = tonumber(box.pools[poolKey])
    box.pools[poolKey] = sample
    if prev == nil or sample == prev then
        return prev == nil
    end
    if sample < prev then
        for _, cell in ipairs(BoxCells(row, at)) do
            cell.t = (tonumber(cell.t) or 0) + (prev - sample)
        end
        BoxCredit(row, at, "dealt", prev - sample)
    elseif countHealing then
        for _, cell in ipairs(BoxCells(row, at)) do
            cell.h = (tonumber(cell.h) or 0) + (sample - prev)
        end
    end
    return true
end

--- Count a creature going down (a foe dead, a hero dying or dead). Returns
--- true if its state changed.
local function BoxDown(box, creatureKey, isDown, row, at)
    local prev = box.down[creatureKey]
    box.down[creatureKey] = isDown
    if prev == nil or prev == isDown then
        return prev == nil
    end
    if isDown then
        for _, cell in ipairs(BoxCells(row, at)) do
            cell.d = (tonumber(cell.d) or 0) + 1
        end
        BoxCredit(row, at, "downs", 1)
    end
    return true
end

--- Note conditions gained and ended since the last pass. Returns true if any.
local function BoxConditions(box, creatureKey, names, row, at)
    local prev = box.conds[creatureKey]
    box.conds[creatureKey] = names
    if type(prev) ~= "table" then
        return true
    end
    local changed = false
    for name, _ in pairs(names) do
        if not prev[name] then
            for _, cell in ipairs(BoxCells(row, at)) do
                if cell.e[name] then
                    cell.e[name] = nil
                else
                    cell.g[name] = true
                end
            end
            changed = true
        end
    end
    for name, _ in pairs(prev) do
        if not names[name] then
            for _, cell in ipairs(BoxCells(row, at)) do
                if cell.g[name] then
                    cell.g[name] = nil
                else
                    cell.e[name] = true
                end
            end
            changed = true
        end
    end
    return changed
end

--- Who is acting this pass, as a box row key and side: a hero's id, or a
--- foe's group key (else its id). A hidden foe acts as "?" so its turn still
--- starts but names nobody. Nil between turns.
--- @return nil|string key, nil|string side
local function BoxActor(raw)
    if raw.turn == nil or type(raw.turn.tokenIds) ~= "table" then
        return nil, nil
    end
    local keys = {}
    for _, hero in ipairs(raw.heroes) do
        if hero.id ~= nil then
            keys[hero.id] = { hero.id, "hero" }
        end
    end
    for _, monster in ipairs(raw.monsters) do
        if monster.id ~= nil then
            keys[monster.id] = monster.hidden and { "?", "foe" } or { monster.group or monster.id, "foe" }
        end
    end
    local best = nil
    for _, tokenid in ipairs(raw.turn.tokenIds) do
        local k = keys[tokenid]
        if k ~= nil and (best == nil or (best[1] == "?" and k[1] ~= "?") or (k[1] ~= "?" and k[1] < best[1])) then
            best = k
        end
    end
    if best == nil then
        return nil, nil
    end
    return best[1], best[2]
end

--- @return table<string, boolean>
local function ConditionNames(list, dropSecret)
    local names = {}
    for _, c in ipairs(list or {}) do
        if type(c) == "table" and type(c.name) == "string" and not (dropSecret and c.hiddenFromEnemies) then
            names[c.name] = true
        end
    end
    return names
end

--- @return string[]
local function SortedKeys(set)
    local list = {}
    for k, _ in pairs(set or {}) do
        list[#list + 1] = k
    end
    table.sort(list)
    return list
end

--- Update the tallies from this pass's raw heroes and monsters, and give the
--- box score block for the raw snapshot (nil before any combat was seen).
--- @param raw table
--- @param q nil|InitiativeQueue
--- @return nil|table
local function UpdateBoxScore(raw, q)
    if g_box == nil then
        g_box = LoadBox()
    end
    local changed = false
    if q ~= nil and (g_box == nil or g_box.combat ~= q.guid) then
        g_box = NewBox(q.guid)
        changed = true
    end
    if g_box == nil then
        return nil
    end
    local box = g_box
    local actor = nil

    if q ~= nil then
        local round = math.max(1, math.min(tonumber(q.round) or 1, BOX_MAX_ROUNDS))
        if round > box.maxRound then
            box.maxRound = round
            changed = true
        end

        --the turn in play: a new one when someone else starts acting.
        local side
        actor, side = BoxActor(raw)
        local rkey = "r" .. round
        local turns = type(box.turns[rkey]) == "table" and box.turns[rkey] or {}
        box.turns[rkey] = turns
        local last = turns[#turns]
        if actor ~= nil and (last == nil or last.a ~= actor) and #turns < BOX_MAX_TURNS then
            last = { a = actor, s = side, dealt = 0, downs = 0 }
            turns[#turns + 1] = last
            changed = true
        end
        local at = BoxAt(round, #turns > 0 and #turns or nil, last)

        for _, hero in ipairs(raw.heroes) do
            if hero.id ~= nil then
                local row = BoxRow(box, hero.id, "hero", hero.id, nil)
                local s = hero.stamina or {}
                local sample = (tonumber(s.cur) or 0) + (tonumber(s.temp) or 0)
                changed = BoxStamina(box, hero.id, sample, row, at, true) or changed
                changed = BoxDown(box, hero.id, hero.dead == true or hero.dying == true, row, at) or changed
                changed = BoxConditions(box, hero.id, ConditionNames(hero.conditions, false), row, at) or changed
            end
        end
        local sampled = {}
        for _, monster in ipairs(raw.monsters) do
            if not monster.hidden and monster.id ~= nil then
                local key = monster.group or monster.id
                local row = BoxRow(box, key, "foe", monster.id, monster.group)
                local pool = monster.id
                if monster.minion and monster.squad ~= nil then
                    pool = "squad/" .. tostring(monster.squad)
                end
                if not sampled[pool] then
                    sampled[pool] = true
                    local s = monster.stamina or {}
                    local sample = (tonumber(s.cur) or 0) + (tonumber(s.temp) or 0)
                    changed = BoxStamina(box, pool, sample, row, at, false) or changed
                end
                changed = BoxDown(box, monster.id, monster.dead == true, row, at) or changed
                changed = BoxConditions(box, monster.id, ConditionNames(monster.conditions, true), row, at) or changed
            end
        end
    end

    if changed then
        pcall(function()
            local doc = mod:GetDocumentSnapshot(BOX_DOC)
            doc:BeginChange()
            doc.data.box = dmhub.ToJson(box)
            doc:CompleteChange("Box score", {undoable = false})
        end)
    end

    local current = q ~= nil and math.max(1, math.min(tonumber(q.round) or 1, BOX_MAX_ROUNDS)) or nil
    local out = {
        current = current,
        rounds = box.maxRound,
        turns = {},
        heroes = {},
        foes = {},
    }
    --each round's turns in order; the last of the round in play is "now"
    --while its actor is still the one acting.
    local turnCounts = {}
    for r = 1, box.maxRound do
        local list = {}
        local turns = type(box.turns) == "table" and box.turns["r" .. r] or nil
        if type(turns) == "table" then
            for i, turn in ipairs(turns) do
                if type(turn) == "table" then
                    list[#list + 1] = {
                        actor = turn.a ~= "?" and turn.a or nil,
                        side = turn.s,
                        dealt = tonumber(turn.dealt) or 0,
                        downs = tonumber(turn.downs) or 0,
                        now = r == current and i == #turns and actor ~= nil and actor == turn.a or nil,
                    }
                end
            end
        end
        out.turns[r] = list
        turnCounts[r] = #list
    end
    local function OutCell(cell)
        return {
            taken = tonumber(cell.t) or 0,
            healed = tonumber(cell.h) or 0,
            down = tonumber(cell.d) or 0,
            gained = SortedKeys(cell.g),
            ended = SortedKeys(cell.e),
        }
    end
    for _, key in ipairs(box.order) do
        local row = box.rows[key]
        if type(row) == "table" then
            local cells = {}
            for r = 1, box.maxRound do
                local cell = type(row.r) == "table" and row.r["r" .. r] or nil
                if type(cell) == "table" then
                    cells[r] = OutCell(cell)
                else
                    cells[r] = { taken = 0, healed = 0, down = 0, gained = {}, ended = {} }
                end
                --only the turns where something happened to this row.
                local byTurn = {}
                for i = 1, turnCounts[r] do
                    local tc = type(row.t) == "table" and row.t["r" .. r .. "t" .. i] or nil
                    if type(tc) == "table" then
                        local c = OutCell(tc)
                        c.i = i
                        byTurn[#byTurn + 1] = c
                    end
                end
                cells[r].turns = byTurn
            end
            if row.side == "hero" then
                out.heroes[#out.heroes + 1] = { id = row.id, cells = cells }
            elseif row.side == "foe" then
                out.foes[#out.foes + 1] = { id = row.id, group = row.group, cells = cells }
            end
        end
    end
    return out
end

--- The raw (Director-level) snapshot for the viewer feed. Malice is never
--- collected: viewers do not see it (decided 2026-11-27), and what is not
--- gathered cannot leak.
--- @param summary table the band summary built this tick
--- @param q nil|InitiativeQueue
--- @param activeTokenIds table<string, boolean>
--- @return table
local function BuildViewerRaw(summary, q, activeTokenIds)
    local combatid = q ~= nil and q.guid or nil
    if combatid ~= g_usedAbilitiesCombat then
        g_usedAbilities = {}
        g_usedAbilitiesCombat = combatid
    end
    if combatid ~= nil and combatid ~= g_monsterGroupsCombat then
        g_monsterGroups = {}
        g_monsterGroupsCombat = combatid
    end

    local raw = {
        mode = summary.mode,
        round = summary.round,
        encounter = { title = summary.encounter and summary.encounter.title },
        heroes = {},
        monsters = {},
        events = summary.events,
    }

    if q ~= nil and summary.turn ~= nil then
        raw.turn = { kind = summary.turn.kind, tokenIds = {} }
        for tokenid, _ in pairs(activeTokenIds) do
            raw.turn.tokenIds[#raw.turn.tokenIds + 1] = tokenid
        end
    end

    --the objective as players see it: EotW always shows it until it is won.
    local won = false
    if q ~= nil then
        pcall(function()
            local live = q:try_get("liveEncounter")
            if type(live) == "table" and live:CheckVictory() then
                won = true
            elseif type(live) == "table" then
                local text = live:GetObjectiveText()
                if type(text) == "string" then
                    text = string.gsub(text, "^Objective: ", "")
                end
                local objective = { label = text }
                local condition = live:try_get("victoryCondition", "all_defeated")
                if live:ScriptVictoryText() == nil and (condition == "all_defeated" or condition == "nonminions_defeated") then
                    objective.progress, objective.goal = live:GetDefeatProgress()
                end
                raw.encounter.objective = objective
            end
        end)
    end

    --the outcome sticks after the combat closes, so the viewer page can still
    --make the recap card; a new combat clears it.
    if combatid ~= nil and combatid ~= g_outcomeCombat then
        g_outcome = nil
        g_outcomeCombat = combatid
    end
    if won and g_outcome == nil then
        g_outcome = "victory"
        if g_baselineTaken then
            PushEvent{ kind = "victory" }
        end
    end
    raw.outcome = g_outcome

    if q ~= nil then
        local ok, actions = pcall(RawActions, q)
        if ok then
            raw.actions = actions
        else
            print("StreamOverlay:: history actions failed:", actions)
        end
    end

    --a montage beat: its own mode and block (combat wins if both somehow are).
    if q == nil then
        local ok, montage = pcall(RawMontage)
        if ok and montage ~= nil and montage.phase == "done" then
            montage.turn = nil
            g_pastMontage = montage
        elseif ok and montage ~= nil then
            raw.mode = "montage"
            raw.montage = montage
        elseif not ok then
            print("StreamOverlay:: montage snapshot failed:", montage)
        end
    end
    if raw.mode ~= "montage" and g_pastMontage == nil then
        local ok, saved = pcall(SavedMontage)
        if ok then
            g_pastMontage = saved
        end
    end
    if raw.mode ~= "montage" and g_pastMontage ~= nil then
        raw.pastMontage = g_pastMontage
    end

    for _, token in ipairs(HeroTokens()) do
        if token.valid and token.properties ~= nil then
            local ok, hero = pcall(RawHero, token, activeTokenIds)
            if ok then
                hero.turnStatus = TurnStatusOf(q, token, activeTokenIds)
                raw.heroes[#raw.heroes + 1] = hero
            end
        end
    end

    local eotw = rawget(_G, "EncounterOfTheWeekGame")
    for _, token in ipairs(dmhub.GetTokens{unaffiliated = true}) do
        if token.valid and token.properties ~= nil and not token.isObject then
            local shown = IsShownToPlayers(token)
            local bystander = false
            if shown and eotw ~= nil then
                pcall(function() bystander = eotw.IsBystander(token) end)
            end
            if not shown then
                --kept only as an id, so events and turn names that mention
                --it are dropped by the redaction.
                raw.monsters[#raw.monsters + 1] = { id = token.charid, hidden = true }
            elseif not bystander then
                local props = token.properties
                local used = g_usedAbilities[token.charid] or {}
                if combatid ~= nil then
                    pcall(function()
                        for name, _ in pairs(props:AbilitiesUsedThisRound()) do
                            used[name] = true
                        end
                    end)
                    g_usedAbilities[token.charid] = used
                end
                local monster = {
                    id = token.charid,
                    name = PublicName(token),
                    namePrivate = token.namePrivate == true,
                    stamina = { cur = props:CurrentHitpoints(), max = props:MaxHitpoints(), temp = props:TemporaryHitpoints() },
                    dead = props:IsDead(),
                    conditions = {},
                }
                pcall(function() monster.squad = props:MinionSquad() end)
                monster.minion = monster.squad ~= nil
                pcall(function() monster.monsterType = props:GetMonsterType() end)
                --the initiative group it acts with, and the group's title.
                --Remembered per monster, so the groups outlive the initiative
                --queue: the end-of-fight list and the recap card stay grouped.
                local initiative = rawget(_G, "InitiativeQueue")
                if q ~= nil and initiative ~= nil then
                    pcall(function()
                        local groupid = initiative.GetInitiativeId(token)
                        if groupid ~= nil then
                            monster.group = groupid
                            monster.groupTitle = q:DescribeEntry(groupid)
                            g_monsterGroups[token.charid] = { group = groupid, title = monster.groupTitle }
                        end
                    end)
                elseif q == nil then
                    local remembered = g_monsterGroups[token.charid]
                    if remembered ~= nil then
                        monster.group = remembered.group
                        monster.groupTitle = remembered.title
                    elseif initiative ~= nil then
                        --after a reload the memory is gone, but the token
                        --still carries its group (initiativeGrouping, or its
                        --squad); the title is filled in below.
                        pcall(function() monster.group = initiative.GetInitiativeId(token) end)
                    end
                end
                monster.conditions = WithSources(MonsterConditions(props), token)
                monster.turnStatus = TurnStatusOf(q, token, activeTokenIds)
                monster.abilities, monster.villainActions = RawMonsterAbilities(token, used)
                raw.monsters[#raw.monsters + 1] = monster
            end
        end
    end


    --groups read back from the tokens have no title (it lived on the
    --initiative queue): name them for their leader, else their first member,
    --as the queue does.
    local titles = {}
    for _, monster in ipairs(raw.monsters) do
        if monster.group ~= nil and monster.groupTitle == nil then
            local t = titles[monster.group]
            if t == nil or (t.minion and not monster.minion) then
                titles[monster.group] = { name = monster.name, minion = monster.minion }
            end
        end
    end
    for _, monster in ipairs(raw.monsters) do
        if monster.group ~= nil and monster.groupTitle == nil and titles[monster.group] ~= nil then
            monster.groupTitle = titles[monster.group].name
        end
    end

    local okBox, box = pcall(UpdateBoxScore, raw, q)
    if okBox then
        raw.boxScore = box
    else
        print("StreamOverlay:: box score failed:", box)
    end
    return raw
end

--- Shrink the viewer snapshot past its cap: drop ability text, then older
--- events, then older actions, then foes' ability lists.
--- @param viewer table
--- @return string json
local function FitViewerToSize(viewer)
    local text = dmhub.ToJson(viewer)
    if #text > VIEWER_MAX_BYTES then
        for _, foe in ipairs(viewer.foes.list) do
            for _, ability in ipairs(foe.abilities) do
                ability.text = nil
            end
            for _, action in ipairs(foe.villainActions) do
                action.text = nil
            end
        end
        text = dmhub.ToJson(viewer)
    end
    --a finished montage is the first thing to give up: its board, then its log.
    if #text > VIEWER_MAX_BYTES and viewer.pastMontage ~= nil then
        viewer.pastMontage.board = {}
        text = dmhub.ToJson(viewer)
        if #text > VIEWER_MAX_BYTES then
            viewer.pastMontage.log = {}
            text = dmhub.ToJson(viewer)
        end
    end
    --then the box score's turn detail for rounds not in play (their totals stay).
    if #text > VIEWER_MAX_BYTES and viewer.boxScore ~= nil then
        for _, rows in ipairs({viewer.boxScore.heroes or {}, viewer.boxScore.foes or {}}) do
            for _, row in ipairs(rows) do
                for r, cell in ipairs(row.cells or {}) do
                    if r ~= viewer.boxScore.current then
                        cell.turns = {}
                    end
                end
            end
        end
        text = dmhub.ToJson(viewer)
    end
    --then the card backs' long lists: abilities, then skills.
    for _, field in ipairs({"abilities", "skills"}) do
        if #text > VIEWER_MAX_BYTES then
            for _, hero in ipairs(viewer.heroes or {}) do
                if hero.back ~= nil then
                    hero.back[field] = {}
                end
            end
            text = dmhub.ToJson(viewer)
        end
    end
    while #text > VIEWER_MAX_BYTES and #viewer.events > 1 do
        table.remove(viewer.events, 1)
        text = dmhub.ToJson(viewer)
    end
    while #text > VIEWER_MAX_BYTES and viewer.actions ~= nil and #viewer.actions > 1 do
        table.remove(viewer.actions, 1)
        text = dmhub.ToJson(viewer)
    end
    if #text > VIEWER_MAX_BYTES then
        for _, foe in ipairs(viewer.foes.list) do
            foe.abilities = {}
        end
        text = dmhub.ToJson(viewer)
    end
    return text
end

--- The viewer snapshot as last published, for checking from the console.
--- @return table
function StreamOverlay.CurrentViewerSnapshot()
    return mod:GetDocumentSnapshot(VIEWER_DOC).data
end

-- ---------------------------------------------------------------------------
-- Going live (the Codex menu's Go Live dialog, EncounterOfTheWeekHud.lua)
-- ---------------------------------------------------------------------------
--
--Going live turns the stream outputs on and gives the game a short viewer
--code; the game server serves the viewer feed for that code (src/viewer.ts
--in cloudflare-game-server) once the settings document holds
--  enabled = true, viewerCode = "KX7P2Q", viewerDelay = <seconds>
--Ending the stream clears the code, which tells the server to close the
--viewers' session and free the code; going live again makes a new one.

--- The streamer's settings as the dialog shows them.
--- @return {live: boolean, code: nil|string, delay: integer}
function StreamOverlay.LiveSettings()
    local data = {}
    pcall(function() data = mod:GetDocumentSnapshot(SETTINGS_DOC).data end)
    local code = data.viewerCode
    local hasCode = rawget(_G, "StreamerKitRedact") ~= nil and StreamerKitRedact.IsViewerCode(code)
    return {
        live = data.enabled == true and hasCode,
        code = cond(hasCode, code, nil),
        delay = tonumber(data.viewerDelay) or 0,
    }
end

--- Go live with a new viewer code and the given delay (seconds). Any host may
--- call it; the elected host's client is the one that publishes.
--- @param delaySeconds number
--- @return nil|string code nil if no code could be made (the settings are left alone)
function StreamOverlay.GoLive(delaySeconds)
    local code = StreamerKitRedact.ViewerCodeFromHex(dmhub.GenerateGuid() .. dmhub.GenerateGuid())
    if code == nil then
        return nil
    end
    local doc = mod:GetDocumentSnapshot(SETTINGS_DOC)
    doc:BeginChange()
    doc.data.enabled = true
    doc.data.viewerCode = code
    doc.data.viewerDelay = StreamerKitRedact.ClampDelay(delaySeconds)
    doc:CompleteChange("Go live", {undoable = false})
    return code
end

--- Change the delay while live. Snapshots already waiting keep their time;
--- the server never lets viewers see an older snapshot after a newer one.
--- @param delaySeconds number
function StreamOverlay.SetViewerDelay(delaySeconds)
    local doc = mod:GetDocumentSnapshot(SETTINGS_DOC)
    doc:BeginChange()
    doc.data.viewerDelay = StreamerKitRedact.ClampDelay(delaySeconds)
    doc:CompleteChange("Stream delay", {undoable = false})
end

--- End the stream: outputs off, the code dropped (the server ends the
--- viewers' session), and the viewer document emptied.
function StreamOverlay.EndLive()
    local doc = mod:GetDocumentSnapshot(SETTINGS_DOC)
    doc:BeginChange()
    doc.data.enabled = false
    doc.data.viewerCode = nil
    doc:CompleteChange("End stream", {undoable = false})

    local viewer = mod:GetDocumentSnapshot(VIEWER_DOC)
    viewer:BeginChange()
    for k, _ in pairs(viewer.data) do
        viewer.data[k] = nil
    end
    viewer:CompleteChange("Streamer Kit viewer cleared", {undoable = false})
end

--- The game server this game's viewers connect to: the one EotW games are
--- created on (same rule as EotwRoster.UseStaging; admins may pick staging).
--- @return string
function StreamOverlay.ViewerHost()
    local staging = dmhub.isAdminAccount == true and dmhub.GetSettingValue("eotw:server") == "staging"
    return cond(staging, "https://game-server-staging.codexback.com", "https://game-server.codexback.com")
end

--- The link viewers open for a code.
--- @param code string
--- @return string
function StreamOverlay.ViewerUrl(code)
    return string.format("%s/v/%s", StreamOverlay.ViewerHost(), code)
end

--- The settings document's path, for a panel's monitorGame.
--- @return string
function StreamOverlay.SettingsPath()
    return mod:GetDocumentPath(SETTINGS_DOC)
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

local g_lastViewerWritten = nil

--- Replace the viewer document with the redacted snapshot. Only the output of
--- StreamerKitRedact.Redact is ever written here. Like the band's document it
--- is not registered for checkpoint backups.
--- @param viewer table
local function WriteViewer(viewer)
    local doc = mod:GetDocumentSnapshot(VIEWER_DOC)
    --a rising number, carried across publishers, so the page and the
    --server can order snapshots.
    local seq = (tonumber(doc.data.seq) or 0) + 1
    doc:BeginChange()
    for k, _ in pairs(doc.data) do
        doc.data[k] = nil
    end
    for k, v in pairs(viewer) do
        doc.data[k] = v
    end
    doc.data.seq = seq
    doc.data.updated = dmhub.serverTimeMilliseconds
    doc:CompleteChange("Streamer Kit viewer", {undoable = false})
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

    local summary, q, activeTokenIds = BuildSummary()

    --the viewer feed is built from the same pass, before FitToSize trims the
    --band's events. Its failure must never stop the band.
    --the viewer feed runs only while a host has gone live with a viewer code
    --(Go Live is dev-only for now); the overlay alone never sends it.
    local viewer, viewerText = nil, nil
    local viewerOk, viewerErr = pcall(function()
        if not StreamOverlay.LiveSettings().live then
            return
        end
        local raw = BuildViewerRaw(summary, q, activeTokenIds)
        viewer = StreamerKitRedact.Redact(raw)
        viewerText = FitViewerToSize(viewer)
    end)
    if not viewerOk then
        print("StreamOverlay:: viewer snapshot failed:", viewerErr)
    end

    local text = FitToSize(summary)
    local bandChanged = text ~= g_lastWritten
    local viewerChanged = viewerText ~= nil and viewerText ~= g_lastViewerWritten
    if not bandChanged and not viewerChanged and not heartbeatDue then
        return
    end
    if bandChanged or heartbeatDue then
        Write(summary)
        g_lastWritten = text
    end
    if viewer ~= nil and viewerText ~= nil and (viewerChanged or heartbeatDue) then
        WriteViewer(viewer)
        g_lastViewerWritten = viewerText
    end
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
