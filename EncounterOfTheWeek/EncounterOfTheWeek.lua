local mod = dmhub.GetModLoading()

--Game-side logic for the Encounter of the Week game mode. This codemod ships
--with the mcdm-encounteroftheweek module, so it loads only inside EotW games
--(and the source game the module is authored in). Setup never runs on its
--own: the titlescreen EotW screen ("Codex Titlescreen/EncounterOfTheWeek.lua")
--drives it by calling EncounterOfTheWeekGame.SetupOnArrival from the
--lobby:EnterGame arrival callback. That explicit handoff is deliberate -- it
--means entering the authoring game normally never triggers EotW setup. The
--only load-time behavior is passive: registering the EotW map-script builtin
--and the Director-UI filter, both inert until IsEotwGame() is true.
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md.

EncounterOfTheWeekGame = {}

--The per-game shared state document. Shape:
--  data.eotw          = true  (host-stamped at setup: this is an EotW game)
--  data.expectedUsers = { userid, ... }  (players with claimed heroes at
--                       launch; the encounter waits for all of them)
--  data.arrived       = { [userid] = serverTime }  (each member on arrival)
--  data.placedHeroes  = { [userid] = { [kind..":"..heroid] = charid } }
--                       (re-entering the game never duplicates heroes)
--  data.combatStarted = true  (host-stamped when the initiative queue first
--                       goes live; permanently lifts the start-zone
--                       confinement on every client)
--  data.proceedRequested = serverTime  (a player pressed Proceed on the
--                       victory screen; the host tick runs the teardown and
--                       clears it)
--  data.abilityBusy   = { [userid] = serverTime }  (that client has an
--                       ability cast/prompt in flight; refreshed while busy,
--                       cleared when idle. The host defers the
--                       victory/defeat award while any stamp is fresh, so
--                       the outcome screen never interrupts a prompt.)
local STATE_DOC_ID = "eotwstate"

--Hidden escape hatch: "/toggle eotw:showdirectorui" in chat restores the
--Director UI on an EotW host client (debugging, or manual recovery when the
--automated combat flow gets stuck).
setting{
    id = "eotw:showdirectorui",
    description = "Show Director UI in Encounter of the Week games",
    default = false,
    storage = "preference",
}

--Handoff to the titlescreen: set to the finished game's id just before this
--client exits at encounter conclusion. The titlescreen EotW screen (which
--re-declares this setting for read access) destroys the game / clears the
--account slot and resets it on its next refresh -- a finished game is never
--offered for resume.
setting{
    id = "eotw:concludedgame",
    default = "",
    storage = "preference",
}

--- Is the current game an Encounter of the Week game? ----------------------

--Cached once true: a game cannot stop being an EotW game mid-session.
local m_isEotwGame = false

--True in real EotW games only, on every member's client. Two signals, either
--suffices: the game occupies this account's dedicated EotW slot (set by the
--create/join flows on the titlescreen), or the host stamped the shared state
--doc at setup (covers a client whose slot has since moved on). The authoring
--game has neither, so it always presents normally.
function EncounterOfTheWeekGame.IsEotwGame()
    if m_isEotwGame then
        return true
    end

    local slotid = nil
    pcall(function() slotid = lobby.eotwGameid end)
    if slotid ~= nil and slotid == dmhub.gameid then
        m_isEotwGame = true
        return true
    end

    local marked = false
    pcall(function() marked = (mod:GetDocumentSnapshot(STATE_DOC_ID).data.eotw == true) end)
    if marked then
        m_isEotwGame = true
    end
    return m_isEotwGame
end

--Hide Director-facing UI in EotW games: the host keeps Director status
--internally (monster control, encounter spawning, the map-script host
--election all need it) but presents as a player. pcall-guarded so an engine
--running an older core codex without the hook just shows the Director UI.
pcall(function()
    GameHud.RegisterDirectorUIFilter(function()
        if not EncounterOfTheWeekGame.IsEotwGame() then
            return true
        end
        return dmhub.GetSettingValue("eotw:showdirectorui") == true
    end)
end)

local function HeroKey(heroEntry)
    return string.format("%s:%s", heroEntry.kind or "?", heroEntry.id or "?")
end

local function GetPlacedHeroes(userid)
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    local placed = doc.data.placedHeroes
    if placed ~= nil and placed[userid] ~= nil then
        return placed[userid]
    end
    return {}
end

local function RecordPlacedHeroes(userid, mine)
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    doc.data.placedHeroes = doc.data.placedHeroes or {}
    doc.data.placedHeroes[userid] = mine
    doc:CompleteChange("Encounter of the Week: heroes placed", {undoable = false})
end

--Host only, at setup: stamp the game as EotW and record which players the
--encounter must wait for before entering combat (the launch roster's
--hero-claiming userids, computed on the titlescreen).
local function RecordExpectedUsers(members)
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    doc.data.eotw = true
    if type(members) == "table" and #members > 0 then
        doc.data.expectedUsers = members
    end
    doc:CompleteChange("Encounter of the Week: expected players", {undoable = false})
    m_isEotwGame = true
end

--Every member, after their heroes are placed: I am in the game. Re-entry
--refreshes the timestamp, which just extends the pre-combat grace beat.
local function RecordArrival()
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    doc.data.arrived = doc.data.arrived or {}
    doc.data.arrived[dmhub.loginUserid] = dmhub.serverTime
    doc:CompleteChange("Encounter of the Week: player arrived", {undoable = false})
end

--True once every expected player has arrived (and the newest arrival has had
--a moment to settle, so the last client in actually sees the Draw Steel
--banner appear rather than loading into mid-roll).
function EncounterOfTheWeekGame.AllPlayersArrived()
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    local expected = doc.data.expectedUsers
    if type(expected) ~= "table" or #expected == 0 then
        return false
    end
    local arrived = doc.data.arrived
    if type(arrived) ~= "table" then
        return false
    end

    local newest = nil
    for _,userid in ipairs(expected) do
        local t = arrived[userid]
        if t == nil then
            return false
        end
        if type(t) == "number" and (newest == nil or t > newest) then
            newest = t
        end
    end

    --math.abs guards server-time rebasing, the map-script presence rule.
    if newest ~= nil and math.abs(dmhub.serverTime - newest) < 3 then
        return false
    end
    return true
end

--- Start zone ---------------------------------------------------------

--Every tile of every "Start" markup zone on the current map, as placeable
--core.Loc values. Zone records store their rasterized tiles in .locs, so no
--per-tile aura queries are needed. Matches by keyword id, with the record's
--keywordName as a fallback (the same heal-by-name rule MapMarkup uses).
local function StartZoneLocs()
    local map = game.currentMap
    if map == nil then
        return {}
    end

    local startIds = {}
    for k,v in unhidden_pairs(dmhub.GetTable("environmentalKeywords") or {}) do
        if v.name ~= nil and string.lower(v.name) == "start" then
            startIds[k] = true
        end
    end

    local result = {}
    for _,floor in ipairs(map.floors or {}) do
        local zones = nil
        local floorIndex = nil
        pcall(function()
            zones = floor.markupZones
            floorIndex = floor.floorIndex
        end)
        if zones ~= nil and floorIndex ~= nil and floorIndex >= 0 then
            for _,record in pairs(zones) do
                --zone records have no category; surfaces and holes do.
                if type(record) == "table" and record.category == nil
                   and (startIds[record.keyword]
                        or (record.keywordName ~= nil and string.lower(record.keywordName) == "start")) then
                    for _,l in ipairs(record.locs or {}) do
                        result[#result+1] = core.Loc{ x = math.floor(l.x), y = math.floor(l.y), floorIndex = floorIndex }
                    end
                end
            end
        end
    end
    return result
end

--The tile heroes fan out from: the Start-zone tile nearest the zone's center
--(paste placement is vacancy-aware, so one anchor serves the whole party).
--nil when the map has no Start zone; callers fall back to the camera.
local function StartZoneAnchor()
    local locs = StartZoneLocs()
    if #locs == 0 then
        return nil
    end
    local sx, sy = 0, 0
    for _,l in ipairs(locs) do
        sx = sx + l.x
        sy = sy + l.y
    end
    local cx, cy = sx / #locs, sy / #locs
    local best = nil
    local bestDist = nil
    for _,l in ipairs(locs) do
        local d = (l.x - cx) * (l.x - cx) + (l.y - cy) * (l.y - cy)
        if bestDist == nil or d < bestDist then
            best = l
            bestDist = d
        end
    end
    return best
end

--- lobby requests -----------------------------------------------------

--Must match the titlescreen's lobby connection (Codex Titlescreen/
--EncounterOfTheWeek.lua): the EotW lobby id, on the staging server while
--EotW is dev-gated.
local LOBBY_ID = "eotw"
local LOBBY_STAGING = true

--Send one request to the EotW lobby over a transient connection of our own
--(the titlescreen's connection closed when its screen was destroyed during
--the game switch). Requests fail immediately while the connection is still
--opening, so poll for auth first (give up after ~30s). onDone(ok, result)
--is optional; the connection is dropped either way.
local function SendLobbyRequest(action, args, onDone)
    local lobbies = rawget(_G, "lobbies")
    if lobbies == nil then
        printf("EotW: engine has no lobbies API; cannot send %s", tostring(action))
        return
    end

    local conn = lobbies:Connect(LOBBY_ID, { staging = LOBBY_STAGING })
    if conn == nil then
        return
    end

    dmhub.Coroutine(function()
        for _ = 1, 300 do
            if mod.unloaded then
                return
            end
            if conn.connected then
                break
            end
            coroutine.yield(0.1)
        end

        if not conn.connected then
            printf("EotW: lobby connection never became ready; %s not sent", tostring(action))
            conn:Disconnect()
            return
        end

        conn:Request{
            action = action,
            args = args,
            success = function(result)
                conn:Disconnect()
                if onDone ~= nil then
                    onDone(true, result)
                end
            end,
            error = function(err)
                conn:Disconnect()
                if onDone ~= nil then
                    onDone(false, err)
                end
            end,
        }
    end)
end

--- pre-combat start-zone confinement ----------------------------------

--From arrival until the initiative queue goes live (the waiting-for-players
--stretch plus the Draw Steel roll), heroes may reposition within the Start
--zone but not leave it. Each client installs the engine's Movement
--Restriction Mode locally and outlines the zone so players can see where
--they may move. Once combat has started (host-stamped combatStarted in the
--state doc) the confinement never returns -- a resume mid- or post-combat is
--not confined.

--The Start-zone outline drawn while confinement is active.
local START_ZONE_COLOR = "#79d2a0"

--Seconds between the victory screen dismissing and this client leaving for
--the titlescreen: covers the screen's 0.7s fade plus the 1-3s GameDetails
--write coalescing, so the host's end-of-combat writes flush before the
--socket closes.
local EXIT_DELAY = 4

local m_restrictionInstalled = false
local m_zoneMarker = nil
local m_outcomeSeen = false
local m_exitScheduled = false

local function ClearStartZoneConfinement()
    if m_restrictionInstalled then
        m_restrictionInstalled = false
        pcall(function() dmhub.ClearMovementRestriction() end)
    end
    if m_zoneMarker ~= nil then
        pcall(function() m_zoneMarker:Destroy() end)
        m_zoneMarker = nil
    end
    GameHud.SetTooltipsSuppressed("eotw", false)
end

local function UpdateStartZoneConfinement()
    local desired = false
    if EncounterOfTheWeekGame.IsEotwGame() then
        local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
        if doc.data.combatStarted ~= true then
            local queue = dmhub.initiativeQueue
            if queue == nil or queue.hidden then
                desired = true
            end
        end
    end

    --Tooltips -- the token-drag movement tooltip and its cross-section diagram
    --above all -- are noise while players shuffle around the start zone, and
    --the phase has nothing a tooltip would explain. Silence them for exactly as
    --long as the confinement lasts. Done before the Start-zone lookup below so
    --a map with no Start zone (no confinement possible) still gets the quiet.
    GameHud.SetTooltipsSuppressed("eotw", desired)

    if not desired then
        ClearStartZoneConfinement()
        return
    end

    if m_restrictionInstalled then
        return
    end

    local locs = StartZoneLocs()
    if #locs == 0 then
        --no Start zone on this map; nothing to confine to.
        return
    end

    m_restrictionInstalled = true
    --pcall: an engine build without the Movement Restriction API degrades to
    --no confinement (the zone outline below still draws).
    pcall(function() dmhub.SetMovementRestriction{ locs = locs } end)
    m_zoneMarker = dmhub.MarkLocs{
        locs = locs,
        color = START_ZONE_COLOR,
        style = "dashed",
    }
end

--Watch the encounter conclude: once this client has seen the victory/defeat
--screen (an awarded outcome on the live queue) and the queue then hides
--(someone pressed Proceed), leave for the titlescreen. Clients that never
--saw an awarded outcome (mid-join, or a combat ended through the Director
--escape hatch) never auto-exit.
local function UpdateEncounterConclusion()
    if m_exitScheduled or not EncounterOfTheWeekGame.IsEotwGame() then
        return
    end

    local queue = dmhub.initiativeQueue
    if queue ~= nil and not queue.hidden then
        if not m_outcomeSeen then
            local outcome = nil
            pcall(function()
                local live = queue:try_get("liveEncounter")
                if type(live) == "table" then
                    outcome = live:GetAwardedOutcome()
                end
            end)
            if outcome ~= nil then
                m_outcomeSeen = true
            end
        end
        return
    end

    if m_outcomeSeen then
        m_exitScheduled = true
        printf("EotW: encounter concluded; returning to the titlescreen")

        --hand the finished game to the titlescreen: it destroys the game /
        --clears the account slot on its next refresh, so a decided
        --encounter is never offered for resume.
        pcall(function() dmhub.SetSettingValue("eotw:concludedgame", dmhub.gameid) end)

        --and drop out of the lobby roster now: the HOST's leave removes the
        --game's record (and its chat) for the whole lobby, and members'
        --leaves stop their returning screens' heartbeats from keeping a
        --stale record alive. Best-effort -- the titlescreen cleanup sends
        --leave-game again if this one loses the race with LeaveGame.
        SendLobbyRequest("leave-game", { gameid = dmhub.gameid }, function(ok, result)
            if not ok then
                printf("EotW: conclusion leave-game not accepted: %s", tostring(result))
            end
        end)

        --deferred: LeaveGame synchronously unloads this codemod, so let the
        --frame (and the victory screen's fade) finish first.
        dmhub.Schedule(EXIT_DELAY, function()
            if mod.unloaded then
                return
            end
            dmhub.LeaveGame()
        end)
    end
end

--- ability-activity mirror --------------------------------------------

--The victory/defeat award must not interrupt an ability mid-prompt (a roll
--dialog awaiting Accept, forced-movement placement, a spend-recovery modal,
--a trigger card...). Those prompts are LOCAL to the prompting client, so
--each client mirrors "I have ability activity in flight" into the state doc
--and the host defers the award while any mirror stamp is fresh.

--How often a busy client refreshes its stamp, and how old a stamp may be
--before the host ignores it (a crashed client must not hold the award
--hostage; a live one clears its stamp the second it goes idle anyway).
local BUSY_REFRESH_INTERVAL = 5
local BUSY_STALE_SECONDS = 15

local m_busyStampTime = nil

--True while THIS client has any ability cast, targeting session, roll
--dialog, modal prompt, or unanswered trigger prompt in flight. Composed
--from the exact predicates the invoke pipeline (AbilityInvokeAbility.lua),
--the Monster AI's WaitForAbilityIdle, and the death gate
--(AbilityRemoveCreature.lua) already trust. Every probe is pcall-guarded.
local function AbilityActivityInFlight()
    --any live cast coroutine (covers post-roll prompts, forced-movement
    --placement, spend-recovery, invoked sub-abilities). On the host this
    --also covers Monster AI casts, which run there.
    local activeCasts = 0
    pcall(function() activeCasts = ActivatedAbility.CountActiveCasts() end)
    if activeCasts > 0 then
        return true
    end

    --the action bar is targeting / awaiting Confirm. The new bar returns
    --the ability OBJECT, the legacy bar a boolean -- test truthy.
    local casting = nil
    pcall(function()
        if gamehud ~= nil and gamehud.actionBarPanel ~= nil and gamehud.actionBarPanel.valid then
            casting = gamehud.actionBarPanel.data.IsCastingSpell()
        end
    end)
    if casting ~= nil and casting ~= false then
        return true
    end

    --any of the three roll surfaces (legacy singleton, embedded ability
    --dialog, standalone roll host).
    local rolling = false
    pcall(function() rolling = CharacterPanel.AnyRollDialogShown() end)
    if rolling then
        return true
    end

    --a modal prompt is up (recovery selection, confer condition, fall...).
    local modal = nil
    pcall(function() modal = gui.GetModal() end)
    if modal ~= nil then
        return true
    end

    --an unanswered trigger / invocation prompt card on a creature this
    --client controls. Hostile prompts never age out, so they must not block
    --forever (same carve-out as the death gate).
    for _,tok in ipairs(dmhub.allTokens) do
        if tok.valid and tok.canControl and tok.properties ~= nil then
            local triggers = nil
            pcall(function() triggers = tok.properties:GetAvailableTriggers(true) end)
            if triggers ~= nil then
                for _,t in pairs(triggers) do
                    if not t.hostile then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function WriteBusyStamp()
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    doc.data.abilityBusy = doc.data.abilityBusy or {}
    doc.data.abilityBusy[dmhub.loginUserid] = dmhub.serverTime
    doc:CompleteChange("Encounter of the Week: ability activity", {undoable = false})
    m_busyStampTime = dmhub.serverTime
end

local function ClearBusyStamp()
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    if doc.data.abilityBusy ~= nil and doc.data.abilityBusy[dmhub.loginUserid] ~= nil then
        doc:BeginChange()
        doc.data.abilityBusy[dmhub.loginUserid] = nil
        doc:CompleteChange("Encounter of the Week: ability activity ended", {undoable = false})
    end
    m_busyStampTime = nil
end

--Per-client, from the 1s driver: mirror local ability activity into the
--state doc while combat is live. Writes only on transitions plus a
--BUSY_REFRESH_INTERVAL keep-alive, so idle ticks cost nothing.
local function UpdateBusyMirror()
    if not EncounterOfTheWeekGame.IsEotwGame() then
        return
    end
    local queue = dmhub.initiativeQueue
    if queue == nil or queue.hidden then
        if m_busyStampTime ~= nil then
            ClearBusyStamp()
        end
        return
    end

    if AbilityActivityInFlight() then
        if m_busyStampTime == nil or math.abs(dmhub.serverTime - m_busyStampTime) >= BUSY_REFRESH_INTERVAL then
            WriteBusyStamp()
        end
    elseif m_busyStampTime ~= nil then
        ClearBusyStamp()
    end
end

--Host-side award gate: true while this client is busy (checked live, so AI
--casts on the host are always fresh) or any other client's mirror stamp is
--recent.
local function AnyClientAbilityBusy()
    if AbilityActivityInFlight() then
        return true
    end
    local stamps = mod:GetDocumentSnapshot(STATE_DOC_ID).data.abilityBusy
    if type(stamps) == "table" then
        local myUserid = dmhub.loginUserid
        for userid,t in pairs(stamps) do
            if userid ~= myUserid and type(t) == "number" and math.abs(dmhub.serverTime - t) < BUSY_STALE_SECONDS then
                return true
            end
        end
    end
    return false
end

--Player-host mode is NOT switched on from here. EotW games are created
--directorless (GameInfo.directorless, via lobby:CreateGame{directorless=true}),
--so the engine already has the host in player-host mode when the game loads --
--player vision, player UI, strict rules -- on every entry path, with no
--in-session switch and so no reload. All this driver does is keep the
--"/toggle eotw:showdirectorui" debug hatch in sync, which deliberately DOES
--refresh: it is a debugging action.
--
--Engine builds without the flag ignore it at creation and report
--playerHostModeSuppressed as nil; there the Director-UI filter above remains
--the (weaker) fallback presentation.
local function UpdateDirectorUIHatch()
    if dmhub.playerHostModeSuppressed == nil then
        return
    end
    if not EncounterOfTheWeekGame.IsEotwGame() then
        return
    end
    local suppress = dmhub.GetSettingValue("eotw:showdirectorui") == true
    if dmhub.playerHostModeSuppressed ~= suppress then
        printf("EncounterOfTheWeek: Director UI hatch %s", tostring(suppress))
        dmhub.playerHostModeSuppressed = suppress
    end
end

--The per-client driver: a cheap 1s poll self-heals across Lua reloads, the
--late IsEotwGame flip (the host stamps the doc during setup), and map loads.
dmhub.Coroutine(function()
    while true do
        coroutine.yield(1)
        if mod.unloaded then
            ClearStartZoneConfinement()
            return
        end
        pcall(UpdateDirectorUIHatch)
        pcall(UpdateStartZoneConfinement)
        pcall(UpdateBusyMirror)
        pcall(UpdateEncounterConclusion)
    end
end)

--Open the victory screen's Proceed button to every player in an EotW game.
--The HOST pressing runs the normal Director teardown (battle log, role
--history, analytics are Director-gated); a PLAYER pressing relays the
--request through the state doc for the host tick to execute. pcall: a core
--codex without the hook keeps the Director-only button.
pcall(function()
    DSVictoryScreen.RegisterProceedOverride{
        canProceed = function()
            return EncounterOfTheWeekGame.IsEotwGame()
        end,
        proceed = function(defaultProceed)
            --the HOST (a player host: real hosting status, presented as a
            --player) falls through to the default teardown -- battle log,
            --role history and analytics must run on the host machine.
            if not EncounterOfTheWeekGame.IsEotwGame() or IsDMOrPlayerHost() then
                return false
            end
            local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
            doc:BeginChange()
            doc.data.proceedRequested = dmhub.serverTime
            doc:CompleteChange("Encounter of the Week: proceed requested", {undoable = false})
            return true
        end,
    }
end)

--- the map's journal encounter ----------------------------------------

--Find the [[encounter]] island on this map's journal. Encounters harvested
--from info bubbles are on the current map by construction; document-sourced
--ones are kept only when the document lives in the map's own journal folder
--(parentFolder chain rooted at the map id), so a rules doc that happens to
--embed an encounter can never be picked up.
local function FindMapEncounter()
    --hostAccess: EotW games are directorless, so the host's dmhub.isDM is false
    --and the map's journal folder is not in their viewing roots -- without this
    --the encounter is invisible to the very client that has to spawn it.
    local entries = Encounter.GetEncountersOnCurrentMap(true)
    local mapid = game.currentMapId
    local docsTable = dmhub.GetTable("documents") or {}
    for _,entry in ipairs(entries) do
        if entry.bubbleid ~= nil then
            return entry
        end
        if entry.docid ~= nil then
            local doc = docsTable[entry.docid]
            if doc ~= nil and CustomDocument.IsDocInAccessibleRoot(doc, { [mapid] = true }) then
                return entry
            end
        end
    end
    return nil
end

--- monster spawning ---------------------------------------------------

--Spawn the start-of-combat monsters from the map's [[encounter]] island,
--scaled to numHeroes, at their banked positions. Mirrors the island's own
--"Place on Map" flow but uses Encounter.SpawnGroupForReal (the combat-grade
--walk: stable slot order, fallback grid instead of silent skips). Wave
--groups are left for reinforcements. Records the spawned charids on the
--island (so its Run Encounter / Save and Remove buttons work) and readies
--the encounter for the combat-setup dialog.
--Returns true if monsters are (now or already) on the map, else false+error.
function EncounterOfTheWeekGame.SpawnEncounterMonsters(numHeroes)
    local entry = FindMapEncounter()
    if entry == nil then
        return false, "This map's journal has no encounter to spawn."
    end

    local richEncounter = entry.richEncounter

    --already spawned (by us or another client)? GetTokenById is nil for
    --deleted AND despawned characters, so stale ids never trip this.
    for _,charid in ipairs(richEncounter:try_get("spawns", {})) do
        if dmhub.GetTokenById(charid) ~= nil then
            return true
        end
    end

    Encounter.SetReadiedEncounter(entry.encounter)

    local spawns = {}
    --every spawned token tagged with its (group, slot), so monsters saved riding
    --another monster get seated once the whole encounter is down.
    local mountEntries = {}
    for groupIndex,group in ipairs(entry.encounter.groups) do
        if group.wave == nil and Encounter.AdjustedGroupCount(group, numHeroes) > 0 then
            local anchor = (group.spawnlocs or {})[1] or dmhub.cameraPosition
            local _, charids, entries = Encounter.SpawnGroupForReal(group, numHeroes, anchor)
            for _,charid in ipairs(charids) do
                spawns[#spawns+1] = charid
            end
            for _,e in ipairs(entries) do
                mountEntries[#mountEntries+1] = { group = groupIndex, slot = e.slot, token = e.token }
            end
        end
    end

    entry.encounter:RestoreMounts(mountEntries)

    richEncounter.spawns = spawns
    richEncounter:UploadDocument()
    game.UpdateCharacterTokens()

    return true
end

--- hero placement -----------------------------------------------------

--Force a placed hero to exactly level 1.
--
--Heroes arrive from wherever their owner built them, and the weekly
--encounter is tuned for a level-1 party, so two directions have to be
--corrected on the game's COPY of the hero:
--  * ABOVE level 1: a lobby or campaign hero can be any level. Note that
--    CharacterLevel() is max(sum of class levels, levelOverride), so the
--    class entries have to come down too -- levelOverride alone cannot
--    lower a level-6 hero.
--  * BELOW level 1: the Draw Steel "slow start" track sits at level 1 with
--    extraLevelInfo.encounter = 1..4 -- the "First Encounter".."Fourth
--    Encounter" rungs, which grant only part of a level-1 hero's features.
--    Clearing .encounter promotes them to a full level 1.
--The owner's original hero (in their lobby game or campaign) is never
--touched: this runs on the pasted duplicate that lives in the EotW game.
--Mirrors the character builder's level dropdown (Draw Steel Character
--Builder/CharacterPanel.lua).
local function NormalizeHeroLevel(token)
    local props = token.properties
    if props == nil then
        return
    end

    --decide first, so a hero that is already level 1 (every well-authored
    --pregen) costs nothing and leaves no upload behind.
    local extra = props:ExtraLevelInfo()
    local clearEncounter = extra.encounter ~= nil
    local setOverride = props:try_get("levelOverride", 1) ~= 1

    local classes = props:try_get("classes", {})
    local lowerClasses = false
    for _,entry in ipairs(classes) do
        if entry.level ~= 1 then
            lowerClasses = true
        end
    end

    if #classes > 1 then
        --Draw Steel has no multiclassing, so this should not happen; the
        --level would sum to #classes and no per-entry clamp can fix it.
        --Leave the classes alone (deleting one is destructive) and say so.
        printf("EotW: hero %s has %d classes; level cannot be forced to 1", tostring(token.name), #classes)
    end

    if not (clearEncounter or setOverride or lowerClasses) then
        return
    end

    token:ModifyProperties{
        --setup, not a player action: an undo must not put the hero back to
        --the level the encounter is not balanced for.
        description = "Encounter of the Week: level 1",
        undoable = false,
        execute = function()
            if clearEncounter then
                --the field existed, so this is the stored table and not
                --try_get's throwaway default; write it back to persist the
                --clear.
                local info = props:ExtraLevelInfo()
                info.encounter = nil
                props.extraLevelInfo = info
            end

            if setOverride then
                props.levelOverride = 1
            end

            for _,entry in ipairs(props:try_get("classes", {})) do
                entry.level = 1
            end
        end,
    }
end

--Claim a freshly pasted hero for the local player: owner, default (friendly)
--party. Cross-game pastes by the DM arrive ownerless and partyless (which
--reads as a hostile NPC), and module pregens carry whatever the author had,
--so both get the same fix-up. Retries briefly: pasted characters can take a
--tick to become resolvable.
local function ClaimPastedHero(charid, description)
    dmhub.Coroutine(function()
        for i = 1, 50 do
            if mod.unloaded then
                return
            end
            local token = dmhub.GetCharacterById(charid)
            if token ~= nil then
                --partyId FIRST: its setter force-writes ownerId = "PARTY" as
                --a side effect, so setting it after ownerId would clobber the
                --player's ownership. The ownerId setter preserves partyid.
                token.partyId = GetDefaultPartyID()
                token.ownerId = dmhub.loginUserid
                token:UploadToken(description or "Encounter of the Week hero")
                --the encounter is balanced for a level-1 party; this is a
                --separate properties patch, so it runs after the token upload.
                NormalizeHeroLevel(token)
                return
            end
            coroutine.yield(0.1)
        end
        printf("EotW: pasted hero %s never resolved; ownership not set", tostring(charid))
    end)
end

--Block (yielding; callers run inside a coroutine) until every pasted charid
--resolves in the local game mirror, then materialize their live token
--objects. A paste round-trips through the game server before it appears in
--gameDetails, so immediately after a paste call the new characters are
--INVISIBLE to the next paste's vacancy scan (charactersByLoc only holds live
--token objects) -- pasting again without this wait stacks heroes on the
--anchor tile. UpdateCharacterTokens alone is NOT enough: it reads the same
--mirror, so before the server echo it has nothing to materialize.
local function WaitForPastedCharacters(charids)
    if charids == nil or #charids == 0 then
        return
    end
    for _ = 1, 50 do
        if mod.unloaded then
            return
        end
        local allResolved = true
        for _,charid in ipairs(charids) do
            if dmhub.GetCharacterById(charid) == nil then
                allResolved = false
                break
            end
        end
        if allResolved then
            break
        end
        coroutine.yield(0.1)
    end
    --create the live token objects at their tiles (registers them in the
    --engine's occupancy map, which the next paste's vacancy scan reads).
    game.UpdateCharacterTokens()
end

--Place the local player's claimed heroes into the Start zone.
--  heroes:       full claim list, {kind, id, name} each, in claim order.
--  clipboardIds: ids of the "lobby" heroes copied to the token clipboard at
--                the titlescreen, in copy order -- the paste result aligns
--                index-for-index with this list.
--Heroes recorded as placed in the state doc are skipped (re-entry safe).
local function PlaceMyHeroes(heroes, clipboardIds)
    local userid = dmhub.loginUserid
    local placed = GetPlacedHeroes(userid)
    local mine = {}
    for k,v in pairs(placed) do
        mine[k] = v
    end

    local anchor = StartZoneAnchor()
    if anchor == nil then
        printf("EotW: no Start zone on this map; placing heroes at the camera")
        anchor = dmhub.cameraPosition
    end

    local changed = false

    --lobby heroes travel via the token clipboard, loaded before EnterGame.
    clipboardIds = clipboardIds or {}
    if #clipboardIds > 0 then
        local anyNew = false
        for _,heroid in ipairs(clipboardIds) do
            if mine["lobby:" .. heroid] == nil then
                anyNew = true
            end
        end

        if anyNew then
            local pastedIds = {}
            local multiPaste = nil
            pcall(function() multiPaste = dmhub.PasteTokensFromClipboard end)
            if multiPaste ~= nil then
                pastedIds = dmhub.PasteTokensFromClipboard(anchor)
            else
                --engine without the batch API: the clipboard holds one hero.
                local charid = dmhub.PasteTokenFromClipboard(anchor)
                if charid ~= nil then
                    pastedIds = { charid }
                end
            end

            --wait for the paste to land in the local mirror BEFORE touching
            --the ids: claims and duplicate-deletes need resolvable
            --characters, and the pregen pastes below need these heroes
            --visible to their vacancy scans.
            WaitForPastedCharacters(pastedIds)

            for i,charid in ipairs(pastedIds) do
                local heroid = clipboardIds[i]
                local key = heroid ~= nil and ("lobby:" .. heroid) or nil
                if key == nil then
                    --more pastes than copied ids should not happen; keep the
                    --token rather than guessing, but do not record it.
                    printf("EotW: pasted hero %d has no matching claim entry", i)
                    ClaimPastedHero(charid)
                elseif mine[key] ~= nil then
                    --this hero was placed on an earlier entry; the batch paste
                    --recreated it, so delete the duplicate.
                    game.DeleteCharacters({charid})
                else
                    ClaimPastedHero(charid)
                    mine[key] = charid
                    changed = true
                end
            end
        end
    end

    --pregens are module characters, already present (unplaced) in the game:
    --duplicate each onto the map with a same-game copy/paste. This must run
    --AFTER the batch paste above -- copying wipes the clipboard.
    for _,heroEntry in ipairs(heroes or {}) do
        if heroEntry.kind == "pregen" and mine[HeroKey(heroEntry)] == nil then
            local sourceToken = dmhub.GetCharacterById(heroEntry.id)
            if sourceToken == nil then
                printf("EotW: pregen %s (%s) not found in this game", tostring(heroEntry.name), tostring(heroEntry.id))
            else
                dmhub.CopyTokenToClipboard(sourceToken)
                local charid = dmhub.PasteTokenFromClipboard(anchor)
                if charid ~= nil then
                    --same rule as the batch paste above: wait for this paste
                    --to land in the mirror so the NEXT paste's vacancy scan
                    --sees it instead of stacking on the anchor tile.
                    WaitForPastedCharacters({charid})
                    ClaimPastedHero(charid)
                    mine[HeroKey(heroEntry)] = charid
                    changed = true
                end
            end
        end
    end

    if changed then
        game.UpdateCharacterTokens()
        RecordPlacedHeroes(userid, mine)
    end
end

--Dev helper: forget every recorded hero placement so the next
--SetupOnArrival places heroes again. Does not touch tokens on the map.
function EncounterOfTheWeekGame.ResetPlacedHeroes()
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    doc.data.placedHeroes = nil
    doc:CompleteChange("Encounter of the Week: reset placed heroes", {undoable = false})
end

--Dev helper: a copy of the shared state doc's data, for inspection from the
--debug console / MCP (the doc is mod-scoped, so outside code cannot reach it).
function EncounterOfTheWeekGame.DebugGetState()
    return DeepCopy(mod:GetDocumentSnapshot(STATE_DOC_ID).data)
end

--Dev helper: clear the EotW game marker and arrival tracking (e.g. after
--accidentally running SetupOnArrival in the authoring game, which would
--otherwise hide its Director UI forever).
function EncounterOfTheWeekGame.ClearEotwMarker()
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    doc.data.eotw = nil
    doc.data.expectedUsers = nil
    doc.data.arrived = nil
    doc:CompleteChange("Encounter of the Week: clear game marker", {undoable = false})
    m_isEotwGame = false
end

--- the Encounter of the Week map script ---------------------------------

--The weekly encounter's automation runs as a Map Script (Draw Steel Core
--Rules/MapScript.lua) attached to the Encounter map by the host at setup.
--The script itself is a thin shim: MapScript compiles its code string in a
--bare environment, so all real logic lives here on EncounterOfTheWeekGame
--and the script just forwards its host tick. What the map-script layer
--buys us: a single elected writer (the host is the game's only Director,
--so election always picks a live host client, surviving host reconnects),
--plus per-map shared state and run-once bookkeeping.
local MAP_SCRIPT_ID = "builtin:eotw-encounter"

local function RegisterMapScriptBuiltin()
    local ms = rawget(_G, "MapScript")
    if ms == nil then
        --core codex without the Map Script system loaded; AttachMapScript
        --will report it when setup actually needs it.
        return
    end
    ms.RegisterBuiltin{
        id = MAP_SCRIPT_ID,
        name = "Encounter of the Week",
        description = "Runs the weekly encounter: enters combat with the normal Draw Steel roll once every player has arrived, then keeps the Monster AI playing the monsters. Attached to the map automatically by the Encounter of the Week game mode.",
        code = [==[
return {
    name = "Encounter of the Week",
    description = "Enters combat when all players have arrived and keeps the Monster AI running. Managed by the Encounter of the Week game mode.",

    hostThink = function(ctx)
        local eotw = rawget(_G, "EncounterOfTheWeekGame")
        if eotw ~= nil and eotw.MapScriptHostThink ~= nil then
            eotw.MapScriptHostThink(ctx)
        end
    end,
    hostThinkInterval = 2,
}
]==],
    }
end
RegisterMapScriptBuiltin()

--Attach the EotW map script to the current map if it is not already there
--(host only -- the attachment list is a Director-writable map setting; it
--replicates to every client and persists with the game).
local function AttachMapScript()
    local ms = rawget(_G, "MapScript")
    if ms == nil then
        printf("EotW: the Map Script system is not loaded; combat automation will not run")
        return
    end

    local records = ms.GetAttachedRecords()
    for _,rec in ipairs(records) do
        if rec.scriptid == MAP_SCRIPT_ID then
            return
        end
    end

    records[#records+1] = ms.CreateRecordFromLibrary(MAP_SCRIPT_ID)
    ms.SetAttachedRecords(records)
    printf("EotW: attached the Encounter of the Week map script to the map")
end

--- combat entry ---------------------------------------------------------

--Everything on the map sorted into sides for the initiative roll: heroes
--(IsHero) vs monsters. Returns nil while either side is empty -- the caller
--retries on a later tick rather than burning its run-once.
local function GatherCombatSides()
    local playerTokens = {}
    local monsterTokens = {}
    for _,token in ipairs(dmhub.allTokens) do
        if token.valid and token.properties ~= nil then
            local isHero = false
            pcall(function() isHero = token.properties:IsHero() end)
            if isHero then
                playerTokens[#playerTokens+1] = token
            elseif not token.playerControlled then
                local isMonster = false
                pcall(function() isMonster = token.properties:IsMonster() end)
                if isMonster then
                    monsterTokens[#monsterTokens+1] = token
                end
            end
        end
    end

    if #playerTokens == 0 or #monsterTokens == 0 then
        return nil
    end
    return { playerTokens = playerTokens, monsterTokens = monsterTokens }
end

--Enter combat exactly the way a Director would: the Draw Steel banner with
--the normal claim-the-die roll, every hero on the players' side, every
--monster on the monsters' side, and the map's authored encounter (when it
--is discoverable) driving victory conditions and rewards.
local function StartEncounterCombat(sides)
    local encounterEntry = FindMapEncounter()
    local encounter = nil
    if encounterEntry ~= nil then
        encounter = encounterEntry.encounter
    end

    local ok, started, err = pcall(function()
        return Encounter.StartCombatWithTokens{
            playerTokens = sides.playerTokens,
            monsterTokens = sides.monsterTokens,
            encounter = encounter,
        }
    end)
    if not ok then
        printf("EotW: combat start unavailable: %s", tostring(started))
    elseif started ~= true then
        printf("EotW: combat did not start: %s", tostring(err))
    else
        printf("EotW: Draw Steel! %d heroes vs %d monsters", #sides.playerTokens, #sides.monsterTokens)
    end
end

--pcall-guarded AI control: an EotW game always bundles the Monster AI
--codemod, but never let a version mismatch break the host tick.
local function EnsureAIRunning()
    pcall(function()
        if MonsterAI.active ~= true then
            printf("EotW: starting the Monster AI")
            MonsterAI.StartAI()
        end
    end)
end

local function EnsureAIStopped()
    pcall(function()
        if MonsterAI.active == true or MonsterAI.IsAIRunning() then
            printf("EotW: stopping the Monster AI")
            MonsterAI.StopAI()
        end
    end)
end

--Host only: permanently record that combat has begun. Read by every client's
--confinement driver -- once stamped, the start-zone confinement never
--returns, so a resume mid- or post-combat is unrestricted.
local function RecordCombatStarted()
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    if doc.data.combatStarted == true then
        return
    end
    doc:BeginChange()
    doc.data.combatStarted = true
    doc:CompleteChange("Encounter of the Week: combat started", {undoable = false})
end

--Consecutive host ticks the met outcome condition has been observed with
--every client ability-idle; the award waits for AWARD_HOLD_TICKS of them so
--the fight visibly settles (and any just-started prompt's busy stamp has
--time to replicate) before the screen takes over.
local m_awardHoldTicks = 0
local AWARD_HOLD_TICKS = 2

--Host only, every tick while combat is live: award victory/defeat once the
--encounter's conditions are met (the existing evaluators the Director's
--objective strip uses) AND no client has an ability prompting -- the
--victory screen must never interrupt a roll dialog or prompt mid-ability.
--While an outcome is on screen, execute a player's relayed Proceed.
--Everything is pcall-guarded: a rules hiccup must never kill the host tick.
local function CheckEncounterOutcome(queue)
    local live = nil
    pcall(function()
        local l = queue:try_get("liveEncounter")
        if type(l) == "table" then
            live = l
        end
    end)
    if live == nil then
        return
    end

    local outcome = nil
    pcall(function() outcome = live:GetAwardedOutcome() end)
    if outcome ~= nil then
        --the victory/defeat screen is up everywhere. A player pressing
        --Proceed stamps proceedRequested (see the proceed override); run the
        --full Director teardown on their behalf.
        local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
        if doc.data.proceedRequested ~= nil then
            printf("EotW: a player pressed Proceed; ending the encounter")
            pcall(function() DSVictoryScreen.ProceedEndCombat() end)
            doc:BeginChange()
            doc.data.proceedRequested = nil
            doc:CompleteChange("Encounter of the Week: proceed handled", {undoable = false})
        end
        return
    end

    local victory = false
    pcall(function() victory = live:CheckVictory() == true end)

    local defeat = false
    if not victory then
        --defeat = a script-declared defeat condition, or every hero down
        --(CountLiveCombatants counts hitpoints > 0, so dying heroes count as
        --down -- an all-dying party is a defeat in a one-shot).
        pcall(function()
            if live:CheckDefeat() == true then
                defeat = true
            else
                local heroes, _ = live:CountLiveCombatants()
                if heroes <= 0 then
                    defeat = true
                end
            end
        end)
    end

    if not victory and not defeat then
        m_awardHoldTicks = 0
        return
    end

    --the condition is met: wait until no client has an ability prompting
    --(local check is live; remote clients via their mirror stamps), then
    --hold for AWARD_HOLD_TICKS consecutive idle ticks before awarding.
    local busy = false
    pcall(function() busy = AnyClientAbilityBusy() end)
    if busy then
        m_awardHoldTicks = 0
        return
    end

    m_awardHoldTicks = m_awardHoldTicks + 1
    if m_awardHoldTicks < AWARD_HOLD_TICKS then
        return
    end
    m_awardHoldTicks = 0

    if victory then
        printf("EotW: victory condition met; showing the victory screen")
        live.victoryAwarded = true
        dmhub:UploadInitiativeQueue()
    else
        printf("EotW: the heroes are defeated; showing the defeat screen")
        live.defeatAwarded = true
        dmhub:UploadInitiativeQueue()
    end
end

--EotW games strictly enforce all game rules: every "Strict..." Rules
--Enforcement option, plus the engine's "Strictly Enforce Movement Rules".
--All of these gate on (not dmhub.isDM) -- which, under player-host mode,
--reads false on the HOST too, so the rules bind every human in the game.
--The Monster AI is unaffected: its capability paths read IsDMOrPlayerHost.
--Game-scoped settings are only editable from the dmonly Game settings tab,
--so nobody in a player-host game can flip them off; the host tick
--re-asserts them regardless.
local g_strictRuleSettings = {
    "strictmovementrules", --Strictly Enforce Movement Rules (engine)
    "strict:movement",     --Strictly Enforce Forced Movement Rules
    "strict:targeting",    --Strictly Enforce Targeting Rules
    "strict:resources",    --Strictly Enforce Action Economy and Resource Costs
    "strict:inventory",    --Strict Inventory Management
    "strict:rolls",        --Strictly Enforce Rolls
}

--Force every strict-rules setting on, writing only the ones not already
--true (these are game-scoped settings, so each write replicates).
local function EnforceStrictRules()
    for _,id in ipairs(g_strictRuleSettings) do
        if dmhub.GetSettingValue(id) ~= true then
            dmhub.SetSettingValue(id, true)
        end
    end
end

--The map script's host tick: runs only on the elected host client (the game
--host -- the game's one Director). Drives the encounter state machine, with
--the current stage mirrored into the script's shared state:
--  (nil)      -> waiting for every expected player to arrive, then Draw Steel
--  "combat"   -> combat is live; watch for victory/defeat and keep the
--                Monster AI playing the monsters
--  "complete" -> combat ended; the AI is stopped and the script goes idle
--                (clients that saw the outcome exit to the titlescreen on
--                their own -- see UpdateEncounterConclusion)
function EncounterOfTheWeekGame.MapScriptHostThink(ctx)
    if not EncounterOfTheWeekGame.IsEotwGame() then
        return
    end

    --keep the strict-rules settings forced on for the life of the game
    --(no-op writes are skipped, so this is free when nothing changed).
    EnforceStrictRules()

    local queue = dmhub.initiativeQueue
    local queueLive = queue ~= nil and not queue.hidden
    local shared = ctx:GetShared()

    if queueLive then
        if shared.stage ~= "combat" then
            ctx:ModifyShared(function(s) s.stage = "combat" end)
        end
        --stamped independently of the stage flip so a host handover between
        --the flip and the stamp still lifts the players' confinement.
        RecordCombatStarted()
        EnsureAIRunning()
        CheckEncounterOutcome(queue)
        return
    end

    if shared.stage == "combat" then
        --combat just ended: stand the AI down and go idle. What happens
        --after the encounter (victory flow, next steps) is later work.
        EnsureAIStopped()
        ctx:ModifyShared(function(s) s.stage = "complete" end)
        return
    end

    if shared.stage == "complete" then
        return
    end

    --pre-combat: wait until every expected player is in the game with their
    --heroes on the map, then roll into combat exactly once. Gathering the
    --sides BEFORE the run-once means an empty side (heroes still pasting,
    --spawn failed) retries next tick instead of consuming the one shot.
    if not EncounterOfTheWeekGame.AllPlayersArrived() then
        return
    end

    local sides = GatherCombatSides()
    if sides == nil then
        return
    end

    ctx:RunOnce("draw-steel", function()
        StartEncounterCombat(sides)
    end)
end

--- lobby ready signal -------------------------------------------------

--Tell the lobby this game is fully set up: the server flips the roster
--record "launched" -> "ready". Waiting members only enter the game when
--they see "ready" (the host enters on "launched" and runs setup first),
--so no joiner ever loads a half-initialized game. Safe to call when no
--roster record exists (a resume): the server answers "not registered",
--which we just log.
local function SignalGameReady()
    local gameid = dmhub.gameid
    SendLobbyRequest("ready-game", { gameid = gameid }, function(ok, result)
        if ok then
            printf("EotW: signaled ready-to-enter for game %s", gameid)
        else
            --"not registered" just means there is no roster record (a
            --resume long after launch); anything else is worth seeing.
            printf("EotW: ready-game signal not accepted: %s", tostring(result))
        end
    end)
end

--- arrival entry point ------------------------------------------------

--Called by the titlescreen EotW screen from the lobby:EnterGame arrival
--callback (fires after the game is fully loaded: map, floors, markup zones
--and tokens are all valid). args:
--  heroes:       the local player's claimed heroes, {kind, id, name} each.
--  clipboardIds: ids of the lobby heroes copied to the token clipboard, in
--                copy order (see PlaceMyHeroes).
--  numHeroes:    total filled hero slots in the game (from the lobby roster).
--  members:      userids of every player with claimed heroes at launch (from
--                the lobby roster; nil on a resume with no record).
--Every member places their own heroes and records their arrival; the host
--additionally stamps the game state, sets the "Number of Heroes" setting,
--spawns the encounter monsters, and attaches the EotW map script that then
--runs the encounter (combat entry + Monster AI).
function EncounterOfTheWeekGame.SetupOnArrival(args)
    args = args or {}
    dmhub.Coroutine(function()
        if mod.unloaded then
            return
        end

        --the host is the game's owner and keeps real hosting status
        --(IsDMOrPlayerHost -- true even in player-host mode, when dmhub.isDM
        --reads false), so it identifies exactly one client to run game-wide
        --setup.
        if IsDMOrPlayerHost() then
            --stamp the game and record who the encounter waits for, BEFORE
            --any hero placement, so every later joiner sees an EotW game.
            RecordExpectedUsers(args.members)

            --NOTE: nothing here switches on player-host mode. The game was
            --created directorless, so the engine already had it on before this
            --client finished loading.
        end

        PlaceMyHeroes(args.heroes, args.clipboardIds)

        --arrival is recorded AFTER hero placement: once every expected
        --player's arrival is visible, their heroes are on the map, so the
        --map script's combat entry never fires on a half-placed party.
        RecordArrival()

        if IsDMOrPlayerHost() then
            local numHeroes = tonumber(args.numHeroes) or 0
            if numHeroes <= 0 then
                --no slot count supplied (resuming an in-progress game with
                --no lobby record): keep the game's existing setting rather
                --than clobbering it with a fresh clamp.
                numHeroes = tonumber(dmhub.GetSettingValue("numheroes")) or 5
            else
                --the numheroes setting only accepts 3..7 (the EotW party range).
                if numHeroes < 3 then numHeroes = 3 end
                if numHeroes > 7 then numHeroes = 7 end
                dmhub.SetSettingValue("numheroes", numHeroes)
            end

            local ok, err = EncounterOfTheWeekGame.SpawnEncounterMonsters(numHeroes)
            if not ok then
                printf("EotW: encounter spawn failed: %s", tostring(err))
            end

            --there is no Director in an EotW game: every player may control
            --initiative (select turns, advance rounds) for their side.
            dmhub.SetSettingValue("permission:playersinitiative", true)

            --EotW games always strictly enforce the game rules.
            EnforceStrictRules()

            --the map script takes it from here: combat entry once everyone
            --has arrived, then Monster AI supervision.
            AttachMapScript()

            --signal ready even if the spawn failed: better to let everyone
            --in to see the problem than to leave them waiting forever.
            SignalGameReady()
        end
    end)
end
