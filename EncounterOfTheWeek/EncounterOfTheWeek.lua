local mod = dmhub.GetModLoading()

--Game-side logic for the Encounter of the Week game mode. This codemod ships
--with the mcdm-encounteroftheweek module, so it loads only inside EotW games
--(and the source game the module is authored in). Setup never runs on its
--own: the titlescreen EotW screen ("Codex Titlescreen/EncounterOfTheWeek.lua")
--hands it over, parking the arrival args in a global before entering the game
--and stamping them ready from the engine's lobby:EnterGame arrival callback.
--Whichever side loads second runs SetupOnArrival off that handoff -- see "the
--arrival handoff" at the foot of this file. It stays an explicit handoff, so
--entering the authoring game normally never triggers EotW setup. All other
--load-time behavior is passive: registering the EotW map-script builtin and
--the Director-UI filter, both inert until IsEotwGame() is true.
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md.

EncounterOfTheWeekGame = {}

--Launch-timing marker: grep Player.log for "[EOTWPROF]" (the titlescreen
--side logs the same way; server= is shared by every client). Never throws.
local function EotwProf(fmt, ...)
    local args = table.pack(...)
    pcall(function()
        printf("[EOTWPROF] server=%.3f app=%.3f " .. fmt, dmhub.serverTimeMilliseconds * 0.001, dmhub.Time(), table.unpack(args, 1, args.n))
    end)
end

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
--  data.alreadyCompleted = { [charid] = true }  (heroes whose owners'
--                       town says they already won this encounter; each
--                       owner stamps its own at arrival. The automatic
--                       Victory award skips them.)
--  data.practice      = true  (host-stamped at setup: a Danger Rooms game.
--                       Practice only -- no Victory, no treasure, no
--                       outcome goes home; players debrief it in town.)
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

--A debug Director window: this client was launched with `--director` (the
--"New Director Window" command on a dev+admin player host does this). The
--engine seeds dmhub.playerHostModeSuppressed from the same flag, so the
--client is the Director from its first frame; the Lua side must agree or the
--hatch driver below would switch it straight back off. Read once: a launch
--flag cannot change.
local m_isDirectorDebugWindow = nil
function EncounterOfTheWeekGame.IsDirectorDebugWindow()
    if m_isDirectorDebugWindow == nil then
        m_isDirectorDebugWindow = false
        pcall(function()
            for _,arg in ipairs(dmhub.commandLineArguments) do
                if arg == "--director" then
                    m_isDirectorDebugWindow = true
                end
            end
        end)
    end
    return m_isDirectorDebugWindow
end

--Should this client show the Director experience in an EotW game? The
--"/toggle eotw:showdirectorui" hatch or the --director launch flag.
function EncounterOfTheWeekGame.ShowDirectorUI()
    return dmhub.GetSettingValue("eotw:showdirectorui") == true
        or EncounterOfTheWeekGame.IsDirectorDebugWindow()
end

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

--Set when the player abandons this game (EncounterPresence.Abandon): JSON
--{ gameid }. The titlescreen's next refresh abandons it there: the
--eotwAbandonGame cloud function deletes the game when no other member
--still holds it, and the player leaves it either way. Declared again, with
--the same id, by the titlescreen.
setting{
    id = "eotw:abandonedgame",
    default = "",
    storage = "preference",
}

--Handoff to the town: what a decided encounter means for each of this
--machine's town heroes, written before leaving the game and applied by the
--town once the player is back (EotwRoster.ApplyPendingOutcomes: the
--Victory onto the roster hero, then the city's record-outcome, or for a
--hero with outcome.died, record-outcome {died} to bury them). JSON text:
--{ [userid] = { ["<gameid>|<heroid>"] = {gameid, heroid, outcome, stage} } }.
--Machine-local so it survives the game switch and a crash on the way home.
--The titlescreen re-declares it.
setting{
    id = "eotw:pendingOutcomes",
    default = "",
    storage = "preference",
}

--Handoff to the town after a Danger Rooms game: the town asks the player to
--debrief it (vote, feedback for its creator, next week's nomination). JSON
--text: { [userid] = {gameid, encounter, result} }, one game per player.
--Machine-local; the titlescreen re-declares it.
setting{
    id = "eotw:pendingDebrief",
    default = "",
    storage = "preference",
}

--Handoff to the town after any finished EotW game (won, lost, abandoned)
--while EotW is in beta: the town invites the player to the beta survey.
--JSON text: { [userid] = {gameid, encounter, kind, outcome, minutes,
--players, heroes} }, one game per player. Machine-local; the titlescreen
--re-declares it.
setting{
    id = "eotw:pendingSurvey",
    default = "",
    storage = "preference",
}

--Seconds this machine has spent in each EotW game, across sittings, so a
--resumed game counts its earlier play toward the survey's minimum.
--JSON text: { [gameid] = {seconds, at} }; entries a month old are dropped.
setting{
    id = "eotw:playtime",
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
    if m_isEotwGame then
        return true
    end

    --an authoring test (see "the authoring test"): this client plays the
    --encounter as a player host, so it gets the whole EotW game for as long
    --as the test runs. Never cached -- the test ends.
    return EncounterOfTheWeekGame.IsTestPlayer()
end

--- the authoring test: shared state ---------------------------------------
--The Director of an authoring game can play the encounter on the current map
--as its players will (Game menu > Test Encounter, the rest of it is under
--"the authoring test" near the foot of this file). The test lives in the
--state doc as data.test:
--  { phase = "setup"|"running"|"ending", mode = "start"|"montage"|"combat",
--    by = userid, startedAt, mapid, heroes = { source charid, ... },
--    placed = { pasted copy charid, ... }, saved = { settings, heroTokens } }

--The test record, or nil.
function EncounterOfTheWeekGame.GetTest()
    local test = nil
    pcall(function()
        local t = mod:GetDocumentSnapshot(STATE_DOC_ID).data.test
        if type(t) == "table" then
            test = t
        end
    end)
    return test
end

--Is a test playing (heroes placed, the script handed to the host tick)?
function EncounterOfTheWeekGame.IsTestRunning()
    local test = EncounterOfTheWeekGame.GetTest()
    return test ~= nil and test.phase == "running"
end

--Is THIS client playing the running test? Only a client in player-host mode
--does: the tester. Anyone else in the authoring game keeps their normal view.
function EncounterOfTheWeekGame.IsTestPlayer()
    return dmhub.playerHostMode == true and EncounterOfTheWeekGame.IsTestRunning()
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
        return EncounterOfTheWeekGame.ShowDirectorUI()
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

--this client's last recorded placedHeroes entry, so KeepMyArrivalRecorded can
--put it back if another client's write wipes it.
local m_myPlacedHeroes = nil

local function RecordPlacedHeroes(userid, mine)
    if userid == dmhub.loginUserid then
        m_myPlacedHeroes = mine
    end
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    doc.data.placedHeroes = doc.data.placedHeroes or {}
    doc.data.placedHeroes[userid] = mine
    doc:CompleteChange("Encounter of the Week: heroes placed", {undoable = false})
end

--Host only, at setup: stamp the game as EotW and record which players the
--encounter must wait for before entering combat (the launch roster's
--hero-claiming userids, computed on the titlescreen).
--the host's expectedUsers as written, so KeepMyArrivalRecorded can put it back.
local m_myExpectedUsers = nil

local function RecordExpectedUsers(members)
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    doc.data.eotw = true
    if type(members) == "table" and #members > 0 then
        doc.data.expectedUsers = members
        m_myExpectedUsers = members
    end
    doc:CompleteChange("Encounter of the Week: expected players", {undoable = false})
    m_isEotwGame = true
end

--Host only, at setup: record which encounter this game plays (its encounter
--KEY, see ParseEncounterKey) and the id of the map it resolved to, so members
--who arrive after the lobby roster record has expired -- and every resume --
--still land on the same map. The id matters for a community encounter: its
--module can ship a map with the same name as one of the official module's.
local function RecordEncounterMap(key, mapid)
    if type(key) ~= "string" or key == "" then
        return
    end
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    if doc.data.encounterMap == key and doc.data.encounterMapId == mapid then
        return
    end
    doc:BeginChange()
    doc.data.encounterMap = key
    doc.data.encounterMapId = mapid
    doc:CompleteChange("Encounter of the Week: encounter map", {undoable = false})
end

--Host only, at setup: a party from the Danger Rooms plays for practice (the
--town decides, from the week's schedule, and says so in the arrival). Only
--ever set, never cleared: a resume has no arrival flag and keeps the stamp.
local function RecordPracticeMode(practice)
    if practice ~= true then
        return
    end
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    if doc.data.practice == true then
        return
    end
    doc:BeginChange()
    doc.data.practice = true
    doc:CompleteChange("Encounter of the Week: Danger Rooms practice", {undoable = false})
end

--Is this a Danger Rooms game? Practice only: the host awards no Victory,
--nothing goes home, and each player debriefs the encounter back in town.
function EncounterOfTheWeekGame.IsPracticeGame()
    local practice = false
    pcall(function() practice = mod:GetDocumentSnapshot(STATE_DOC_ID).data.practice == true end)
    return practice
end


--Host only, at setup: the party's Hero Tokens for the session. Draw Steel
--hands the party a number of Hero Tokens equal to the number of heroes at
--the start of every game session, and one EotW game IS one session -- so
--the pool is seeded here, since there is no Director to do it by hand.
--
--Stamped once in the state doc so a resume (or the host reconnecting and
--running setup a second time) never refunds tokens the party has spent; a
--game whose combat has already begun is left alone outright, which also
--covers games that launched before this existed.
local function SeedHeroTokens(numHeroes)
    numHeroes = tonumber(numHeroes) or 0
    if numHeroes <= 0 then
        return
    end

    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    if doc.data.heroTokensSeeded == true or doc.data.combatStarted == true then
        return
    end

    --written before the stamp: a write that somehow fails leaves the seed
    --pending rather than silently swallowing the party's tokens.
    local ok = pcall(function()
        CharacterResource.SetGlobalResource(CharacterResource.heroTokenId, numHeroes, "Start of the session")
    end)
    if not ok then
        printf("EotW: could not seed the party's Hero Tokens")
        return
    end

    printf("EotW: seeded %d Hero Tokens for the session", numHeroes)

    doc:BeginChange()
    doc.data.heroTokensSeeded = true
    doc:CompleteChange("Encounter of the Week: hero tokens seeded", {undoable = false})
end

--- the players' party --------------------------------------------------

--Where a stray module pregen should be parked: the party the week's OTHER
--pregens already live in. Decided by a majority vote over module-content
--characters that sit outside the players' party, so it needs no hardcoded
--guid and no module download -- in mcdm-encounteroftheweek that elects
--"Delian Tomb Pregens", where 7 of the 9 pregens are authored. Ties break on
--the party id so repeated runs agree with each other. Returns nil when the
--game has no such party, in which case the sweep leaves the strays alone
--rather than inventing somewhere to put them.
local function PregenPartyID(defaultParty)
    local counts = {}
    for partyid,_ in pairs(dmhub.GetTable(Party.tableName) or {}) do
        if partyid ~= defaultParty then
            local n = 0
            for _,charid in ipairs(dmhub.GetCharacterIdsInParty(partyid)) do
                if module.IsCharacterAvailableInModule(charid) then
                    n = n + 1
                end
            end
            if n > 0 then
                counts[partyid] = n
            end
        end
    end

    local best, bestCount = nil, 0
    for partyid,n in pairs(counts) do
        if n > bestCount or (n == bestCount and best ~= nil and partyid < best) then
            best, bestCount = partyid, n
        end
    end

    return best
end

--Host only, at setup: the players' party holds the heroes the players
--brought, and nothing else.
--
--A module's characters are installed verbatim, party and all, and
--mcdm-encounteroftheweek itself authors two of its nine pregens (High Elf
--Tactician, Human Null) with partyId = the default Players guid -- the
--modules descend from the same source game, so the guid matches exactly and
--they land in the live party. Every EotW game therefore listed two extra
--unclaimed heroes nobody chose. Any other installed module that shares that
--lineage can do the same, so the sweep is written against the general case.
--
--Only MODULE CONTENT is touched: a hero placed by EotW is a paste with a
--fresh guid, so IsCharacterAvailableInModule is false for it, and a claimed
--hero carries its owner's userid rather than "PARTY". Both tests must fail
--for a record to move, and the pristine module character is only re-partied,
--never deleted -- PlaceMyHeroes duplicates it when a player claims that
--pregen. Cheap and idempotent, so it runs on every setup rather than being
--stamped: a module can finish installing after the first pass.
local function SweepPlayersParty()
    local defaultParty = GetDefaultPartyID()
    if defaultParty == nil then
        return
    end

    local strays = {}
    for _,charid in ipairs(dmhub.GetCharacterIdsInParty(defaultParty)) do
        if module.IsCharacterAvailableInModule(charid) then
            local token = dmhub.GetCharacterById(charid)
            local owner = token ~= nil and token.ownerId or nil
            if token ~= nil and (owner == nil or owner == "PARTY") then
                strays[#strays+1] = token
            end
        end
    end

    if #strays == 0 then
        return
    end

    local pregenParty = PregenPartyID(defaultParty)
    if pregenParty == nil then
        printf("EotW: %d unclaimed module character(s) in the players' party, but no pregen party to move them to", #strays)
        return
    end

    for _,token in ipairs(strays) do
        --the partyId setter force-writes ownerId = "PARTY", which is what
        --these already are, so no ownership is lost here.
        token.partyId = pregenParty
        token:UploadToken("Encounter of the Week: move unclaimed pregen out of the players' party")
        printf("EotW: moved unclaimed pregen %s out of the players' party", tostring(token.name))
    end
end

--- the encounter map ---------------------------------------------------

--An encounter module may ship several encounter maps: one named exactly
--this (the default) and any number named "<this>: <title>". Mirrored by the
--titlescreen's EncounterOfTheWeek.IsEncounterMapName and the publisher's
--is_encounter_map_name -- keep the three in step.
local DEFAULT_ENCOUNTER_MAP = "Encounter"

--Every EotW game is created from this module (it carries this codemod).
local OFFICIAL_MODULE = "mcdm-encounteroftheweek"

--The host picks an encounter from the town's pool in the Form a Party
--dialog, and the choice travels as an encounter KEY: the map name for one of
--the official module's maps ("Encounter: Goblin Ambush"), or
--"<moduleid>|<map name>" for a community Encounter of the Week module's
--(map ids change with every publish; names do not). A SERIES (one map
--played as several encounters, see "Encounter series" in the design doc)
--names its later parts with a "#<n>" suffix: "Encounter: The Crypt#2". Part
--1 is the bare key. Map names can never hold "#", so the suffix is never
--part of a name. Returns moduleid, map name, part; nil or "" is the official
--default map. A copy of the titlescreen's EncounterOfTheWeek.ParseEncounterKey
---- keep the two in step.
local function ParseEncounterKey(key)
    if type(key) ~= "string" or key == "" then
        return OFFICIAL_MODULE, DEFAULT_ENCOUNTER_MAP, 1
    end
    local part = 1
    local base, number = key:match("^(.-)#(%d+)$")
    if base ~= nil then
        key = base
        part = math.max(1, tonumber(number) or 1)
    end
    local moduleid, mapName = key:match("^([^|]+)|(.+)$")
    if moduleid == nil then
        return OFFICIAL_MODULE, key, part
    end
    return moduleid, mapName, part
end

--What this game plays, for the Codex > About Encounter of the Week dialog
--(EncounterOfTheWeekHud.lua): { title, mapid, moduleid }, or nil when no
--encounter map is up. title is the map's name without "Encounter: ", plus the
--part for a series. moduleid is the module the encounter came from (nil in an
--authoring test, which plays the authoring game's own map).
--- @return nil|{title: string, mapid: string, moduleid: nil|string}
function EncounterOfTheWeekGame.EncounterInfo()
    local mapid = game.currentMapId
    local map = mapid ~= nil and game.GetMap(mapid) or nil
    if map == nil then
        return nil
    end
    local name = tostring(map.description or "")
    local title = string.match(name, "^[^:]+:%s*(.+)$") or name

    --a series names the part: "The Crypt -- Part 2: The Ossuary".
    pcall(function()
        local montage = rawget(_G, "EncounterMontage")
        local script = montage ~= nil and montage.FindMapScript() or nil
        local part = script ~= nil and script.parse ~= nil and script.parse.part or nil
        if part ~= nil then
            local partName = string.format("Part %d", part.number)
            if part.title ~= nil then
                partName = partName .. ": " .. part.title
            end
            title = title .. " -- " .. partName
        end
    end)

    local moduleid = nil
    if not EncounterOfTheWeekGame.IsTestRunning() then
        pcall(function()
            local key = mod:GetDocumentSnapshot(STATE_DOC_ID).data.encounterMap
            if type(key) == "string" and key ~= "" then
                moduleid = ParseEncounterKey(key)
            end
        end)
    end
    return { title = title, mapid = mapid, moduleid = moduleid }
end

--The part an authoring test plays while it sets up (before data.test holds
--it), and the encounter key this client arrived with (before the host has
--stamped one). See ActivePart.
local m_testPart = nil
local m_arrivalKey = nil

--Which part of a series this game plays: the test's choice, else the part in
--the game's encounter key (the host's stamp, else the key this client
--arrived with). 1 for every encounter that is not a series. The script, its
--encounter island, and so the region and start area all follow it.
function EncounterOfTheWeekGame.ActivePart()
    if m_testPart ~= nil then
        return m_testPart
    end
    local data = nil
    pcall(function() data = mod:GetDocumentSnapshot(STATE_DOC_ID).data end)
    if data ~= nil then
        if type(data.test) == "table" and tonumber(data.test.part) ~= nil then
            return math.floor(tonumber(data.test.part) or 1)
        end
        if type(data.encounterMap) == "string" and data.encounterMap ~= "" then
            local _, _, part = ParseEncounterKey(data.encounterMap)
            return part
        end
    end
    if type(m_arrivalKey) == "string" and m_arrivalKey ~= "" then
        local _, _, part = ParseEncounterKey(m_arrivalKey)
        return part
    end
    return 1
end

local function FindMapByName(name)
    for _,map in pairs(game.maps or {}) do
        if map.description == name then
            return map
        end
    end
    return nil
end

local function FindMapById(mapid)
    if type(mapid) ~= "string" or mapid == "" then
        return nil
    end
    for _,map in pairs(game.maps or {}) do
        if map.id == mapid then
            return map
        end
    end
    return nil
end

--How long the host waits for a community encounter module to install and
--its encounter map to appear in the game.
local MODULE_INSTALL_TIMEOUT_SECONDS = 120

--Host only: remember which community module this game installed, so a
--re-entry does not install it again.
local function RecordEncounterModule(moduleid)
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    if doc.data.encounterModule == moduleid then
        return
    end
    doc:BeginChange()
    doc.data.encounterModule = moduleid
    doc:CompleteChange("Encounter of the Week: encounter module", {undoable = false})
end

--Host only, inside the setup coroutine: install a community encounter's
--module into this game, on top of the official module the game was created
--from, and return its encounter map (nil on failure, which is logged). The
--map is told apart from a same-named official map by being NEW: the map ids
--present before the install are snapshotted. On a re-entry, with the module
--already installed, the id stamped by RecordEncounterMap is used instead.
local function EnsureEncounterModule(moduleid, mapName)
    local data = mod:GetDocumentSnapshot(STATE_DOC_ID).data
    if data.encounterModule == moduleid then
        local map = FindMapById(data.encounterMapId) or FindMapByName(mapName)
        if map ~= nil then
            return map
        end
    end

    local before = {}
    for _,map in pairs(game.maps or {}) do
        before[map.id] = true
    end

    printf("EotW: installing the encounter module %s", moduleid)
    local installed = false
    local failure = nil
    module.DownloadModuleInfo{
        moduleid = moduleid,
        success = function(info)
            local ok, err = pcall(function()
                info:Install{
                    success = function()
                        installed = true
                    end,
                    error = function(message)
                        failure = message or "the install failed"
                    end,
                }
            end)
            if not ok then
                failure = tostring(err)
            end
        end,
        failure = function(message)
            failure = message or "the module was not found"
        end,
    }

    --the install's success can land before its maps reach game.maps, so
    --wait for the map itself, with a grace period after a success.
    local waited = 0
    local sinceInstalled = 0
    while waited < MODULE_INSTALL_TIMEOUT_SECONDS do
        for _,map in pairs(game.maps or {}) do
            if not before[map.id] and map.description == mapName then
                RecordEncounterModule(moduleid)
                printf("EotW: installed %s; its encounter map is %s", moduleid, map.id)
                return map
            end
        end
        if failure ~= nil then
            printf("EotW: could not install the encounter module %s: %s", moduleid, tostring(failure))
            return nil
        end
        if installed then
            sinceInstalled = sinceInstalled + 0.2
            if sinceInstalled > 10 then
                --installed but no new map: the module was already in the
                --game (its maps keep their ids), so take its map by name.
                local map = FindMapByName(mapName)
                if map ~= nil then
                    RecordEncounterModule(moduleid)
                end
                return map
            end
        end
        coroutine.yield(0.2)
        waited = waited + 0.2
    end
    printf("EotW: the encounter module %s did not install within %d seconds", moduleid, MODULE_INSTALL_TIMEOUT_SECONDS)
    return nil
end

--True when this client is already on the map an official-module encounter
--key names (lobby:EnterGame's startMap put it there). A community module's
--map only exists once the host's setup installs it, so that never counts.
local function OnRequestedEncounterMap(requested)
    if type(requested) ~= "string" or requested == "" then
        return false
    end
    local moduleid, name = ParseEncounterKey(requested)
    if moduleid ~= OFFICIAL_MODULE then
        return false
    end
    local map = FindMapByName(name)
    return map ~= nil and game.currentMapId == map.id
end

--Make sure this client is on the chosen encounter map, travelling there if
--not. Runs on every member's client on arrival, BEFORE hero placement: the
--engine's own choice of map on entry (the module's lowest-ord map, or the
--map your own token stands on) is only right by luck once the module ships
--more than one. Must run inside a coroutine -- it waits for the switch to
--land so callers see the new map's floors and Start zone.
--  requested: the encounter key from the lobby record (nil/"" = not chosen).
--Resolution order for the key: requested -> the host's stamp in the state
--doc (a resume after the lobby record expired) -> the default. For a
--community encounter the host first installs its module
--(EnsureEncounterModule); everyone else finds the map by the id the host
--stamped. A key with no matching map falls back to the official default
--map; with no default either we stay put.
--Returns the encounter key now in play and its map id (nil, nil if no map
--was found).
local function EnsureOnEncounterMap(requested)
    local stampedKey, stampedId = nil, nil
    pcall(function()
        local data = mod:GetDocumentSnapshot(STATE_DOC_ID).data
        stampedKey = data.encounterMap
        stampedId = data.encounterMapId
    end)

    local key = requested
    if type(key) ~= "string" or key == "" then
        key = stampedKey
    end
    if type(key) ~= "string" or key == "" then
        key = DEFAULT_ENCOUNTER_MAP
    end
    local moduleid, name = ParseEncounterKey(key)

    local map = nil
    if key == stampedKey then
        map = FindMapById(stampedId)
    end
    if map == nil and moduleid ~= OFFICIAL_MODULE and IsDMOrPlayerHost() then
        map = EnsureEncounterModule(moduleid, name)
    end
    if map == nil then
        map = FindMapByName(name)
    end
    if map == nil and key ~= DEFAULT_ENCOUNTER_MAP then
        printf("EotW: this game has no map for the encounter \"%s\"; falling back to \"%s\"", key, DEFAULT_ENCOUNTER_MAP)
        key = DEFAULT_ENCOUNTER_MAP
        name = DEFAULT_ENCOUNTER_MAP
        map = FindMapByName(name)
    end
    if map == nil then
        printf("EotW: this game has no map named \"%s\"; staying on the current map", name)
        return nil, nil
    end

    if game.currentMapId == map.id then
        return key, map.id
    end

    printf("EotW: travelling to the encounter map \"%s\"", name)
    map:Travel()

    --the animated switch syncs the map's details first, so give it a
    --generous window; a switch that never lands is logged, not fatal.
    local waited = 0
    while game.currentMapId ~= map.id and waited < 60 do
        coroutine.yield(0.1)
        waited = waited + 0.1
    end
    if game.currentMapId ~= map.id then
        printf("EotW: travel to \"%s\" did not complete; continuing on the current map", name)
        return nil, nil
    end

    --let the new map's floors and markup settle before anyone reads them.
    coroutine.yield(0.5)
    return key, map.id
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
    --No settle while an opening stage beat waits on the party: every
    --player's loading screen is held until that beat opens (RevealReady), so
    --nobody can load into the middle of anything.
    if newest ~= nil and not EncounterOfTheWeekGame.OpeningStageArriving() and math.abs(dmhub.serverTime - newest) < 3 then
        return false
    end
    return true
end

--Every client, after recording its arrival: until the whole party is in, put
--this client's entries back if they go missing -- its arrival and placed
--heroes, and on the host the expectedUsers list. Two clients writing the
--state doc at the same moment can overwrite each other (seen 2026-10-08:
--arrivals 76ms apart left only the later one; another time a member's first
--write erased the whole doc), and every loading screen then waits forever.
--A member can arrive before the host writes expectedUsers, so a member
--repairs nothing until it appears. Stops on leaving the game.
local ARRIVAL_REPAIR_SECONDS = 120
local function KeepMyArrivalRecorded()
    local userid = dmhub.loginUserid
    local gameid = dmhub.gameid
    local waited = 0
    while waited < ARRIVAL_REPAIR_SECONDS and not mod.unloaded do
        coroutine.yield(1)
        waited = waited + 1
        if dmhub.gameid ~= gameid then
            return
        end

        local data = mod:GetDocumentSnapshot(STATE_DOC_ID).data
        if type(data.expectedUsers) ~= "table" and m_myExpectedUsers ~= nil then
            printf("EotW: the expected players went missing from the shared state; recording them again")
            RecordExpectedUsers(m_myExpectedUsers)
            data = mod:GetDocumentSnapshot(STATE_DOC_ID).data
        end
        if type(data.expectedUsers) == "table" then
            if type(data.arrived) ~= "table" or data.arrived[userid] == nil then
                printf("EotW: this client's arrival went missing from the shared state; recording it again")
                RecordArrival()
            end
            if m_myPlacedHeroes ~= nil and (type(data.placedHeroes) ~= "table" or data.placedHeroes[userid] == nil) then
                printf("EotW: this client's placed heroes went missing from the shared state; recording them again")
                RecordPlacedHeroes(userid, m_myPlacedHeroes)
            end
            if EncounterOfTheWeekGame.AllPlayersArrived() then
                return
            end
        end
    end
end

--True while a narrative or montage beat is up but not yet opened: the host
--tick opens it once the whole party has arrived, applying the beat's first
--unlocks with it.
function EncounterOfTheWeekGame.OpeningStageArriving()
    local arriving = false
    pcall(function()
        local montage = rawget(_G, "EncounterMontage")
        local m = montage ~= nil and montage.GetState() or nil
        if m ~= nil and m.phase == "arriving" then
            arriving = true
        end
        local narrative = rawget(_G, "EncounterNarrative")
        local n = narrative ~= nil and narrative.GetState() or nil
        if n ~= nil and n.phase == "arriving" then
            arriving = true
        end
    end)
    return arriving
end

--Whether a held loading screen may be released: the whole party is in (its
--heroes placed) and the opening beat has opened, so what the screen reveals
--is complete -- every hero, and the features the beat unlocked -- rather
--than the host's own heroes with the rest popping in a few seconds later.
function EncounterOfTheWeekGame.RevealReady()
    return not EncounterOfTheWeekGame.OpeningStageArriving()
end

--- Start zone ---------------------------------------------------------

--Every tile of every "Start" markup zone on the current map, as placeable
--core.Loc values. Zone records store their rasterized tiles in .locs, so no
--per-tile aura queries are needed. Matches by keyword id, with the record's
--keywordName as a fallback (the same heal-by-name rule MapMarkup uses).
--
--A montage clause can open further zone types to start in ("the Start2 zone
--becomes a starting area", EncounterZones.UnlockedStartZones): their tiles
--join the result, so the confinement and its outline grow to cover them.
--Pass baseOnly = true for the Start zone alone (where heroes are placed).
--
--The encounter's own play area comes first (EncounterOfTheWeekGame.PlayArea):
--hero start tiles drawn in the encounter builder replace the Start zone, and
--a region keeps only the zone tiles inside it. That is how each part of a
--series starts in its own corner of a shared map.
local function StartZoneLocs(baseOnly)
    local map = game.currentMap
    if map == nil then
        return {}
    end

    local area = nil
    pcall(function() area = EncounterOfTheWeekGame.PlayArea() end)
    local function InRegion(x, y)
        local region = area ~= nil and area.region or nil
        return region == nil or (x >= region.x1 and x <= region.x2 and y >= region.y1 and y <= region.y2)
    end

    local startNames = { start = true }
    local result = {}
    if area ~= nil and #area.startLocs > 0 then
        --the builder's start tiles stand in for the Start zone.
        startNames = {}
        for _, l in ipairs(area.startLocs) do
            result[#result+1] = l
        end
    end
    if not baseOnly then
        local zones = rawget(_G, "EncounterZones")
        if zones ~= nil and zones.UnlockedStartZones ~= nil then
            for _, name in ipairs(zones.UnlockedStartZones()) do
                startNames[string.lower(name)] = true
            end
        end
    end

    local startIds = {}
    for k,v in unhidden_pairs(dmhub.GetTable("environmentalKeywords") or {}) do
        if v.name ~= nil and startNames[string.lower(v.name)] then
            startIds[k] = true
        end
    end

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
                        or (record.keywordName ~= nil and startNames[string.lower(record.keywordName)])) then
                    for _,l in ipairs(record.locs or {}) do
                        local x, y = math.floor(l.x), math.floor(l.y)
                        if InRegion(x, y) then
                            result[#result+1] = core.Loc{ x = x, y = y, floorIndex = floorIndex }
                        end
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
    local locs = StartZoneLocs(true)
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

--Must match the titlescreen's connection (Codex Titlescreen/EotwRoster.lua):
--the Blackbottom city, which holds the parties roster, on the staging server
--while EotW is dev-gated.
local LOBBY_ID = "blackbottom"
local LOBBY_OPTIONS = { staging = true, route = "city" }

--Send one request to the EotW lobby over a transient connection of our own
--(the titlescreen's connection closed when its screen was destroyed during
--the game switch). Requests fail immediately while the connection is still
--opening, so poll for auth first (give up after ~30s). onDone(ok, result)
--is optional; the connection is dropped either way.
--A connection opened ahead of time by PrewarmLobbyConnection, taken by the
--next SendLobbyRequest so the request does not wait on a cold connect + auth.
local m_prewarmedLobbyConn = nil

local function PrewarmLobbyConnection()
    local lobbies = rawget(_G, "lobbies")
    if lobbies == nil or m_prewarmedLobbyConn ~= nil then
        return
    end
    m_prewarmedLobbyConn = lobbies:Connect(LOBBY_ID, LOBBY_OPTIONS)
end

local function SendLobbyRequest(action, args, onDone)
    local lobbies = rawget(_G, "lobbies")
    if lobbies == nil then
        printf("EotW: engine has no lobbies API; cannot send %s", tostring(action))
        return
    end

    local conn = m_prewarmedLobbyConn
    m_prewarmedLobbyConn = nil
    if conn == nil then
        conn = lobbies:Connect(LOBBY_ID, LOBBY_OPTIONS)
    end
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

        EotwProf("lobby connection ready; sending %s", tostring(action))
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
--defined with the beat machine below; see there.
local MontageStageExpected
--the map the restriction/outline were built for, and the markup-zone
--revision they were read at. The game loads on whatever map the engine picks
--first (lowest ord) and EnsureOnEncounterMap travels to the chosen map
--AFTER the 1s driver has already confined to the first map's Start zone, so
--the confinement must follow the current map or every encounter inherits
--the first map's starting area.
local m_restrictionMapId = nil
local m_restrictionZonesSeq = nil
local m_outcomeSeen = false
local m_exitScheduled = false
--set the moment THIS user presses Proceed on the victory/defeat screen; the
--auto-exit below never fires without it, whatever the other clients do.
local m_localProceeded = false

local function ClearStartZoneConfinement()
    if m_restrictionInstalled then
        m_restrictionInstalled = false
        pcall(function() dmhub.ClearMovementRestriction() end)
    end
    m_restrictionMapId = nil
    m_restrictionZonesSeq = nil
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
    --NOT while a montage or narrative stage covers the map, though: the stage
    --has tooltips of its own (the item haul, the stat chips) and no token
    --shuffle to keep quiet for.
    local stageUp = false
    if MontageStageExpected ~= nil then
        stageUp = MontageStageExpected()
    end
    GameHud.SetTooltipsSuppressed("eotw", desired and not stageUp)

    if not desired then
        ClearStartZoneConfinement()
        return
    end

    local mapid = game.currentMapId
    local zonesSeq = nil
    pcall(function() zonesSeq = dmhub.markupZonesSeq end)
    --an unlocked extra start zone changes the area too.
    pcall(function()
        local zones = rawget(_G, "EncounterZones")
        if zones ~= nil and zones.UnlockedStartZones ~= nil then
            zonesSeq = tostring(zonesSeq) .. "|" .. table.concat(zones.UnlockedStartZones(), ",")
        end
    end)
    --and so does the play area (a series' part, its region and start tiles).
    pcall(function()
        local area = EncounterOfTheWeekGame.PlayArea()
        local r = area.region
        zonesSeq = string.format("%s|p%d|%s|%d", tostring(zonesSeq), area.part,
            r ~= nil and string.format("%d,%d,%d,%d", r.x1, r.y1, r.x2, r.y2) or "-", #area.startLocs)
    end)

    if m_restrictionInstalled then
        if m_restrictionMapId == mapid and m_restrictionZonesSeq == zonesSeq then
            return
        end
        --the map changed under us (EnsureOnEncounterMap travelling to the
        --chosen encounter, or a resume landing elsewhere) or the zones were
        --edited: tear down and rebuild for what is now on screen.
        ClearStartZoneConfinement()
        GameHud.SetTooltipsSuppressed("eotw", true)
    end

    local locs = StartZoneLocs()
    if #locs == 0 then
        --no Start zone on this map; nothing to confine to.
        return
    end

    m_restrictionInstalled = true
    m_restrictionMapId = mapid
    m_restrictionZonesSeq = zonesSeq
    --pcall: an engine build without the Movement Restriction API degrades to
    --no confinement (the zone outline below still draws).
    pcall(function() dmhub.SetMovementRestriction{ locs = locs } end)
    m_zoneMarker = dmhub.MarkLocs{
        locs = locs,
        color = START_ZONE_COLOR,
        style = "dashed",
    }
end

--- coming home ---------------------------------------------------------

--The Victories a won encounter is worth, to each hero who has not won it
--before (DSVictoryScreen.AwardVictories on the host; the town write-back).
local ENCOUNTER_VICTORIES = 1

--"victory" or "defeat": the outcome this client saw on the victory screen.
local m_outcomeKind = nil

--Has this game's encounter been decided (won or lost)? The game is ending
--then, so leaving it needs no "you can resume later" confirmation.
function EncounterOfTheWeekGame.OutcomeDecided()
    return m_outcomeSeen
end
local m_outcomesRecorded = false

--{charid = true}: heroes who had already won this encounter on arrival.
local function AlreadyCompletedHeroes()
    local result = {}
    pcall(function()
        local stamped = mod:GetDocumentSnapshot(STATE_DOC_ID).data.alreadyCompleted
        if type(stamped) == "table" then
            result = stamped
        end
    end)
    return result
end

--After hero placement: stamp which of MY heroes the town says already won
--this encounter (the city marks them `completed` in the party roster), so
--the host's Victory award skips them and their victory card says why.
local function RecordCompletedHeroes(heroes)
    local placed = GetPlacedHeroes(dmhub.loginUserid)
    local completed = {}
    local any = false
    for _, h in ipairs(heroes or {}) do
        local charid = placed["lobby:" .. tostring(h.id)]
        if h.completed == true and charid ~= nil then
            completed[charid] = true
            any = true
        end
    end
    if not any then
        return
    end
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    doc.data.alreadyCompleted = doc.data.alreadyCompleted or {}
    for charid in pairs(completed) do
        doc.data.alreadyCompleted[charid] = true
    end
    doc:CompleteChange("Encounter of the Week: heroes who already won", {undoable = false})
end

--Host, while the victory screen is up: award the encounter's Victory the
--way the Director's Award button would, once the cards have had time to
--fade in (or at once, `now`, when someone is already pressing Proceed).
--Dead heroes get nothing; heroes who won this encounter before get
--"Already Completed" on their card instead.
local VICTORY_AWARD_DELAY = 3
local m_victorySeenAt = nil
local function AutoAwardVictories(live, now)
    if live:try_get("victoriesAwarded", false) then
        return
    end
    --the Danger Rooms award nothing that lasts.
    if EncounterOfTheWeekGame.IsPracticeGame() then
        return
    end
    if m_victorySeenAt == nil then
        m_victorySeenAt = dmhub.serverTime
    end
    if not now and math.abs(dmhub.serverTime - m_victorySeenAt) < VICTORY_AWARD_DELAY then
        return
    end
    local completed = AlreadyCompletedHeroes()
    local exemptions = {}
    for _, token in ipairs(live:GetBattleHeroTokens()) do
        local props = token.properties
        if props == nil or props:IsDead() then
            exemptions[token.charid] = ""
        elseif completed[token.charid] then
            exemptions[token.charid] = "Already Completed"
        end
    end
    printf("EotW: awarding %d Victory to the heroes", ENCOUNTER_VICTORIES)
    --elevated: the award writes every player's heroes, and the host is a
    --player in an EotW game.
    ElevateToHostPermissions()
    local ok, err = pcall(DSVictoryScreen.AwardVictories, live, ENCOUNTER_VICTORIES, exemptions)
    DropHostPermissions()
    if not ok then
        printf("EotW: the Victory award failed: %s", tostring(err))
    end
end

--- treasure: what the heroes carry home ----------------------------------
--Consumables stay in the encounter; every other item a hero GAINED here
--(a montage reward, a chest on the map) goes home with them. "Gained" is
--measured against a snapshot of every hero's items the host takes once all
--players have arrived, before the first beat (state doc arrivalItems).

--Every item a creature holds, inventory and equipment slots together:
--{ [itemid] = count }.
local function ItemCounts(props)
    local counts = {}
    pcall(function()
        for itemid, entry in pairs(props:try_get("inventory", {})) do
            local q = type(entry) == "table" and tonumber(entry.quantity) or 0
            if q ~= nil and q > 0 then
                counts[itemid] = (counts[itemid] or 0) + q
            end
        end
    end)
    pcall(function()
        for itemid, q in pairs(props:GetEquipmentInAllSlots()) do
            counts[itemid] = (counts[itemid] or 0) + q
        end
    end)
    return counts
end

--Host, once: what every hero on the map carries at the start. Each record
--carries `_snapshot` so an empty inventory still reads back as a record (a
--hero with NO record -- a late arrival -- is never credited with treasure,
--or their whole pack would be counted as gained).
local function EnsureArrivalItems()
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    if doc.data.arrivalItems ~= nil then
        return
    end
    local snapshot = {}
    for _, token in ipairs(dmhub.allTokens) do
        local isHero = false
        pcall(function() isHero = token.valid and token.properties ~= nil and token.properties:IsHero() end)
        if isHero then
            local counts = ItemCounts(token.properties)
            counts._snapshot = 1
            snapshot[token.charid] = counts
        end
    end
    doc:BeginChange()
    doc.data.arrivalItems = snapshot
    doc:CompleteChange("Encounter of the Week: items on arrival", {undoable = false})
end

EncounterOfTheWeekGame.EnsureArrivalItems = EnsureArrivalItems

--The treasure a hero gained in this game: non-consumable items they hold
--now beyond what they arrived with, { { itemid, name, quantity }, ... }
--sorted by name. Empty for a hero with no arrival record.
function EncounterOfTheWeekGame.TreasureGained(token)
    local result = {}
    if token == nil or not token.valid or token.properties == nil then
        return result
    end
    local arrival = nil
    pcall(function()
        local all = mod:GetDocumentSnapshot(STATE_DOC_ID).data.arrivalItems
        if type(all) == "table" then
            arrival = all[token.charid]
        end
    end)
    if type(arrival) ~= "table" then
        return result
    end
    local gear = dmhub.GetTable("tbl_Gear") or {}
    for itemid, count in pairs(ItemCounts(token.properties)) do
        local gained = count - (tonumber(arrival[itemid]) or 0)
        local item = gear[itemid]
        if gained > 0 and item ~= nil and not EquipmentCategory.IsConsumable(item) then
            result[#result + 1] = { itemid = itemid, name = item.name, quantity = gained }
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

--"Bastion Belt" / "Bastion Belt x2, Ward Token".
local function DescribeTreasure(list)
    local parts = {}
    for _, t in ipairs(list) do
        parts[#parts + 1] = cond(t.quantity > 1, string.format("%s x%d", t.name, t.quantity), t.name)
    end
    return table.concat(parts, ", ")
end

--The victory card names the treasure each living hero is taking home.
pcall(function()
    --no IsEotwGame() gate: without the arrival snapshot (taken only by an EotW
    --host or the dev drivers) there is no treasure to name.
    DSVictoryScreen.RegisterHeroCardNote("eotw-treasure", function(live, token)
        if token == nil or token.properties == nil then
            return nil
        end
        local outcome = nil
        pcall(function() outcome = live:GetAwardedOutcome() end)
        if outcome ~= "victory" or token.properties:IsDead() then
            return nil
        end
        --practice: nothing found here goes home (see "eotw-practice").
        if EncounterOfTheWeekGame.IsPracticeGame() then
            return nil
        end
        local treasure = EncounterOfTheWeekGame.TreasureGained(token)
        if #treasure == 0 then
            return nil
        end
        return "Treasure: " .. DescribeTreasure(treasure)
    end)
end)

--In the Danger Rooms every hero's card says why nothing was awarded.
pcall(function()
    DSVictoryScreen.RegisterHeroCardNote("eotw-practice", function(live, token)
        if not EncounterOfTheWeekGame.IsPracticeGame() then
            return nil
        end
        return "Danger Rooms: practice only"
    end)
end)

--A surviving hero's wounds, to carry home (Downtime: nothing heals on the
--way back to town; a respite at the Blue Fish Inn does). Stamina lost and
--Recoveries spent, as the town applies them: absolute values, since this
--copy started the encounter from the town's working copy.
local function HeroWounds(tok)
    local wounds = nil
    pcall(function()
        local props = tok.properties
        local id = CharacterResource.recoveryResourceId
        wounds = {
            damage = math.max(0, math.floor(tonumber(props.damage_taken) or 0)),
            recoveriesUsed = math.max(0, math.floor(tonumber(props:GetResourceUsage(id, "long")) or 0)),
        }
    end)
    return wounds
end

--What this decided encounter means for each of a player's town heroes:
--{ { heroid, outcome }, ... } (heroid = the town roster id), for the town to
--apply once the player is home (see eotw:pendingOutcomes). `result` is
--"victory" or "defeat". A hero who is fully dead (not merely dying) at the
--end is buried: outcome.died, at a victory or a defeat. A survivor of a
--victory takes the Victory home (0 if they had won it before); every
--survivor, of a victory or a defeat, takes their wounds home
--(outcome.wounds). The player's own client sends these home; for a
--player who was away at the end, the host offers them through the city
--(OfferAbsentOutcomes).
local function OutcomesFor(userid, encounter, result)
    local completed = AlreadyCompletedHeroes()
    local entries = {}
    for key, charid in pairs(GetPlacedHeroes(userid)) do
        --town heroes travel as "lobby:<heroid>" (see PlaceMyHeroes).
        local heroid = string.match(key, "^lobby:(.+)$")
        --a dead hero is usually despawned into a corpse by the Hero Death
        --rule; GetCharacterById still finds the despawned token.
        local tok = heroid ~= nil and dmhub.GetCharacterById(charid) or nil
        local alive, dead = false, false
        pcall(function()
            if tok ~= nil and tok.properties ~= nil then
                dead = tok.properties:IsDead()
                alive = not dead
            end
        end)
        if dead then
            printf("EotW: %s fell in %s", tostring(tok ~= nil and tok.name or heroid), tostring(encounter))
            entries[#entries + 1] = {
                heroid = heroid,
                outcome = { encounter = encounter, result = result, died = true },
            }
        elseif alive and result == "victory" then
            local outcome = {
                encounter = encounter,
                result = "victory",
                victories = cond(completed[charid], 0, ENCOUNTER_VICTORIES),
                completed = true,
            }
            --the non-consumable treasure the hero won here travels home with
            --the outcome; the town adds it to their pack (EotwRoster).
            local treasure = EncounterOfTheWeekGame.TreasureGained(tok)
            if #treasure > 0 then
                outcome.treasures = treasure
                printf("EotW: %s takes home %s", tostring(tok ~= nil and tok.name or heroid), DescribeTreasure(treasure))
            end
            outcome.wounds = HeroWounds(tok)
            entries[#entries + 1] = { heroid = heroid, outcome = outcome }
        elseif alive then
            --a defeat's survivors bring nothing but their wounds home.
            entries[#entries + 1] = {
                heroid = heroid,
                outcome = { encounter = encounter, result = result, wounds = HeroWounds(tok) },
            }
        end
    end
    return entries
end

--The encounter key this game plays, or nil (logged) when none was stamped.
local function RecordedEncounter()
    local encounter = nil
    pcall(function() encounter = mod:GetDocumentSnapshot(STATE_DOC_ID).data.encounterMap end)
    if type(encounter) ~= "string" or encounter == "" then
        printf("EotW: no encounter name recorded; the town will not hear of this outcome")
        return nil
    end
    return encounter
end

--Note this client's heroes' outcomes (`result` "victory" or "defeat") for
--the town. Once per game.
local function RecordPendingOutcomes(result)
    if m_outcomesRecorded then
        return
    end
    m_outcomesRecorded = true

    --a Danger Rooms game sends nothing home, not even a death: the debrief
    --replaces it.
    if EncounterOfTheWeekGame.IsPracticeGame() then
        return
    end

    local encounter = RecordedEncounter()
    if encounter == nil then
        return
    end

    local entries = {}
    for _, e in ipairs(OutcomesFor(dmhub.loginUserid, encounter, result)) do
        entries[#entries + 1] = {
            gameid = dmhub.gameid,
            heroid = e.heroid,
            stage = "new",
            outcome = e.outcome,
        }
    end
    if #entries == 0 then
        return
    end

    local all = {}
    local text = dmhub.GetSettingValue("eotw:pendingOutcomes")
    if type(text) == "string" and text ~= "" then
        --FromJson answers {success, result}, not the decoded value.
        local parsed = dmhub.FromJson(text)
        if type(parsed) == "table" and parsed.success and type(parsed.result) == "table" then
            all = parsed.result
        end
    end
    local mine = all[dmhub.loginUserid]
    if type(mine) ~= "table" then
        mine = {}
        all[dmhub.loginUserid] = mine
    end
    for _, entry in ipairs(entries) do
        mine[entry.gameid .. "|" .. entry.heroid] = entry
    end
    dmhub.SetSettingValue("eotw:pendingOutcomes", dmhub.ToJson(all))
    printf("EotW: %d hero outcome(s) saved for the town", #entries)
end

--Host, at a victory or defeat: players who left without abandoning are not
--here to send their heroes' outcomes home (Victories, and burial for the
--dead), so leave them with the city as offers; each player accepts or
--ignores them in town ("While You Were Away"), and an ignored death buries
--no one. A player who abandoned gets nothing (user decision 2026-10-09).
local m_absentOffered = false
local function OfferAbsentOutcomes(result)
    if m_absentOffered or not IsDMOrPlayerHost() or EncounterOfTheWeekGame.IsPracticeGame() then
        return
    end
    m_absentOffered = true
    local presence = rawget(_G, "EncounterPresence")
    if presence == nil then
        return
    end
    local encounter = RecordedEncounter()
    if encounter == nil then
        return
    end
    for userid, rec in pairs(presence.GetData().away or {}) do
        if type(rec) == "table" and not rec.abandoned and not presence.HasAbandoned(userid) then
            local entries = OutcomesFor(userid, encounter, result)
            if #entries > 0 then
                SendLobbyRequest("offer-outcomes", { userid = userid, gameid = dmhub.gameid, entries = entries }, function(ok, result)
                    if ok then
                        printf("EotW: left %d hero result(s) with the city for %s, who was away", #entries, tostring(userid))
                    else
                        printf("EotW: could not leave results for %s: %s", tostring(userid), tostring(result))
                    end
                end)
            end
        end
    end
end

--After a Danger Rooms game, ask the town to have this player debrief it
--(eotw:pendingDebrief). Victory or defeat alike; a later game replaces it.
local function RecordPendingDebrief(outcome)
    if not EncounterOfTheWeekGame.IsPracticeGame() then
        return
    end
    local encounter = nil
    pcall(function() encounter = mod:GetDocumentSnapshot(STATE_DOC_ID).data.encounterMap end)
    if type(encounter) ~= "string" or encounter == "" then
        return
    end
    local all = {}
    local text = dmhub.GetSettingValue("eotw:pendingDebrief")
    if type(text) == "string" and text ~= "" then
        --FromJson answers {success, result}, not the decoded value.
        local parsed = dmhub.FromJson(text)
        if type(parsed) == "table" and parsed.success and type(parsed.result) == "table" then
            all = parsed.result
        end
    end
    all[dmhub.loginUserid] = {
        gameid = dmhub.gameid,
        encounter = encounter,
        result = outcome or "",
    }
    dmhub.SetSettingValue("eotw:pendingDebrief", dmhub.ToJson(all))
    printf("EotW: Danger Rooms debrief of %s waiting for the town", encounter)
end

--- the beta survey -------------------------------------------------------
--While EotW is in beta, every finished game (won, lost or abandoned) of at
--least SURVEY_MIN_SECONDS leaves eotw:pendingSurvey, and back in town the
--player is invited to a short survey they can answer or decline (the town's
--ShowSurveyDialog; the city keeps both). Set EOTW_BETA_SURVEY false to stop
--inviting when EotW leaves beta.
local EOTW_BETA_SURVEY = true
local SURVEY_MIN_SECONDS = 10 * 60

--Play clock: seconds spent in this game on this machine, banked into
--eotw:playtime so a resumed game keeps counting from where it left off.
local m_playClockAt = nil
local m_playUnbanked = 0
local PLAYTIME_BANK_SECONDS = 30
local PLAYTIME_KEEP_SECONDS = 30 * 24 * 60 * 60

local function ReadPlaytime()
    local text = dmhub.GetSettingValue("eotw:playtime")
    if type(text) ~= "string" or text == "" then
        return {}
    end
    --FromJson answers {success, result}, not the decoded value.
    local parsed = dmhub.FromJson(text)
    if type(parsed) ~= "table" or not parsed.success or type(parsed.result) ~= "table" then
        return {}
    end
    return parsed.result
end

local function BankPlaytime()
    if m_playUnbanked <= 0 then
        return
    end
    local all = ReadPlaytime()
    local now = dmhub.serverTime
    local entry = all[dmhub.gameid]
    local seconds = (type(entry) == "table" and tonumber(entry.seconds) or 0) + m_playUnbanked
    all[dmhub.gameid] = { seconds = seconds, at = now }
    for gameid, e in pairs(all) do
        if type(e) ~= "table" or (tonumber(e.at) or 0) < now - PLAYTIME_KEEP_SECONDS then
            all[gameid] = nil
        end
    end
    m_playUnbanked = 0
    dmhub.SetSettingValue("eotw:playtime", dmhub.ToJson(all))
end

--Called from the 1s driver. Counts only real EotW games, never a test; a
--long gap (the app frozen, or asleep) adds at most a few seconds.
local function UpdatePlayClock()
    if not EOTW_BETA_SURVEY or not EncounterOfTheWeekGame.IsEotwGame() or EncounterOfTheWeekGame.IsTestPlayer() then
        m_playClockAt = nil
        return
    end
    local now = dmhub.Time()
    if m_playClockAt ~= nil then
        m_playUnbanked = m_playUnbanked + math.min(math.max(0, now - m_playClockAt), 5)
    end
    m_playClockAt = now
    if m_playUnbanked >= PLAYTIME_BANK_SECONDS then
        BankPlaytime()
    end
end

--Seconds this machine has spent in the current game, all sittings.
function EncounterOfTheWeekGame.PlaySeconds()
    local entry = ReadPlaytime()[dmhub.gameid]
    return (type(entry) == "table" and tonumber(entry.seconds) or 0) + m_playUnbanked
end

--Leave a survey invitation for the town after this game. outcome is
--"victory", "defeat" or "abandoned". Skipped in tests, outside EotW, and
--for games shorter than SURVEY_MIN_SECONDS. A later game replaces it.
function EncounterOfTheWeekGame.RecordPendingSurvey(outcome)
    if not EOTW_BETA_SURVEY or not EncounterOfTheWeekGame.IsEotwGame() or EncounterOfTheWeekGame.IsTestPlayer() then
        return
    end
    if outcome ~= "victory" and outcome ~= "defeat" and outcome ~= "abandoned" then
        return
    end
    BankPlaytime()
    local seconds = EncounterOfTheWeekGame.PlaySeconds()
    if seconds < SURVEY_MIN_SECONDS then
        printf("EotW: no survey for a %d second game", math.floor(seconds))
        return
    end

    local encounter, players, heroes = "", 0, 0
    pcall(function()
        local data = mod:GetDocumentSnapshot(STATE_DOC_ID).data
        if type(data.encounterMap) == "string" then
            encounter = data.encounterMap
        end
        for _,_ in pairs(data.expectedUsers or {}) do
            players = players + 1
        end
        for _,placed in pairs(data.placedHeroes or {}) do
            for _,_ in pairs(placed) do
                heroes = heroes + 1
            end
        end
    end)

    local all = {}
    local text = dmhub.GetSettingValue("eotw:pendingSurvey")
    if type(text) == "string" and text ~= "" then
        local parsed = dmhub.FromJson(text)
        if type(parsed) == "table" and parsed.success and type(parsed.result) == "table" then
            all = parsed.result
        end
    end
    all[dmhub.loginUserid] = {
        gameid = dmhub.gameid,
        encounter = encounter,
        kind = cond(EncounterOfTheWeekGame.IsPracticeGame(), "danger", "week"),
        outcome = outcome,
        minutes = math.floor(seconds / 60 + 0.5),
        players = players,
        heroes = heroes,
    }
    dmhub.SetSettingValue("eotw:pendingSurvey", dmhub.ToJson(all))
    printf("EotW: beta survey (%s, %d min) waiting for the town", outcome, math.floor(seconds / 60))
end

--The script's story section for an outcome ("# Conclusion" after a victory,
--"# Defeat" after a defeat), or nil.
local function OutcomeStory(outcome)
    local section, script = nil, nil
    pcall(function()
        local montage = rawget(_G, "EncounterMontage")
        if montage ~= nil then
            script = montage.FindMapScript()
            local story = script.parse.story or {}
            section = story[cond(outcome == "defeat", "defeat", "conclusion")]
        end
    end)
    if section == nil or section.text == nil or section.text == "" then
        return nil
    end
    return section, script
end

--Watch the encounter conclude: once this client has seen the victory/defeat
--screen (an awarded outcome on the live queue), the local user has pressed
--Proceed, and the queue has hidden (combat torn down), leave for the
--titlescreen -- by way of the script's Conclusion / Defeat story screen
--when it has one. Another client's Proceed tears combat down but leaves this
--client's screen held until its own press. Clients that never saw an awarded
--outcome (mid-join, or a combat ended through the Director escape hatch)
--never auto-exit.
local function UpdateEncounterConclusion()
    if m_exitScheduled or not EncounterOfTheWeekGame.IsEotwGame() then
        return
    end
    --an authoring test has no town to carry anything home to, and its
    --"leaving" is the end of the test, back to the Director.
    local testing = EncounterOfTheWeekGame.IsTestPlayer()

    local queue = dmhub.initiativeQueue
    if queue ~= nil and not queue.hidden then
        local outcome, awarded = nil, false
        pcall(function()
            local live = queue:try_get("liveEncounter")
            if type(live) == "table" then
                outcome = live:GetAwardedOutcome()
                awarded = live:try_get("victoriesAwarded", false) == true
            end
        end)
        if outcome ~= nil and not m_outcomeSeen then
            m_outcomeSeen = true
            m_outcomeKind = outcome
            if outcome == "victory" then
                OfferAbsentOutcomes(outcome)
            end
        end
        --the Victory has landed: note it for the town now, not only on the
        --way out, so a crash on the victory screen does not lose it. A
        --defeat waits for the way out: a hero's Recovery on Death prompt can
        --still be open under the defeat screen, and must not bury them.
        if outcome == "victory" and awarded and not testing then
            RecordPendingOutcomes(outcome)
        end
        return
    end

    if m_outcomeSeen and m_localProceeded and testing then
        m_exitScheduled = true
        printf("EotW test: encounter concluded; ending the test")
        local section, script = OutcomeStory(m_outcomeKind)
        local stage = rawget(_G, "EncounterMontageStage")
        if section == nil or stage == nil or stage.ShowStoryScreen == nil then
            EncounterOfTheWeekGame.EndTest()
            return
        end
        dmhub.Schedule(0.8, function()
            if mod.unloaded then
                return
            end
            local title = nil
            pcall(function()
                title = string.match(game.currentMap.description or "", "^[^:]+:%s*(.+)$")
            end)
            local ok, err = pcall(stage.ShowStoryScreen, {
                outcome = m_outcomeKind,
                title = title,
                section = section,
                script = script,
                buttonText = "End Test",
                busyText = "Ending...",
                onContinue = EncounterOfTheWeekGame.EndTest,
            })
            if not ok then
                printf("EotW test: could not show the %s story: %s", tostring(m_outcomeKind), tostring(err))
                EncounterOfTheWeekGame.EndTest()
            end
        end)
        return
    end

    if m_outcomeSeen and m_localProceeded then
        m_exitScheduled = true
        printf("EotW: encounter concluded; returning to the titlescreen")

        --a victory whose award this client never saw (the host tore combat
        --down in the same moment) is still a victory for the town; a defeat
        --is noted here, once the screen has been dismissed (see above).
        if m_outcomeKind == "victory" or m_outcomeKind == "defeat" then
            RecordPendingOutcomes(m_outcomeKind)
            OfferAbsentOutcomes(m_outcomeKind)
        end
        RecordPendingDebrief(m_outcomeKind)
        EncounterOfTheWeekGame.RecordPendingSurvey(m_outcomeKind)

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
        --frame (and the victory screen's fade) finish first. With a story
        --screen the player leaves when they press on, but never before
        --EXIT_DELAY, so the host's end-of-combat writes still flush.
        local leaveAt = dmhub.Time() + EXIT_DELAY
        local function Leave()
            dmhub.Schedule(math.max(0.2, leaveAt - dmhub.Time()), function()
                if mod.unloaded then
                    return
                end
                dmhub.LeaveGame()
            end)
        end

        local section, script = OutcomeStory(m_outcomeKind)
        local stage = rawget(_G, "EncounterMontageStage")
        if section == nil or stage == nil or stage.ShowStoryScreen == nil then
            Leave()
            return
        end

        --after the victory screen's fade, the story screen; pressing on
        --from it is what takes the player home.
        dmhub.Schedule(0.8, function()
            if mod.unloaded then
                return
            end
            --"Encounter: Goblin Ambush" reads as "Goblin Ambush". The stamp
            --is an encounter key, so a community module's id comes off too.
            local title = nil
            pcall(function()
                local _, name = ParseEncounterKey(mod:GetDocumentSnapshot(STATE_DOC_ID).data.encounterMap)
                title = string.match(name or "", "^[^:]+:%s*(.+)$")
                --a series names the part: "The Crypt -- Part 2: The Ossuary".
                local part = script ~= nil and script.parse ~= nil and script.parse.part or nil
                if part ~= nil then
                    local partName = string.format("Part %d", part.number)
                    if part.title ~= nil then
                        partName = partName .. ": " .. part.title
                    end
                    title = cond(title ~= nil, (title or "") .. " -- " .. partName, partName)
                end
            end)
            local ok, err = pcall(stage.ShowStoryScreen, {
                outcome = m_outcomeKind,
                title = title,
                section = section,
                script = script,
                onContinue = Leave,
            })
            if not ok then
                printf("EotW: could not show the %s story: %s", tostring(m_outcomeKind), tostring(err))
                Leave()
            end
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
    --MACHINE is responsible for: the user's own heroes, and on the host the
    --monsters its Monster AI answers for. tok.canControl is elevation-aware
    --(false for monsters in the host's un-elevated tick), so ask under host
    --permissions -- a state read, no UI. Hostile prompts never age out, so
    --they must not block forever (same carve-out as the death gate).
    local pending = false
    ElevateToHostPermissions()
    for _,tok in ipairs(dmhub.allTokens) do
        if tok.valid and tok.canControl and tok.properties ~= nil then
            local triggers = nil
            pcall(function() triggers = tok.properties:GetAvailableTriggers(true) end)
            if triggers ~= nil then
                for _,t in pairs(triggers) do
                    if not t.hostile then
                        pending = true
                        break
                    end
                end
            end
        end
        if pending then
            break
        end
    end
    DropHostPermissions()

    return pending
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
--refresh: it is a debugging action. (A --director debug window is already
--suppressed by the engine from launch, so for it this is a no-op -- unless
--the engine predates the flag, in which case it refreshes once here.)
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
    --an authoring test is a Director playing as a player host on purpose;
    --End Test is its way back, so the hatch preference must not undo it.
    if EncounterOfTheWeekGame.IsTestPlayer() then
        return
    end
    local suppress = EncounterOfTheWeekGame.ShowDirectorUI()
    if dmhub.playerHostModeSuppressed ~= suppress then
        printf("EncounterOfTheWeek: Director UI hatch %s", tostring(suppress))
        dmhub.playerHostModeSuppressed = suppress
    end
end

--- arranging the heroes -------------------------------------------------
--When the heroes win the initiative (a die roll, or a montage outcome that
--hands it to them), the Draw Steel banner announces it and then HOLDS the
--start of combat: the party may move their heroes anywhere inside the
--start zone (plus any zone a clause unlocked) before the first turn. Each
--player presses Ready; when every voter is ready, or ARRANGE_SECONDS have
--passed, the host creates the initiative queue and the heroes go first.
--A party that loses the initiative (which a surprised party always does)
--goes straight into the fight.
--
--State doc: data.arrange = nil | { phase = "arranging"|"done", startedAt,
--deadline, ready = { [voterKey] = { at } }, endedAt }. Voter keys are the
--narrative's (EncounterNarrative.Voters): one per player who owns heroes,
--"PARTY" for party-owned heroes. Players write only their own key.
local ARRANGE_SECONDS = 120

--The banner's begin() for the held combat (host only). Lost on a Lua reload;
--the host tick then starts combat again with the heroes forced first.
local m_arrangeBegin = nil

--True while /eotwencounter is running the encounter beat in an authoring
--game, where IsEotwGame() is false but the arrangement panel should show.
local m_devEncounter = false

local function ArrangeState()
    local state = nil
    pcall(function() state = mod:GetDocumentSnapshot(STATE_DOC_ID).data.arrange end)
    if type(state) == "table" then
        return state
    end
    return nil
end

local function ArrangeVoters()
    local voters = {}
    pcall(function() voters = EncounterNarrative.Voters(nil) end)
    return voters or {}
end

--This user's voter key, or nil for a user with no heroes in the fight.
local function ArrangeVoterKey()
    local key = nil
    pcall(function() key = EncounterNarrative.VoterKeyForUser(dmhub.loginUserid) end)
    return key
end

--Every voter has pressed Ready, or the time is up.
local function ArrangeComplete(state)
    if state.deadline ~= nil and dmhub.serverTime >= state.deadline then
        return true
    end
    local voters = ArrangeVoters()
    if #voters == 0 then
        return true
    end
    for _, voter in ipairs(voters) do
        if (state.ready or {})[voter.key] == nil then
            return false
        end
    end
    return true
end

--Mark (or unmark) this user's party as arranged.
function EncounterOfTheWeekGame.SetArrangeReady(ready)
    local key = ArrangeVoterKey()
    local state = ArrangeState()
    if key == nil or state == nil or state.phase ~= "arranging" then
        return
    end
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    doc.data.arrange.ready = doc.data.arrange.ready or {}
    if ready then
        doc.data.arrange.ready[key] = { at = dmhub.serverTime }
    else
        doc.data.arrange.ready[key] = nil
    end
    doc:CompleteChange("Encounter of the Week: heroes arranged", {undoable = false})
end

--The banner resolved: hold for the arrangement when the heroes won. Only
--passed when no die was rolled (see StartEncounterCombat).
local function HoldForArrangement(heroesWin, begin)
    if not heroesWin then
        begin()
        return
    end
    m_arrangeBegin = begin
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    doc.data.arrange = {
        phase = "arranging",
        startedAt = dmhub.serverTime,
        deadline = dmhub.serverTime + ARRANGE_SECONDS,
        ready = {},
    }
    doc:CompleteChange("Encounter of the Week: arrange the heroes", {undoable = false})
    printf("EotW: the heroes won the initiative; they may arrange themselves for %ds", ARRANGE_SECONDS)
end

--- the arrangement panel (every client) -----------------------------------

local m_arrangePanel = nil

--"Kira", "Kira and Brann", "Kira, Brann and Osk".
local function JoinNames(names)
    if #names <= 1 then
        return names[1] or ""
    end
    return string.format("%s and %s", table.concat(names, ", ", 1, #names - 1), names[#names])
end

local function CreateArrangePanel()
    local statusLabel = gui.Label{
        classes = {"fg"},
        text = "",
        width = "100%",
        height = "auto",
        halign = "center",
        tmargin = 8,
        textAlignment = "center",
        textWrap = true,
        fontSize = 14,
    }
    local readyButton = gui.Button{
        text = "Ready",
        halign = "center",
        tmargin = 12,
        width = 200,
        height = 40,
        fontSize = 18,
        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            local state = ArrangeState()
            local key = ArrangeVoterKey()
            local mine = state ~= nil and key ~= nil and (state.ready or {})[key] ~= nil
            EncounterOfTheWeekGame.SetArrangeReady(not mine)
        end,
    }

    local function Refresh()
        local state = ArrangeState()
        if state == nil then
            return
        end
        local key = ArrangeVoterKey()
        local ready = state.ready or {}
        local waiting = {}
        for _, voter in ipairs(ArrangeVoters()) do
            if ready[voter.key] == nil and voter.key ~= key then
                waiting[#waiting + 1] = voter.name
            end
        end
        local left = math.max(0, math.ceil((state.deadline or dmhub.serverTime) - dmhub.serverTime))
        local timeText = string.format("The fight begins in %d:%02d", math.floor(left / 60), left % 60)
        local mine = key ~= nil and ready[key] ~= nil
        if mine and #waiting > 0 then
            statusLabel.text = string.format("You are ready. Waiting for %s. %s.", JoinNames(waiting), timeText)
        elseif mine then
            statusLabel.text = "Everyone is ready. Draw steel!"
        elseif #waiting > 0 then
            statusLabel.text = string.format("Also waiting for %s. %s.", JoinNames(waiting), timeText)
        else
            statusLabel.text = string.format("%s, or as soon as you are ready.", timeText)
        end
        readyButton.text = cond(mine, "Not Ready", "Ready")
    end

    local panel = gui.Panel{
        --an explicit backing: the HUD layer this mounts in does not render the
        --themed panel surfaces, and the text has to read over the map.
        classes = {"border"},
        bgimage = "panels/square.png",
        bgcolor = "#0c0f14e6",
        width = 560,
        height = "auto",
        --at the bottom, clear of the starting area the camera centres on.
        halign = "center",
        valign = "bottom",
        bmargin = 60,
        flow = "vertical",
        hpad = 20,
        vpad = 16,
        borderBox = true,
        cornerRadius = 8,
        borderWidth = 1,
        thinkTime = 0.5,
        think = function(element)
            Refresh()
        end,
        create = function(element)
            Refresh()
        end,
        children = {
            gui.Label{
                classes = {"info"},
                text = "Arrange Your Heroes",
                width = "100%",
                height = "auto",
                halign = "center",
                textAlignment = "center",
                fontSize = 22,
                fontWeight = "bold",
                uppercase = true,
            },
            gui.Label{
                classes = {"fg"},
                text = "You have won the initiative, and the enemy has not seen you yet. Move your heroes anywhere inside the outlined starting area, then press Ready. Your heroes act first.",
                width = "100%",
                height = "auto",
                halign = "center",
                tmargin = 8,
                textAlignment = "center",
                textWrap = true,
                fontSize = 16,
            },
            statusLabel,
            readyButton,
        },
    }
    return panel
end

--Show the arrangement panel to every player with heroes while the heroes
--are arranging, and take it down when the arrangement ends.
local function UpdateArrangePanel()
    local state = ArrangeState()
    local want = (EncounterOfTheWeekGame.IsEotwGame() or m_devEncounter) and state ~= nil
        and state.phase == "arranging" and ArrangeVoterKey() ~= nil
    local shown = m_arrangePanel ~= nil and m_arrangePanel.valid
    if want and not shown then
        if GameHud.instance ~= nil and GameHud.instance.parentPanel ~= nil then
            m_arrangePanel = CreateArrangePanel()
            GameHud.instance.parentPanel:AddChild(m_arrangePanel)
            --bring the starting area into view: that is where the moving happens.
            pcall(function()
                local anchor = StartZoneAnchor()
                if anchor ~= nil then
                    dmhub.CenterOnLoc{ x = anchor.x, y = anchor.y, smooth = true }
                end
            end)
        end
    elseif not want and shown then
        ---@cast m_arrangePanel -nil
        m_arrangePanel:DestroySelf()
        m_arrangePanel = nil
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
        pcall(UpdateArrangePanel)
        pcall(UpdateBusyMirror)
        pcall(UpdateEncounterConclusion)
        pcall(UpdatePlayClock)
        pcall(function() EncounterOfTheWeekGame.EnsureMapScriptRunning() end)
        --an authoring test waiting to be set up after its player-host refresh.
        pcall(function() EncounterOfTheWeekGame.ConsumePendingTest() end)
        --a montage turn that is this user's to roll (the stage's own think
        --also polls this; the driver is the backstop when the stage is not
        --mounted yet).
        pcall(function()
            local montage = rawget(_G, "EncounterMontage")
            if montage ~= nil then
                montage.ClientTick()
            end
        end)
        --zones the script revealed: this client's zone overlay shows them.
        pcall(function()
            local zones = rawget(_G, "EncounterZones")
            if zones ~= nil then
                zones.ClientTick()
            end
        end)
    end
end)

--Open the victory screen's Proceed button to every player in an EotW game.
--The HOST pressing runs the normal Director teardown (battle log, role
--history, analytics are Director-gated); a PLAYER pressing relays the
--request through the state doc for the host tick to execute. pcall: a core
--codex without the hook keeps the Director-only button.
--
--The screen is dismissed PER CLIENT: it stays up on this client, whatever
--the other clients or the host do, until the local user presses Proceed
--(holdUntilLocalProceed). Only that press releases this client's auto-exit.
pcall(function()
    DSVictoryScreen.RegisterProceedOverride{
        canProceed = function()
            return EncounterOfTheWeekGame.IsEotwGame()
        end,
        holdUntilLocalProceed = function()
            --once this user has pressed Proceed the screen may close with
            --the queue as normal (that close is what triggers the exit).
            return EncounterOfTheWeekGame.IsEotwGame() and not m_localProceeded
        end,
        proceed = function(defaultProceed, alreadyEnded)
            if not EncounterOfTheWeekGame.IsEotwGame() then
                return false
            end
            m_localProceeded = true
            if alreadyEnded then
                --combat was torn down while this screen was held; the
                --driver below exits now that the local press has happened.
                return true
            end
            --the HOST (a player host: real hosting status, presented as a
            --player) falls through to the default teardown -- battle log,
            --role history and analytics must run on the host machine. A
            --Proceed pressed before the automatic Victory award awards first.
            if IsDMOrPlayerHost() then
                pcall(function()
                    local live = dmhub.initiativeQueue:try_get("liveEncounter")
                    if type(live) == "table" and live:GetAwardedOutcome() == "victory" then
                        AutoAwardVictories(live, true)
                    end
                end)
                --a test fight is not a real one: end it without the
                --default teardown's battle log and analytics.
                if EncounterOfTheWeekGame.IsTestPlayer() then
                    EncounterOfTheWeekGame.EndTestCombat()
                    return true
                end
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
--
--On a SERIES map every part has its own script and its own island, so only
--the documents of the part being played count (EncounterMontage.ScriptDocuments),
--and info-bubble encounters never do. FindMapScript itself falls back on this
--for a map with no script document, hence the re-entry guard.
local m_findingMapEncounter = false
local function FindMapEncounter()
    local partDocs = nil
    local montage = rawget(_G, "EncounterMontage")
    if not m_findingMapEncounter and montage ~= nil and montage.ScriptDocuments ~= nil then
        m_findingMapEncounter = true
        pcall(function()
            local script = montage.FindMapScript()
            if #(script.seriesParts or {}) > 0 then
                partDocs = montage.ScriptDocuments(script)
            end
        end)
        m_findingMapEncounter = false
    end

    --hostAccess: EotW games are directorless, so the host's dmhub.isDM is false
    --and the map's journal folder is not in their viewing roots -- without this
    --the encounter is invisible to the very client that has to spawn it.
    local entries = Encounter.GetEncountersOnCurrentMap(true)
    local mapid = game.currentMapId
    local docsTable = dmhub.GetTable("documents") or {}
    for _,entry in ipairs(entries) do
        if partDocs ~= nil then
            if entry.docid ~= nil and partDocs[entry.docid] then
                return entry
            end
        elseif entry.bubbleid ~= nil then
            return entry
        elseif entry.docid ~= nil then
            local doc = docsTable[entry.docid]
            if doc ~= nil and CustomDocument.IsDocInAccessibleRoot(doc, { [mapid] = true }) then
                return entry
            end
        end
    end
    return nil
end
EncounterOfTheWeekGame.FindMapEncounter = FindMapEncounter

--- the play area -----------------------------------------------------

--Where this encounter is played, from its island's encounter as drawn in the
--encounter builder: `region`, the rectangle of the map the fight is bounded
--to ({x1, y1, x2, y2}, tiles, inclusive), and `startLocs`, the tiles heroes
--start on (core.Loc on the current map). Either may be nil/empty: no region
--= the whole map; no start tiles = the map's Start zone. This is what lets a
--series play its parts on different parts of one map. Cached for a couple of
--seconds -- the 1s drivers ask -- and keyed by map and part.
---@class EotwPlayArea
---@field mapid string|nil
---@field part integer
---@field at number when it was worked out (dmhub.Time)
---@field region EncounterRegion|nil
---@field startLocs Loc[]
---@field encounter Encounter|nil the part's island encounter

---@type EotwPlayArea|nil
local m_playArea = nil
local PLAY_AREA_CACHE_SECONDS = 2

--- @return EotwPlayArea
function EncounterOfTheWeekGame.PlayArea()
    local mapid = game.currentMapId
    local part = EncounterOfTheWeekGame.ActivePart()
    local now = dmhub.Time()
    if m_playArea ~= nil and m_playArea.mapid == mapid and m_playArea.part == part
        and now - m_playArea.at < PLAY_AREA_CACHE_SECONDS then
        return m_playArea
    end

    ---@type EotwPlayArea
    local area = { mapid = mapid, part = part, at = now, region = nil, startLocs = {} }
    pcall(function()
        local entry = FindMapEncounter()
        if entry == nil or entry.encounter == nil then
            return
        end
        area.encounter = entry.encounter
        area.region = entry.encounter:GetRegion()
        area.startLocs = Encounter.StartLocsOnCurrentMap(entry.encounter:GetHeroStartLocs())
    end)
    m_playArea = area
    return area
end

--Is the tile inside the play area's region (always true with no region)?
function EncounterOfTheWeekGame.InPlayRegion(x, y)
    local region = EncounterOfTheWeekGame.PlayArea().region
    if region == nil then
        return true
    end
    return x >= region.x1 and x <= region.x2 and y >= region.y1 and y <= region.y2
end

--Host (or the authoring test): bound the map to the play area's region for
--the whole game, not just from combat on, so the heroes never see or reach
--the rest of the map. The core restores the original bounds only when told
--(hold) -- an EotW game is thrown away afterwards; an authoring test puts
--them back at its end (ReleasePlayRegion).
local function ApplyPlayRegion()
    local area = EncounterOfTheWeekGame.PlayArea()
    if area.region == nil or area.encounter == nil then
        return
    end
    ElevateToHostPermissions()
    local ok, err = pcall(Encounter.ApplyRegion, area.encounter, { hold = true, anyMap = true })
    DropHostPermissions()
    if ok then
        printf("EotW: the map is bounded to the encounter's region (%d,%d)-(%d,%d)",
            area.region.x1, area.region.y1, area.region.x2, area.region.y2)
    else
        printf("EotW: could not bound the map to the encounter's region: %s", tostring(err))
    end
end
EncounterOfTheWeekGame.ApplyPlayRegion = ApplyPlayRegion

local function ReleasePlayRegion()
    pcall(Encounter.RestoreRegionBounds, game.currentMapId)
    m_playArea = nil
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

--Detach the pasted copy from the engine's lobby hero sync. CreateHero
--stamps every lobby hero with properties.originalid (its lobby charid) and
--properties.creatorid (its owner); both ride inside properties, so the paste
--carries them into the EotW copy. With them present, the engine periodically
--saves the owner's primary character to char-cache/{originalid}.json
--(CharacterToken.SaveLocally, gated by creatorid == me) and the next lobby
--load PUTs that file over the ORIGINAL lobby hero (SerializedCharacterInfo.
--LoadLocally) -- which is how EotW stamina, recoveries, conditions and the
--level-1 clamp leaked home (ticket 3GJJQYJV). That sync is right for campaign
--copies and wrong for a disposable weekly copy, so clear both stamps here.
--creatorid is the gate, originalid the file name: clear BOTH, since a copy
--with creatorid but no originalid would save to a nameless file.
local function DetachFromLobbySync(token)
    local props = token.properties
    if props == nil then
        return
    end

    local hasOriginal = props:try_get("originalid") ~= nil
    local hasCreator = props:try_get("creatorid") ~= nil
    if not (hasOriginal or hasCreator) then
        return
    end

    token:ModifyProperties{
        description = "Encounter of the Week: detach from lobby hero",
        undoable = false,
        execute = function()
            props.originalid = nil
            props.creatorid = nil
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
                --properties patches, issued after the token upload: cut the
                --copy loose from the lobby hero it was pasted from, then
                --clamp it to the level the encounter is balanced for.
                DetachFromLobbySync(token)
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

--Start-zone tiles ordered by distance from the anchor (ties by x then y):
--the shared spreading order every client agrees on.
local function StartZoneTilesByDistance(anchor)
    local tiles = StartZoneLocs()
    local ax, ay = anchor.x, anchor.y
    table.sort(tiles, function(a, b)
        local da = (a.x - ax) * (a.x - ax) + (a.y - ay) * (a.y - ay)
        local db = (b.x - ax) * (b.x - ax) + (b.y - ay) * (b.y - ay)
        if da ~= db then
            return da < db
        end
        if a.x ~= b.x then
            return a.x < b.x
        end
        return a.y < b.y
    end)
    return tiles
end

--The nth (1-based) tile in ordered that no token occupies, or nil.
local function NthFreeStartTile(ordered, n)
    local count = 0
    for _,loc in ipairs(ordered) do
        if game.GetTokensAtLoc(loc) == nil then
            count = count + 1
            if count == n then
                return loc
            end
        end
    end
    return nil
end

--The free Start-zone tile nearest loc, or nil when the map has no Start
--zone or it is full. Used by the montage runtime to seat an ally beside
--its hero (EncounterMontage.lua).
function EncounterOfTheWeekGame.FreeStartTileNear(loc)
    if loc == nil then
        return nil
    end
    return NthFreeStartTile(StartZoneTilesByDistance(loc), 1)
end

--how long to wait for other clients' pastes to echo back before checking
--for stacked heroes, and how many check/repair rounds to run.
local UNSTACK_WAIT = 1.0
local UNSTACK_ROUNDS = 3

--Tile-set key for a Loc, so tiles can be looked up by position. A Loc
--exposes its floor as .floor (core.Loc{floorIndex=...} constructs it, but
--the field reads back as .floor).
local function LocKey(loc)
    return string.format("%d,%d,%d", math.floor(loc.x), math.floor(loc.y), loc.floor or 0)
end

--Every hero token on the current map standing outside the Start zone, sorted
--by charid: the shared order every client agrees on when spreading them
--back in. startSet is keyed by LocKey.
local function HeroesOutsideStartZone(startSet)
    local ids = {}
    for _,token in ipairs(dmhub.allTokens) do
        if token.valid and token.playerControlled and token.properties ~= nil then
            local isHero = false
            pcall(function() isHero = token.properties:IsHero() end)
            if isHero and not startSet[LocKey(token.loc)] then
                ids[#ids+1] = token.charid
            end
        end
    end
    table.sort(ids)
    return ids
end

--Repair heroes this client just pasted that did not end up alone on a
--Start-zone tile.
--
--Outside the zone: the engine's paste fans out from the anchor by distance
--alone (anchor, its neighbours, then rings), with no idea a markup zone
--exists, so a zone narrower than a 3x3 block around the anchor -- a
--corridor, an L -- spills heroes over its edge. Every such hero (any
--client's) is ranked by charid and takes that rank's free Start-zone tile.
--
--Stacked: the paste's vacancy scan cannot see a paste another client sent
--in the same instant (both echo back after both have chosen), so two
--arrivals can land on the anchor tile together. After the echoes land every
--client sees the same pile, so the repair is deterministic: the lowest
--charid keeps the tile and each other member takes the next free Start-zone
--tile in the shared distance order -- two clients repairing the same pile at
--once therefore pick different tiles.
--
--Re-checks a few times to catch echoes that arrive late. Yields; runs
--inside PlaceMyHeroes' coroutine.
local function UnstackPlacedHeroes(charids, anchor)
    if charids == nil or #charids == 0 then
        return
    end
    local ordered = StartZoneTilesByDistance(anchor)
    if #ordered == 0 then
        --no Start zone: nothing to spread across.
        return
    end
    local startSet = {}
    for _,loc in ipairs(ordered) do
        startSet[LocKey(loc)] = true
    end

    for _ = 1, UNSTACK_ROUNDS do
        coroutine.yield(UNSTACK_WAIT)
        if mod.unloaded then
            return
        end
        game.UpdateCharacterTokens()

        local moved = false
        local outside = nil
        for _,charid in ipairs(charids) do
            local token = dmhub.GetCharacterById(charid)
            if token ~= nil and not startSet[LocKey(token.loc)] then
                outside = outside or HeroesOutsideStartZone(startSet)
                local rank = 0
                for i,id in ipairs(outside) do
                    if id == charid then
                        rank = i
                    end
                end
                local dest = rank > 0 and NthFreeStartTile(ordered, rank) or nil
                if dest ~= nil then
                    printf("EotW: hero %s landed outside the Start zone at %s; moving it to %s", charid, tostring(token.loc), tostring(dest))
                    token:ChangeLocation(dest.withGroundAltitude)
                    moved = true
                else
                    printf("EotW: hero %s is outside the Start zone but it has no free tile", charid)
                end
            elseif token ~= nil then
                local stacked = game.GetTokensAtLoc(token.loc) or {}
                if #stacked > 1 then
                    local ids = {}
                    for _,t in ipairs(stacked) do
                        ids[#ids+1] = t.charid
                    end
                    table.sort(ids)
                    local rank = 0
                    for i,id in ipairs(ids) do
                        if id == charid then
                            rank = i - 1
                        end
                    end
                    if rank > 0 then
                        local dest = NthFreeStartTile(ordered, rank)
                        if dest ~= nil then
                            printf("EotW: hero %s shares %s with %d other token(s); moving it to %s", charid, tostring(token.loc), #stacked - 1, tostring(dest))
                            token:ChangeLocation(dest.withGroundAltitude)
                            moved = true
                        else
                            printf("EotW: hero %s is stacked but the Start zone has no free tile", charid)
                        end
                    end
                end
            end
        end

        if not moved then
            return
        end
    end
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
        --the paste APIs need a Loc (a Vector2 fails the engine's cast); world
        --coordinates map 1:1 to tile coordinates.
        local cam = dmhub.cameraPosition
        anchor = core.Loc{ x = round(cam.x), y = round(cam.y), floorIndex = game.currentFloorIndex }
    end

    local changed = false
    --every hero this call put on the map, for the stacking repair below.
    local myPasted = {}

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
            EotwProf("lobby heroes pasted (%d); waiting for the echo", #pastedIds)
            WaitForPastedCharacters(pastedIds)
            EotwProf("lobby heroes resolved")

            for i,charid in ipairs(pastedIds) do
                local heroid = clipboardIds[i]
                local key = heroid ~= nil and ("lobby:" .. heroid) or nil
                if key == nil then
                    --more pastes than copied ids should not happen; keep the
                    --token rather than guessing, but do not record it.
                    printf("EotW: pasted hero %d has no matching claim entry", i)
                    ClaimPastedHero(charid)
                    myPasted[#myPasted+1] = charid
                elseif mine[key] ~= nil then
                    --this hero was placed on an earlier entry; the batch paste
                    --recreated it, so delete the duplicate.
                    game.DeleteCharacters({charid})
                else
                    ClaimPastedHero(charid)
                    myPasted[#myPasted+1] = charid
                    mine[key] = charid
                    changed = true
                end
            end
        end
    end

    --pregens are module characters, already present (unplaced) in the game:
    --duplicate them onto the map with one same-game batch copy/paste and one
    --wait, like the lobby heroes. This must run AFTER the batch paste above --
    --copying wipes the clipboard.
    local entries, tokens = {}, {}
    for _,heroEntry in ipairs(heroes or {}) do
        if heroEntry.kind == "pregen" and mine[HeroKey(heroEntry)] == nil then
            local sourceToken = dmhub.GetCharacterById(heroEntry.id)
            if sourceToken == nil then
                printf("EotW: pregen %s (%s) not found in this game", tostring(heroEntry.name), tostring(heroEntry.id))
            else
                entries[#entries+1] = heroEntry
                tokens[#tokens+1] = sourceToken
            end
        end
    end
    if #tokens > 0 then
        dmhub.CopyTokensToClipboard(tokens)
        local pastedIds = dmhub.PasteTokensFromClipboard(anchor) or {}
        WaitForPastedCharacters(pastedIds)
        for i,charid in ipairs(pastedIds) do
            local heroEntry = entries[i]
            ClaimPastedHero(charid)
            myPasted[#myPasted+1] = charid
            if heroEntry ~= nil then
                mine[HeroKey(heroEntry)] = charid
                changed = true
            end
        end
    end

    if changed then
        game.UpdateCharacterTokens()
        RecordPlacedHeroes(userid, mine)
    end

    --another client arriving in the same instant may have pasted onto the
    --same tiles: the caller spreads any pile with UnstackPlacedHeroes once
    --it has recorded its arrival (the repair waits on other clients' pastes,
    --and the arrival is what the whole party's loading screens wait on).
    return myPasted, anchor
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
    doc.data.heroTokensSeeded = nil
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
    --0.5s: a montage turn (drag, choose, roll) should answer promptly.
    hostThinkInterval = 0.5,

    --another client took over hosting (or this one lost its host status):
    --stand down what only the host runs, so two Monster AIs never play the
    --same monsters.
    onLoseHost = function(ctx)
        local eotw = rawget(_G, "EncounterOfTheWeekGame")
        if eotw ~= nil and eotw.MapScriptLoseHost ~= nil then
            eotw.MapScriptLoseHost(ctx)
        end
    end,
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

--Self-healing, from every client's 1s driver. A mid-game Lua reload once
--killed a live encounter: Core Rules reloaded AFTER this mod, MapScript's
--fresh builtin registry no longer knew "builtin:eotw-encounter", the attached
--record stopped resolving, the driver tore the instance down and the host
--tick (combat entry, AI supervision, victory detection) silently stopped.
--So, every tick: (1) any client re-registers the builtin if the registry
--lost it; (2) the HOST of an EotW game makes sure the record is attached to
--the current map and reports (once) if it still is not running. Cheap when
--healthy: a table lookup and a walk of a one-entry list.
local m_reportedScriptNotRunning = false
function EncounterOfTheWeekGame.EnsureMapScriptRunning()
    local ms = rawget(_G, "MapScript")
    if ms == nil then
        return
    end
    if ms.GetBuiltin(MAP_SCRIPT_ID) == nil then
        printf("EotW: the map script builtin was missing; re-registering it")
        RegisterMapScriptBuiltin()
    end

    if not (EncounterOfTheWeekGame.IsEotwGame() or EncounterOfTheWeekGame.IsTestRunning()) or not IsDMOrPlayerHost() then
        return
    end
    if game.currentMapId == nil or game.currentMapId == "" then
        return
    end

    local record = nil
    for _,rec in ipairs(ms.GetAttachedRecords()) do
        if rec.scriptid == MAP_SCRIPT_ID then
            record = rec
            break
        end
    end
    if record == nil then
        printf("EotW: the map script was not attached to the map; attaching it")
        AttachMapScript()
        return
    end

    --the map-script driver reconciles attachments every 0.5s, so a record
    --whose code resolves runs on its own; if it still does not, say so once
    --rather than every second.
    local running = true
    if ms.IsRecordRunning ~= nil then
        running = ms.IsRecordRunning(record.guid)
    end
    if running then
        m_reportedScriptNotRunning = false
    elseif not m_reportedScriptNotRunning then
        m_reportedScriptNotRunning = true
        local code = ms.GetRecordCode(record)
        printf("EotW: the map script is attached but not running (code resolves: %s)", tostring(code ~= nil and code ~= ""))
    end
end

--- combat entry ---------------------------------------------------------

--The names the script's "# Encounter" beat declares as bystanders
--("Civilian tokens stay out of initiative"), lower-cased, or {}.
local function BystanderNames()
    local names = {}
    pcall(function()
        local montage = rawget(_G, "EncounterMontage")
        if montage == nil then
            return
        end
        for _, beat in ipairs(montage.FindMapScript().parse.beats or {}) do
            if beat.kind == "encounter" then
                for _, instruction in ipairs(beat.setup or {}) do
                    if instruction.kind == "bystanders" then
                        for _, name in ipairs(instruction.names or {}) do
                            names[#names + 1] = string.lower(name)
                        end
                    end
                end
            end
        end
    end)
    return names
end

--Is this token one of the script's bystanders? A name matches the token's
--name, a token named "<name> <anything>" ("Civilian" covers "Civilian 2"),
--or the bestiary type of a monster token.
function EncounterOfTheWeekGame.IsBystander(token, names)
    names = names or BystanderNames()
    if #names == 0 or token == nil or not token.valid then
        return false
    end
    local tokenName = string.lower(token.name or "")
    local monsterType = nil
    pcall(function() monsterType = string.lower(token.properties:try_get("monster_type") or "") end)
    for _, name in ipairs(names) do
        if tokenName == name or string.sub(tokenName, 1, #name + 1) == name .. " " or monsterType == name then
            return true
        end
    end
    return false
end

--Bystanders stand outside the fight: they make no opportunity attacks and
--provoke none. Both the movement dispatch (creature:OnMove) and the token
--HUD's opportunity-attack preview ask creature:CanOpportunityAttack, so
--failing it here covers both. Only EotW games and authoring tests pay for
--the lookup (it scans the map's documents); the names are cached per game
--update because the dispatch asks once per observer per step.
local m_oaBystanderNames = nil
local m_oaBystanderUpdate = nil
local g_baseCanOpportunityAttack = creature.CanOpportunityAttack
function creature:CanOpportunityAttack(observerToken, moverToken)
    if not g_baseCanOpportunityAttack(self, observerToken, moverToken) then
        return false
    end

    if not (EncounterOfTheWeekGame.IsEotwGame() or EncounterOfTheWeekGame.IsTestRunning()) then
        return true
    end

    if m_oaBystanderNames == nil or m_oaBystanderUpdate ~= dmhub.ngameupdate then
        m_oaBystanderNames = BystanderNames()
        m_oaBystanderUpdate = dmhub.ngameupdate
    end
    if EncounterOfTheWeekGame.IsBystander(observerToken, m_oaBystanderNames)
        or EncounterOfTheWeekGame.IsBystander(moverToken, m_oaBystanderNames) then
        return false
    end
    return true
end

--Everything on the map sorted into sides for the initiative roll: heroes
--(IsHero) vs monsters. Returns nil while either side is empty -- the caller
--retries on a later tick rather than burning its run-once. Bystanders the
--script names (hostages to rescue) are left out of both sides: they take no
--turns, and a monster AI with no initiative entry for them never attacks them.
local function GatherCombatSides()
    local playerTokens = {}
    local monsterTokens = {}
    local bystanders = BystanderNames()
    for _,token in ipairs(dmhub.allTokens) do
        if token.valid and token.properties ~= nil and not EncounterOfTheWeekGame.IsBystander(token, bystanders) then
            local isHero = false
            pcall(function() isHero = token.properties:IsHero() end)
            if isHero then
                playerTokens[#playerTokens+1] = token
            elseif token.playerControlled then
                --a monster that joined a hero during the montage (owned by
                --the player) fights on the heroes' side.
                local isMonster = false
                pcall(function() isMonster = token.properties:IsMonster() end)
                if isMonster then
                    playerTokens[#playerTokens+1] = token
                end
            else
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
--options.forceHeroes: the heroes go first, no die (the arrangement's
--fallback when the banner's continuation was lost); options.forceResult:
--"heroes" | "monsters" go first, no die (a die that already landed, see
--RecoverLostCombatStart); options.noArrange: no arrangement hold.
local function StartEncounterCombat(sides, options)
    options = options or {}
    local encounterEntry = FindMapEncounter()
    local encounter = nil
    if encounterEntry ~= nil then
        encounter = encounterEntry.encounter
    end

    --Surprise is read from its OWN sticky flags, not from the initiative
    --outcome: the outcome is last-one-wins, so a montage that handed out
    --"you begin the encounter surprised" and then "you lose initiative"
    --keeps only the second, and deriving surprise from it lost the
    --condition entirely.
    local partySurprised, enemySurprised = nil, nil
    pcall(function()
        partySurprised, enemySurprised = EncounterMontage.GetSurprisedSides()
    end)

    --A montage clause may have decided initiative: "win"/"lose" skip the
    --die. Older cores ignore the extra args and just roll.
    local immediateResult = nil
    local outcome, outcomeEntry = nil, nil
    pcall(function()
        outcome, outcomeEntry = EncounterMontage.GetInitiativeOutcome()
    end)
    if outcome == "win" or outcome == "surprise" then
        immediateResult = "heroes"
    elseif outcome == "lose" or outcome == "surprised" then
        immediateResult = "monsters"
    end
    if outcome ~= nil then
        printf("EotW: montage (%s) decided initiative: %s", tostring(outcomeEntry), tostring(outcome))
    end

    --Being surprised IMPLIES losing the initiative, and it outranks a plain
    --win/lose clause however late that clause landed: "the heroes begin the
    --encounter surprised" and then "the heroes win initiative" must not put
    --a surprised party first. Only a montage that surprised BOTH sides
    --falls back to the last outcome, there being no side to favour. This
    --holds even under surprise immunity -- the heroes still lose the die,
    --they just do not take the condition (see HasSurpriseImmunity).
    if partySurprised ~= nil and enemySurprised == nil and immediateResult ~= "monsters" then
        printf("EotW: montage (%s) surprised the heroes; they lose the initiative", tostring(partySurprised.entryName))
        immediateResult = "monsters"
    elseif enemySurprised ~= nil and partySurprised == nil and immediateResult ~= "heroes" then
        printf("EotW: montage (%s) surprised the enemy; the heroes win the initiative", tostring(enemySurprised.entryName))
        immediateResult = "heroes"
    end

    --The heroes already took the condition when the clause landed
    --(EncounterMontage applies it on the spot); re-applying here is
    --idempotent and catches montage allies, who did not exist yet.
    local surprisedTokens = nil
    if partySurprised ~= nil then
        --"You cannot be surprised" (a montage boon): the heroes still lose
        --the initiative, but nobody on their side takes the condition.
        local immune, immuneEntry = false, nil
        pcall(function() immune, immuneEntry = EncounterMontage.HasSurpriseImmunity() end)
        if immune then
            printf("EotW: montage (%s) made the party immune to Surprised; they lose initiative only", tostring(immuneEntry))
        else
            surprisedTokens = surprisedTokens or {}
            for _, token in ipairs(sides.playerTokens) do
                surprisedTokens[#surprisedTokens + 1] = token
            end
            printf("EotW: montage (%s) surprised the heroes", tostring(partySurprised.entryName))
        end
    end
    if enemySurprised ~= nil then
        surprisedTokens = surprisedTokens or {}
        for _, token in ipairs(sides.monsterTokens) do
            surprisedTokens[#surprisedTokens + 1] = token
        end
        printf("EotW: montage (%s) surprised the enemy", tostring(enemySurprised.entryName))
    end

    if options.forceHeroes then
        immediateResult = "heroes"
    elseif options.forceResult == "heroes" or options.forceResult == "monsters" then
        immediateResult = options.forceResult
    end

    --Only a party handed the initiative with no die gets the arrangement
    --pause. When the die is rolled the heroes arrange themselves (still
    --confined to the start area) while the banner waits for someone to roll.
    local holdBeforeQueue = nil
    if immediateResult == "heroes" and not options.noArrange then
        holdBeforeQueue = HoldForArrangement
    end

    --elevated: the surprised condition goes on monsters too, and the host
    --is a player in an EotW game.
    ElevateToHostPermissions()
    local ok, started, err = pcall(function()
        return Encounter.StartCombatWithTokens{
            playerTokens = sides.playerTokens,
            monsterTokens = sides.monsterTokens,
            encounter = encounter,
            immediateResult = immediateResult,
            surprisedTokens = surprisedTokens,
            holdBeforeQueue = holdBeforeQueue,
        }
    end)
    DropHostPermissions()
    if not ok then
        printf("EotW: combat start unavailable: %s", tostring(started))
    elseif started ~= true then
        printf("EotW: combat did not start: %s", tostring(err))
    else
        printf("EotW: Draw Steel! %d heroes vs %d monsters", #sides.playerTokens, #sides.monsterTokens)
    end
end

--Host, every pre-combat tick: while the heroes are arranging, wait; once
--everyone is ready (or the time is up) start the held combat. Returns true
--while the arrangement owns the tick (the script beats must not run).
local function ArrangeHostTick()
    local state = ArrangeState()
    if state == nil or state.phase ~= "arranging" then
        return false
    end
    if not ArrangeComplete(state) then
        return true
    end
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    doc.data.arrange.phase = "done"
    doc.data.arrange.endedAt = dmhub.serverTime
    doc:CompleteChange("Encounter of the Week: the heroes are in position", {undoable = false})

    local begin = m_arrangeBegin
    m_arrangeBegin = nil
    if begin ~= nil then
        printf("EotW: the heroes are in position; Draw Steel!")
        begin()
    else
        --the banner's continuation died with a Lua reload: start again,
        --the heroes first, with no second arrangement.
        printf("EotW: the arrangement's combat start was lost; starting combat again with the heroes first")
        local sides = GatherCombatSides()
        if sides ~= nil then
            StartEncounterCombat(sides, { forceHeroes = true, noArrange = true })
        end
    end
    return true
end

--The encounter beat starts combat only once (a RunOnce watermark), so a Draw
--Steel banner that never creates the initiative queue -- its controller torn
--down mid-roll (KPM5CV7T), or killed by a Lua reload -- left the fight unable
--to begin, even after reloading. Host, every pre-combat tick after that
--start: once no banner has been on screen for LOST_START_GRACE seconds and
--there is still no queue, start combat again, keeping the side the die
--already chose when one landed.
local LOST_START_GRACE = 6
local LOST_START_RETRY = 20
local m_lostStartSince = nil
local m_lostStartTried = nil

local function RecoverLostCombatStart(sides)
    --a core without the banner queries: no way to tell a live roll from a
    --lost one, so never restart.
    local ok, bannerActive = pcall(function() return Encounter.DrawSteelBannerActive() end)
    if not ok then
        return
    end
    local arrange = ArrangeState()
    if bannerActive or (arrange ~= nil and arrange.phase == "arranging") then
        m_lostStartSince = nil
        return
    end

    local now = dmhub.Time()
    if m_lostStartSince == nil then
        m_lostStartSince = now
        return
    end
    if now - m_lostStartSince < LOST_START_GRACE then
        return
    end
    if m_lostStartTried ~= nil and now - m_lostStartTried < LOST_START_RETRY then
        return
    end
    m_lostStartTried = now
    m_lostStartSince = nil

    local outcome = nil
    pcall(function() outcome = Encounter.DrawSteelRollOutcome(sides.playerTokens) end)
    if outcome ~= nil then
        --the die was rolled; no arrangement, as for any rolled initiative.
        printf("EotW: combat never started after the Draw Steel roll; starting it now with the %s first", outcome)
        StartEncounterCombat(sides, { forceResult = outcome, noArrange = true })
    else
        printf("EotW: combat never started; showing the Draw Steel banner again")
        StartEncounterCombat(sides)
    end
end

--- dev driver: the encounter beat in an authoring game ---------------------
--/eotwencounter start runs the "# Encounter" beat outside a real EotW game,
--the way the host tick would: the setup instructions, the spawn (for the
--staging "numheroes" count), pending zone and object reveals, then Draw
--Steel through StartEncounterCombat -- so the montage's initiative outcome,
--the bystanders, the arrangement pause and the encounter's own scripts all
--run. The Director plays the party-owned heroes and starts the Monster AI.
--/eotwmontage reset puts the map back.
local function DevEncounterStart()
    local montage = rawget(_G, "EncounterMontage")
    if montage == nil then
        print("EotW encounter: the EotW code is not loaded")
        return
    end
    local q = dmhub.initiativeQueue
    if q ~= nil and not q.hidden then
        print("EotW encounter: combat is already running")
        return
    end
    local script = montage.FindMapScript(true)
    local beat = nil
    for _, b in ipairs(script.parse.beats or {}) do
        if b.kind == "encounter" then
            beat = b
            break
        end
    end
    if beat == nil then
        print("EotW encounter: this map's script has no # Encounter beat")
        return
    end
    local zones = rawget(_G, "EncounterZones")
    if zones ~= nil then
        pcall(zones.RunEncounterSetup, beat)
    end
    local numHeroes = tonumber(dmhub.GetSettingValue("numheroes")) or 5
    local ok, err = EncounterOfTheWeekGame.SpawnEncounterMonsters(numHeroes)
    if not ok then
        printf("EotW encounter: spawn failed: %s", tostring(err))
        return
    end
    if zones ~= nil then
        pcall(zones.ApplyPendingReveals)
        if zones.ApplyPendingObjectReveals ~= nil then
            pcall(zones.ApplyPendingObjectReveals)
        end
    end
    m_devEncounter = true
    dmhub.Coroutine(function()
        --the stage (if a driver left one up) goes first, then the spawned
        --monsters need a moment to appear in allTokens.
        for _ = 1, 50 do
            local gone = true
            pcall(function() gone = montage.DismissStage() end)
            if gone then
                break
            end
            coroutine.yield(0.2)
        end
        local sides = nil
        for _ = 1, 50 do
            sides = GatherCombatSides()
            if sides ~= nil then
                break
            end
            coroutine.yield(0.2)
        end
        if sides == nil then
            print("EotW encounter: no heroes or no monsters on the map")
            m_devEncounter = false
            return
        end
        StartEncounterCombat(sides)
        --stand in for the host tick's arrangement handling until the
        --initiative queue exists.
        while not mod.unloaded and m_devEncounter do
            local queue = dmhub.initiativeQueue
            if queue ~= nil and not queue.hidden then
                break
            end
            pcall(ArrangeHostTick)
            coroutine.yield(0.5)
        end
        m_devEncounter = false
        print("EotW encounter: combat is live")
    end)
end

pcall(function()
    Commands.RegisterMacro{
        name = "eotwencounter",
        summary = "run the Encounter of the Week encounter beat in an authoring game",
        doc = "Usage: /eotwencounter start | stop | state\nstart runs the map script's # Encounter beat here: setup instructions, the monster spawn for the numheroes setting, pending reveals, then Draw Steel -- including the montage's initiative outcome, bystanders and the heroes' arrangement pause when they win the initiative. stop abandons a pending arrangement. state prints the arrangement and the bystanders. /eotwmontage reset puts the map back.",
        command = function(str)
            local arg = string.lower(string.gsub(str or "", "^%s*(.-)%s*$", "%1"))
            if arg == "start" then
                DevEncounterStart()
            elseif arg == "stop" then
                m_devEncounter = false
                m_arrangeBegin = nil
                local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
                doc:BeginChange()
                doc.data.arrange = nil
                doc:CompleteChange("Encounter of the Week: arrangement abandoned", {undoable = false})
                print("EotW encounter: stopped")
            else
                local names = BystanderNames()
                local tokens = {}
                for _, token in ipairs(dmhub.allTokens) do
                    if EncounterOfTheWeekGame.IsBystander(token, names) then
                        tokens[#tokens + 1] = tostring(token.name)
                    end
                end
                print(json{ arrange = ArrangeState(), bystanderNames = names, bystanders = tokens,
                    devEncounter = m_devEncounter, holding = m_arrangeBegin ~= nil })
            end
        end,
    }
end)

--pcall-guarded AI control: an EotW game always bundles the Monster AI
--codemod, but never let a version mismatch break the host tick.
local function EnsureAIRunning()
    pcall(function()
        if not MonsterAI.IsAIRunning() then
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

--This client is no longer the elected host (the map script's onLoseHost):
--its Monster AI stops; the new host's tick starts its own.
function EncounterOfTheWeekGame.MapScriptLoseHost(ctx)
    printf("EotW: this client is no longer the host")
    EnsureAIStopped()
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

--When the outcome condition was FIRST observed met (whether or not clients
--were still ability-busy), so the award can linger a dramatic beat after the
--killing blow before the banner takes over. This runs concurrently with the
--prompt wait above -- a fight whose final prompts take longer than the
--linger pays no extra delay. Reset whenever the condition reads unmet.
local m_outcomeMetTime = nil
local OUTCOME_LINGER_SECONDS = 5

--Heroes in the initiative queue that are not dead. Dying heroes count as
--living (see the defeat check below); a hero with no token on the map is
--ignored, like CountLiveCombatants does.
local function CountLivingHeroes(queue)
    local count = 0
    local seen = {}
    for initiativeid, _ in pairs(queue.entries) do
        local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
        for _, token in ipairs(tokens or {}) do
            if token ~= nil and not seen[token.charid] then
                seen[token.charid] = true
                local props = token.properties
                if props ~= nil and props:IsHero() and not props:IsDead() then
                    count = count + 1
                end
            end
        end
    end
    return count
end

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
        --full Director teardown on their behalf -- after the Victory award,
        --which must never be skipped by a quick Proceed.
        local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
        if outcome == "victory" then
            AutoAwardVictories(live, doc.data.proceedRequested ~= nil)
        end
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
    --the script's "Victory: every Dwarf on the map is defeated" line wins
    --too, whatever the encounter's own condition says.
    if not victory then
        local reinforcements = rawget(_G, "EncounterReinforcements")
        if reinforcements ~= nil then
            pcall(function() victory = reinforcements.ClearMapVictory() == true end)
        end
    end

    local defeat = false
    if not victory then
        --defeat = a script-declared defeat condition, or every hero DEAD.
        --Deliberately not CountLiveCombatants: that counts hitpoints > 0,
        --so a DYING hero (0 or less, above the death threshold) reads as
        --down there -- but a dying hero still takes turns in Draw Steel
        --and can win the fight, so only actual deaths count here.
        pcall(function()
            if live:CheckDefeat() == true then
                defeat = true
            elseif CountLivingHeroes(queue) <= 0 then
                defeat = true
            end
        end)
    end

    if not victory and not defeat then
        m_awardHoldTicks = 0
        m_outcomeMetTime = nil
        return
    end

    --the condition is met: stamp when we first saw it (the linger clock runs
    --from here, busy or not), then wait until no client has an ability
    --prompting (local check is live; remote clients via their mirror
    --stamps), and hold for AWARD_HOLD_TICKS consecutive idle ticks.
    if m_outcomeMetTime == nil then
        m_outcomeMetTime = dmhub.serverTime
    end

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
    --cap the counter so later ticks re-enter here while the linger holds.
    m_awardHoldTicks = AWARD_HOLD_TICKS

    --idle hold satisfied; also let the moment breathe -- the banner waits
    --OUTCOME_LINGER_SECONDS from the killing blow. math.abs so a serverTime
    --rebase releases the wait rather than wedging it.
    if math.abs(dmhub.serverTime - m_outcomeMetTime) < OUTCOME_LINGER_SECONDS then
        return
    end

    m_awardHoldTicks = 0
    m_outcomeMetTime = nil

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

--Game-scoped settings every EotW game forces to a fixed value.
--
--Strict rules: every "Strict..." Rules Enforcement option, plus the
--engine's "Strictly Enforce Movement Rules". All of these gate on
--(not dmhub.isDM) -- which, under player-host mode, reads false on the
--HOST too, so the rules bind every human in the game. The Monster AI is
--unaffected: its capability paths read IsDMOrPlayerHost.
--
--Automatic Rule Adjudication sits in the same section but is not a
--restriction: the game makes table calls (e.g. Black Ash Teleport's "do you
--have cover to hide?") itself, for everyone, so a directorless game never
--leaves them to the players' honour.
--
--Monster stamina: players always see every monster's stamina BAR, but
--not the exact amount. The "lifebar" status bar reaches a player through
--its showToEnemies rung (TokenUI.lua ShouldShowElement), which
--enemystambardisplay turns off at its "none" default; "bar" shows the bar
--with no value or percentage, and the minion squad HUD (MCDMMinion.lua)
--reads the same setting. Bars are shown outside combat too
--(hpbarsonlyincombat off) so the monsters' stamina is visible from the
--moment the heroes arrive, not only once the map script opens initiative.
--
--Monster Info: the feature is always on in EotW (monsterinfo, declared in
--Draw Steel Core Rules/MonsterKnowledge.lua) with automatic learning
--(monsterinfoautolearn), so players learn the monsters' stat blocks by
--fighting them -- the one sanctioned route to exact stamina (third kill).
--
--Game-scoped settings are only editable from the dmonly Game settings tab,
--so nobody in a player-host game can flip them; the host tick re-asserts
--them regardless.
local g_forcedGameSettings = {
    { id = "strictmovementrules", value = true },  --Strictly Enforce Movement Rules (engine)
    { id = "strict:movement", value = true },      --Strictly Enforce Forced Movement Rules
    { id = "strict:targeting", value = true },     --Strictly Enforce Targeting Rules
    { id = "strict:resources", value = true },     --Strictly Enforce Action Economy and Resource Costs
    { id = "strict:inventory", value = true },     --Strict Inventory Management
    { id = "strict:rolls", value = true },         --Strictly Enforce Rolls
    { id = "strict:autoadjudicate", value = true }, --Automatic Rule Adjudication
    { id = "enemystambardisplay", value = "bar" }, --enemy stamina bars: bar only, no value
    { id = "hpbarsonlyincombat", value = false },  --stamina bars shown outside combat too
    { id = "monsterinfo", value = true },          --Monster Info: players learn monster stat blocks
    { id = "monsterinfoautolearn", value = true }, --...automatically, from combat events
}

--Force every forced game setting to its value, writing only the ones not
--already there (these are game-scoped settings, so each write replicates).
--
--"enemystambardisplay" is the one that is not a constant: a week that
--unlocked Intelligence sells the enemy's health on the Tactical Preparation
--screen, so the level the party bought decides what the bars show (nothing
--at all until they buy the first notch). Weeks without the feature keep the
--game mode's own "bar only" (EncounterPrep.EnemyStaminaDisplay).
local function EnforceStrictRules()
    for _,entry in ipairs(g_forcedGameSettings) do
        local value = entry.value
        if entry.id == "enemystambardisplay" then
            local prep = rawget(_G, "EncounterPrep")
            if prep ~= nil then
                pcall(function() value = prep.EnemyStaminaDisplay() end)
            end
        end
        if dmhub.GetSettingValue(entry.id) ~= value then
            dmhub.SetSettingValue(entry.id, value)
        end
    end
end

--- the script's beats --------------------------------------------------

--The current beat index, host-stamped in the montage runtime's document so
--late joiners and resumes agree on where the script is.
local function GetBeatIndex()
    local index = 1
    pcall(function()
        local v = EncounterMontage.GetDoc().data.beat
        if type(v) == "number" then
            index = v
        end
    end)
    return index
end

local function SetBeatIndex(index)
    local doc = EncounterMontage.GetDoc()
    doc:BeginChange()
    doc.data.beat = index
    doc:CompleteChange("Encounter of the Week: script beat", { undoable = false })
end

--Host, every tick before combat: play the map's script. Each "# Montage"
--beat runs through EncounterMontage until it reports done; the
--"# Encounter" beat spawns the journal encounter's monsters (idempotent)
--and starts combat once, exactly as the pre-script flow did. A script with
--no montage therefore behaves as before, except that the spawn now happens
--here, on the first tick after every player has arrived, instead of during
--the host's arrival setup. Unknown beats are skipped.
--Finish a stage beat (a montage or a narrative -- the two that own the
--full-screen stage) and open the next one. When the next beat is also a
--stage beat we do NOT hide: we seed it and present it under the same dialog
--id, so the stage's content swaps in place (and, because both beats usually
--name the same [[scene]], the backdrop does not even blink). Its first tick
--runs here too, so the new beat opens on its first section/round instead of
--sitting in "arriving" until the next tick. Only a beat that hands back to
--the map -- the encounter, or the end of the script -- hides the stage.
local function AdvanceFromStageBeat(script, index, montage, narrative)
    local nextBeat = script.parse.beats[index + 1]

    --Order matters: SEED the next beat's state first, and only then stamp the
    --beat index. The stage picks its body from the beat index, so stamping it
    --first would leave one refresh in which the new body renders the PREVIOUS
    --beat's state -- a flash of the wrong section. Seeding first just means
    --the old body draws its own (finished) state for one more refresh, which
    --is what is already on screen.
    if nextBeat ~= nil and nextBeat.kind == "montage" then
        montage.Begin(script, nextBeat, index + 1)
        SetBeatIndex(index + 1)
        pcall(montage.HostTick, script, nextBeat, index + 1)
        return
    end
    if nextBeat ~= nil and nextBeat.kind == "narrative" and narrative ~= nil then
        narrative.Begin(script, nextBeat, index + 1)
        SetBeatIndex(index + 1)
        pcall(narrative.HostTick, script, nextBeat, index + 1)
        return
    end

    --Not a stage beat: the surface has to go, but NOT here. The encounter
    --beat dismisses it once its monsters are placed, so the spawn happens
    --behind the scene and the dissolve reveals a battlefield that is already
    --set; a script that simply ends dismisses it from the "no such beat"
    --branch of RunScriptBeat. Hiding here would snap it away instead.
    SetBeatIndex(index + 1)
end

local m_reportedBeat = nil
local function RunScriptBeat(ctx)
    local montage = rawget(_G, "EncounterMontage")
    if montage == nil then
        --older module without the montage runtime: the pre-script flow.
        local sides = GatherCombatSides()
        if sides == nil then
            return
        end
        ctx:RunOnce("draw-steel", function()
            StartEncounterCombat(sides)
        end)
        return
    end

    local script = montage.FindMapScript()
    local beats = script.parse.beats
    local index = GetBeatIndex()
    local beat = beats[index]
    if beat == nil then
        --the script has run out: dissolve the stage away if it is still up.
        pcall(montage.DismissStage)
        if m_reportedBeat ~= index then
            m_reportedBeat = index
            if #beats == 0 then
                printf("EotW: this map has no script and no encounter; nothing to run")
            else
                printf("EotW: the script has ended (beat %d of %d) without an encounter", index, #beats)
            end
        end
        return
    end

    if beat.kind == "montage" then
        local status = montage.HostTick(script, beat, index)
        if status == "done" then
            printf("EotW: montage beat %d complete", index)
            AdvanceFromStageBeat(script, index, montage, rawget(_G, "EncounterNarrative"))
        end
        return
    end

    if beat.kind == "narrative" then
        local narrative = rawget(_G, "EncounterNarrative")
        if narrative == nil then
            --an older module without the narrative runtime: skip the beat
            --rather than stalling the script forever.
            printf("EotW: skipping narrative beat %d (this client has no narrative runtime)", index)
            SetBeatIndex(index + 1)
            return
        end
        local status = narrative.HostTick(script, beat, index)
        if status == "done" then
            printf("EotW: narrative beat %d complete", index)
            AdvanceFromStageBeat(script, index, montage, narrative)
        end
        return
    end

    if beat.kind ~= "encounter" then
        printf("EotW: skipping unknown script beat %d (%s)", index, tostring(beat.title))
        SetBeatIndex(index + 1)
        return
    end

    --the encounter beat. First, when the week unlocked Intelligence, the
    --Tactical Preparation screen: the party spends what they learned on
    --surprise, the traps and the enemy's health. It runs BEFORE the setup
    --below because what they buy decides it -- a trap reveal is banked here
    --and applied with the rest when the zones go down.
    local prep = rawget(_G, "EncounterPrep")
    if prep ~= nil and prep.Required() then
        local status = prep.HostTick(script, beat, index)
        if status ~= "done" then
            return
        end
    end

    --then the script's setup instructions (traps placed in their zones, the
    --spare zones trimmed away) and the spawn (idempotent -- already-present
    --monsters are left alone), then Draw Steel once both sides exist.
    local zones = rawget(_G, "EncounterZones")
    if zones ~= nil then
        local okSetup, errSetup = pcall(zones.RunEncounterSetup, beat)
        if not okSetup then
            printf("EotW: encounter zone setup failed: %s", tostring(errSetup))
        end
    end
    local numHeroes = tonumber(dmhub.GetSettingValue("numheroes")) or 5
    local ok, err = EncounterOfTheWeekGame.SpawnEncounterMonsters(numHeroes)
    if not ok then
        if m_reportedBeat ~= index then
            m_reportedBeat = index
            printf("EotW: encounter spawn failed: %s", tostring(err))
        end
        return
    end

    local sides = GatherCombatSides()
    if sides == nil then
        return
    end

    --A montage that revealed the traps: the zones turn player-visible now,
    --behind the stage, so they are on the map when it comes through.
    if zones ~= nil then
        pcall(zones.ApplyPendingReveals)
        --and any object a clause revealed ("reveal the Treasure Chest
        --object") switches on with them.
        if zones.ApplyPendingObjectReveals ~= nil then
            pcall(zones.ApplyPendingObjectReveals)
        end
    end

    --The monsters were placed behind the stage, so nothing popped in on a bare
    --map. Now dissolve the stage away and let the battlefield come through it;
    --only once it is really gone does Draw Steel roll, so the banner plays
    --over the map rather than over a scene nobody can see past.
    if not montage.DismissStage() then
        return
    end

    local started = ctx:RunOnce(string.format("draw-steel-%d", index), function()
        StartEncounterCombat(sides)
    end)
    if not started then
        RecoverLostCombatStart(sides)
    end
end

--- developer: skip to combat ----------------------------------------------

--The index of the encounter beat a "Skip to Combat" would jump to, or nil
--when there is nothing to skip: the script must be on a montage or narrative
--beat, before combat, with an encounter beat somewhere after it.
local function SkipToCombatTarget()
    if not (EncounterOfTheWeekGame.IsEotwGame() or EncounterOfTheWeekGame.IsTestRunning()) then
        return nil
    end
    local queue = dmhub.initiativeQueue
    if queue ~= nil and not queue.hidden then
        return nil
    end
    local montage = rawget(_G, "EncounterMontage")
    if montage == nil then
        return nil
    end
    local target = nil
    pcall(function()
        local beats = montage.FindMapScript().parse.beats
        local index = GetBeatIndex()
        local beat = beats[index]
        if beat == nil or (beat.kind ~= "montage" and beat.kind ~= "narrative") then
            return
        end
        for i = index + 1, #beats do
            if beats[i].kind == "encounter" then
                target = i
                return
            end
        end
    end)
    return target
end

--Abandon the montage/narrative where it stands and point the script at its
--encounter beat. The host tick then plays that beat the normal way (prep,
--trap setup, spawn, stage dissolve, Draw Steel). Consequences and rewards of
--the skipped beats are NOT applied.
function EncounterOfTheWeekGame.DevSkipToCombat()
    local target = SkipToCombatTarget()
    if target == nil then
        print("EotW: nothing to skip -- the script is not on a montage or narrative before its encounter")
        return false
    end
    local doc = EncounterMontage.GetDoc()
    doc:BeginChange()
    --mark the stage beats finished (and drop any pending roll) so no client
    --keeps treating them as live.
    if type(doc.data.montage) == "table" then
        doc.data.montage.phase = "done"
        doc.data.montage.turn = nil
    end
    if type(doc.data.narrative) == "table" then
        doc.data.narrative.phase = "done"
    end
    doc.data.beat = target
    doc:CompleteChange("Encounter of the Week: skip to combat", { undoable = false })
    printf("EotW: developer skipped to the encounter beat (%d)", target)
    return true
end

--Rows for the title bar's Developer menu (CodexTitleBar.lua appends them).
function EncounterOfTheWeekGame.DeveloperMenuItems()
    if not devmode() or SkipToCombatTarget() == nil then
        return {}
    end
    return {
        {
            text = "Skip to Combat",
            click = function()
                EncounterOfTheWeekGame.DevSkipToCombat()
            end,
        },
    }
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
    --a running authoring test plays wherever the election puts the host
    --tick, even on a client that is not the tester.
    if not (EncounterOfTheWeekGame.IsEotwGame() or EncounterOfTheWeekGame.IsTestRunning()) then
        return
    end

    --keep the forced game settings (strict rules, monster stamina
    --visibility) asserted for the life of the game (no-op writes are
    --skipped, so this is free when nothing changed).
    EnforceStrictRules()

    --a player who leaves hands their heroes to the host until they return
    --(EncounterPresence.lua). Not in an authoring test: one player.
    local presence = rawget(_G, "EncounterPresence")
    if presence ~= nil and not EncounterOfTheWeekGame.IsTestRunning() then
        local ok, err = pcall(presence.HostTick)
        if not ok then
            printf("EotW: presence tick failed: %s", tostring(err))
        end
    end

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
        --surges the montage banked can only be granted with a live queue
        --(they are a clearOutsideOfCombat resource); this is a no-op once
        --the bank is empty.
        pcall(EncounterMontage.ApplyPendingCombatBoons)
        EnsureAIRunning()
        CheckEncounterOutcome(queue)
        --the script's reinforcements arrive at the start of their rounds --
        --but never while a won or lost fight is waiting for its screen, so
        --clearing the map just before a new round still wins.
        local reinforcements = rawget(_G, "EncounterReinforcements")
        if reinforcements ~= nil and m_outcomeMetTime == nil then
            ---@cast queue -nil
            local ok, err = pcall(function()
                local live = queue:try_get("liveEncounter")
                if type(live) ~= "table" then
                    live = nil
                end
                if live == nil or live:GetAwardedOutcome() == nil then
                    reinforcements.HostTick(queue, live)
                end
            end)
            if not ok then
                printf("EotW: reinforcements tick failed: %s", tostring(err))
            end
        end
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
    --heroes on the map, then play the map's script beat by beat (see
    --RunScriptBeat): montages first, then the encounter beat spawns the
    --monsters and rolls into combat exactly once.
    if not EncounterOfTheWeekGame.AllPlayersArrived() then
        return
    end

    --what every hero carries before the script hands anything out, so the
    --end of the game knows what treasure they won.
    pcall(EnsureArrivalItems)

    --the heroes won the initiative and are arranging themselves: the held
    --combat starts from here once they are ready.
    local arranging, arrangeResult = pcall(ArrangeHostTick)
    if not arranging then
        printf("EotW: arrangement tick failed: %s", tostring(arrangeResult))
    elseif arrangeResult then
        return
    end

    RunScriptBeat(ctx)
end

--- lobby ready signal -------------------------------------------------

--Tell the lobby this game is fully set up: the server flips the roster
--record "launched" -> "ready". Waiting members only enter the game when
--they see "ready" (the host enters on "launched" and runs setup first),
--so no joiner ever loads a half-initialized game. Safe to call when no
--roster record exists (a resume): the server answers "not registered",
--which we just log.
--Host only, at setup: the members may set up now. Written once the encounter
--map is chosen and stamped and the opening stage beat has begun, which is
--everything a member's own setup reads from the host. With a fast launch the
--members entered alongside the host and wait for this (WaitForHostSetup).
local function RecordSetupReady()
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    if doc.data.setupReady ~= nil then
        return
    end
    doc:BeginChange()
    doc.data.setupReady = dmhub.serverTime
    doc:CompleteChange("Encounter of the Week: setup ready", {undoable = false})
end

--Members of a fast launch: wait (behind the held loading screen) until the
--host has stamped setupReady. The engine's loading screen hold times out
--after 20s unless renewed, so renew it while waiting. Gives up after
--HOST_SETUP_TIMEOUT_SECONDS and carries on, as a late joiner would.
--Installs this player's switched-on Hero modules (HeroModules.lua) into the
--game, from inside the arrival coroutine. Each client installs its own, so a
--member's modules arrive with the member. Renews the loading screen hold while
--it waits; HeroModules gives up after HERO_MODULES_TIMEOUT_SECONDS.
local HERO_MODULES_TIMEOUT_SECONDS = 20
local function InstallMyHeroModules()
    local heroModules = rawget(_G, "HeroModules")
    if heroModules == nil or heroModules.InstallIntoGame == nil then
        return
    end
    local done = false
    heroModules.InstallIntoGame(function()
        done = true
    end, HERO_MODULES_TIMEOUT_SECONDS)
    local sinceRenew = 0
    while not done and not mod.unloaded do
        if sinceRenew >= 5 then
            sinceRenew = 0
            pcall(function() dmhub.HoldLoadingScreen() end)
        end
        coroutine.yield(0.1)
        sinceRenew = sinceRenew + 0.1
    end
end

local HOST_SETUP_TIMEOUT_SECONDS = 120
local function WaitForHostSetup()
    local waited = 0
    local sinceRenew = 0
    while waited < HOST_SETUP_TIMEOUT_SECONDS do
        if mod.unloaded then
            return
        end
        local ready = false
        pcall(function()
            ready = mod:GetDocumentSnapshot(STATE_DOC_ID).data.setupReady ~= nil
        end)
        if ready then
            return
        end
        if sinceRenew >= 5 then
            sinceRenew = 0
            pcall(function() dmhub.HoldLoadingScreen() end)
        end
        coroutine.yield(0.1)
        waited = waited + 0.1
        sinceRenew = sinceRenew + 0.1
    end
    printf("EotW: the host's setup was not ready after %d seconds; continuing", HOST_SETUP_TIMEOUT_SECONDS)
end

local function SignalGameReady()
    local gameid = dmhub.gameid
    EotwProf("host: SignalGameReady (opening lobby connection)")
    SendLobbyRequest("ready-game", { gameid = gameid }, function(ok, result)
        EotwProf("host: ready-game acked ok=%s", tostring(ok))
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
--  encounterMap: the encounter KEY the host chose at create time (see
--                ParseEncounterKey; from the lobby roster record; nil/"" =
--                not chosen, so the host's stamp in the state doc or the
--                default map is used).
--Every member first makes sure they are on the chosen encounter map, then
--places their own heroes and records their arrival; the host
--additionally stamps the game state, sets the "Number of Heroes" setting,
--spawns the encounter monsters, and attaches the EotW map script that then
--runs the encounter (combat entry + Monster AI).
--- the loading-screen hold ---------------------------------------------

--The titlescreen holds the loading screen for every EotW entry
--(dmhub.HoldLoadingScreen, before lobby:EnterGame), so the engine runs the
--arrival callback -- and so SetupOnArrival -- behind it. Someone on this
--side has to let it go: the montage stage does, in its create event, when
--the week opens on a montage; otherwise SetupOnArrival does, right after
--hero placement. The engine's 20s timeout backstops both.
local function ReleaseLoadingScreen()
    pcall(function() dmhub.ReleaseLoadingScreen() end)
end

--How long a client's loading screen waits on the rest of the party before
--revealing the game anyway (a player who never arrives must not trap the
--others behind it).
local REVEAL_WAIT_MAX_SECONDS = 45

--Host: open the opening stage beat the moment the last player arrives,
--rather than on the map script's tick -- the script driver takes a few of
--its 0.5s ticks to elect this client and run its first host tick, and every
--player's loading screen is waiting on the opening (RevealReady). Does what
--that tick would (the arrival items, then the beat's HostTick, which moves
--it out of "arriving" and applies its unlocks); later ticks carry on as
--normal. Gives up quietly if the map script opens it first.
local function OpenOpeningBeatWhenPartyIn()
    local waited = 0
    while waited < REVEAL_WAIT_MAX_SECONDS and not mod.unloaded do
        if not EncounterOfTheWeekGame.OpeningStageArriving() then
            return
        end
        if EncounterOfTheWeekGame.AllPlayersArrived() then
            pcall(EnsureArrivalItems)
            local ok, err = pcall(function()
                local montage = rawget(_G, "EncounterMontage")
                local narrative = rawget(_G, "EncounterNarrative")
                local script = montage.FindMapScript()
                local index = GetBeatIndex()
                local beat = script.parse.beats[index]
                if beat == nil then
                    return
                end
                if beat.kind == "montage" then
                    montage.HostTick(script, beat, index)
                elseif beat.kind == "narrative" and narrative ~= nil then
                    narrative.HostTick(script, beat, index)
                end
            end)
            if not ok then
                printf("EotW: could not open the opening beat: %s", tostring(err))
            end
            return
        end
        coroutine.yield(0.1)
        waited = waited + 0.1
    end
end

--No opening stage: release the held loading screen once every expected
--player has arrived (or after REVEAL_WAIT_MAX_SECONDS), renewing the hold
--while waiting.
local function WaitForPartyThenRelease()
    local waited = 0
    local sinceRenew = 0
    while waited < REVEAL_WAIT_MAX_SECONDS and not mod.unloaded do
        local arrived = false
        pcall(function() arrived = EncounterOfTheWeekGame.AllPlayersArrived() end)
        if arrived then
            break
        end
        if sinceRenew >= 5 then
            sinceRenew = 0
            pcall(function() dmhub.HoldLoadingScreen() end)
        end
        coroutine.yield(0.1)
        waited = waited + 0.1
        sinceRenew = sinceRenew + 0.1
    end
    EotwProf("party in; releasing the loading screen")
    ReleaseLoadingScreen()
end

--True when a script stage is (or is about to be) on screen for this client:
--a live montage or narrative state whose beat belongs to this map's script.
--(Forward-declared above UpdateStartZoneConfinement, which also needs it.)
MontageStageExpected = function()
    local expected = false
    pcall(function()
        local montage = rawget(_G, "EncounterMontage")
        if montage ~= nil then
            local m = montage.GetState()
            if m ~= nil and m.phase ~= "done" and montage.CurrentBeat() ~= nil then
                expected = true
            end
        end
        local narrative = rawget(_G, "EncounterNarrative")
        if narrative ~= nil then
            local n = narrative.GetState()
            if n ~= nil and n.phase ~= "done" and narrative.CurrentBeat() ~= nil then
                expected = true
            end
        end
    end)
    return expected
end

--Host, during arrival setup and BEFORE its heroes are placed: if the map's
--script opens on a montage or a narrative and the script has not started,
--seed and present it (Begin -- the "arriving" phase, which the host tick
--opens once the party is in). Resuming mid-beat re-presents the stage. So
--the stage, not the map, is what every loading screen reveals.
local function BeginOpeningMontage()
    local montage = rawget(_G, "EncounterMontage")
    if montage == nil or montage.Begin == nil then
        return
    end
    local narrative = rawget(_G, "EncounterNarrative")
    local ok, err = pcall(function()
        local m = montage.GetState()
        if m ~= nil and m.phase ~= "done" and montage.CurrentBeat() ~= nil then
            if not montage.IsPresented() then
                montage.Present(m.beatIndex)
            end
            return
        end
        if narrative ~= nil then
            local n = narrative.GetState()
            if n ~= nil and n.phase ~= "done" and narrative.CurrentBeat() ~= nil then
                if not narrative.IsPresented() then
                    narrative.Present(n.beatIndex)
                end
                return
            end
        end
        if m ~= nil or (narrative ~= nil and narrative.GetState() ~= nil) then
            --a finished beat is still on the document: the host tick moves
            --the script on, it does not restart here.
            return
        end
        if GetBeatIndex() ~= 1 then
            return
        end
        local script = montage.FindMapScript(true)
        local beat = script.parse.beats[1]
        if beat == nil then
            return
        end
        if beat.kind == "montage" then
            montage.Begin(script, beat, 1)
        elseif beat.kind == "narrative" and narrative ~= nil then
            narrative.Begin(script, beat, 1)
        end
    end)
    if not ok then
        printf("EotW: could not begin the opening beat: %s", tostring(err))
    end
end

function EncounterOfTheWeekGame.SetupOnArrival(args)
    args = args or {}
    dmhub.Coroutine(function()
        if mod.unloaded then
            ReleaseLoadingScreen()
            return
        end

        EotwProf("SetupOnArrival begin (%s)", IsDMOrPlayerHost() and "host" or "member")

        --what KeepMyArrivalRecorded restores belongs to this game only.
        m_myExpectedUsers = nil
        m_myPlacedHeroes = nil
        --a series' part rides the key; until the host stamps it, this is
        --where ActivePart reads it (a member placing heroes early).
        m_arrivalKey = args.encounterMap

        if IsDMOrPlayerHost() and args.fastLaunch then
            --ready-game goes out as soon as the stage is up; have the lobby
            --connection authenticated by then.
            PrewarmLobbyConnection()
        end

        --a member who entered alongside the host waits for the host's setup
        --stamp: the map choice and the opening stage are the host's. When it
        --already started on the party's map (an official encounter, named
        --at entry), only the stage is outstanding, so it places its heroes
        --first and waits after.
        local waitForHost = not IsDMOrPlayerHost() and args.fastLaunch
        if waitForHost and not OnRequestedEncounterMap(args.encounterMap) then
            WaitForHostSetup()
            EotwProf("member: host setup ready")
            waitForHost = false
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

        --onto the chosen encounter map (a switch waits for the map to load),
        --before any hero placement or Start-zone reads.
        local encounterKey, encounterMapId = EnsureOnEncounterMap(args.encounterMap)
        EotwProf("on encounter map")
        if IsDMOrPlayerHost() then
            --stamp it, so members arriving after the lobby record expires,
            --and every resume, land on the same map.
            RecordEncounterMap(encounterKey, encounterMapId)
            RecordPracticeMode(args.practice)

            --the encounter's region bounds the map from now on (a series'
            --part plays in its own corner of the map). Before any hero lands.
            ApplyPlayRegion()

            --an opening montage goes up before the heroes land, so it is
            --the stage that the held loading screen reveals.
            BeginOpeningMontage()
            EotwProf("host: opening montage begun")

            --the members can set up from here on. Signal ready now rather
            --than after this client's own hero placement and the game-wide
            --writes below, none of which a member waits on.
            RecordSetupReady()
            SignalGameReady()

            --the map script's host tick opens the opening beat once the
            --whole party has arrived; have it running from now, not from the
            --end of this client's own setup.
            AttachMapScript()
        end

        --a hero built with a class or ancestry from one of this player's Hero
        --modules needs the module in this game before it lands.
        InstallMyHeroModules()
        EotwProf("hero modules installed")

        local myPasted, anchor = PlaceMyHeroes(args.heroes, args.clipboardIds)
        RecordCompletedHeroes(args.heroes)
        EotwProf("heroes placed")

        if IsDMOrPlayerHost() then
            local numHeroes = tonumber(args.numHeroes) or 0
            if numHeroes <= 0 then
                --no slot count supplied (resuming an in-progress game with
                --no lobby record): keep the game's existing setting rather
                --than clobbering it with a fresh clamp.
                numHeroes = tonumber(dmhub.GetSettingValue("numheroes")) or 5
            else
                --the numheroes setting only accepts 3..7 (the lobby sends 4..6).
                if numHeroes < 3 then numHeroes = 3 end
                if numHeroes > 7 then numHeroes = 7 end
                dmhub.SetSettingValue("numheroes", numHeroes)
            end

            --the players' party lists the heroes the players brought, and
            --nothing else: park any unclaimed pregen the week's module
            --authored into it with the rest of the pregens. After hero
            --placement, so a hero of this client's is never mistaken for
            --one, and late enough that the module has finished installing.
            SweepPlayersParty()

            --the party starts the session with one Hero Token per hero.
            SeedHeroTokens(numHeroes)

            --the monsters are spawned by the host tick when the script's
            --encounter beat begins (after any montage), not here.

            --there is no Director in an EotW game: every player may control
            --initiative (select turns, advance rounds) for their side.
            dmhub.SetSettingValue("permission:playersinitiative", true)

            --EotW games always strictly enforce the game rules, and
            --players always see the monsters' stamina.
            EnforceStrictRules()
        end

        --arrival is recorded once this client's heroes are on the map (and,
        --on the host, the game-wide settings above are written): once every
        --expected player's arrival is visible, the party is complete, so the
        --host tick opens the opening beat and the map script's combat entry
        --never fires on a half-placed party.
        RecordArrival()
        EotwProf("arrival recorded")
        dmhub.Coroutine(KeepMyArrivalRecorded)

        if waitForHost then
            WaitForHostSetup()
            EotwProf("member: host setup ready")
        end

        if IsDMOrPlayerHost() and MontageStageExpected() then
            dmhub.Coroutine(OpenOpeningBeatWhenPartyIn)
        end

        --another client pasting in the same instant may have landed on the
        --same tiles: spread any pile. After the arrival -- the repair waits a
        --beat for the other clients' pastes, and the opening stage covers
        --the map while it moves anyone.
        UnstackPlacedHeroes(myPasted, anchor)
        EotwProf("unstack done")

        --the loading screen stays up until the whole party is in. With an
        --opening stage, the stage releases it once the beat has opened
        --(EncounterOfTheWeekGame.RevealReady); without one, release once
        --every expected player has arrived.
        if MontageStageExpected() then
            printf("EotW: leaving the loading screen to the montage stage")
        else
            WaitForPartyThenRelease()
        end
        EotwProf("SetupOnArrival done")
    end)
end

--- the authoring test --------------------------------------------------
--The Director of an authoring game plays the encounter on the current map the
--way its players will (EncounterTest.lua holds the menu rows, the hero
--picker and the test bar; this is the machinery):
--
--  1. StartTest parks the request in a global and switches this client into
--     player-host mode (dmhub.playerHostModeForced). That refreshes the game.
--  2. After the refresh, the 1s driver's ConsumePendingTest runs the test's
--     arrival: a clean slate (EncounterMontage.ResetTest), copies of the
--     chosen heroes pasted into the Start zone as this user's own heroes, the
--     settings a real EotW host writes (saved first), the party marked as
--     arrived, the chosen beat started, and the map script attached.
--  3. The test record turns "running": IsEotwGame() is now true on this
--     client, so the EotW interface, the start-zone confinement, the strict
--     rules and the host tick all behave as in a real game.
--  4. EndTest (the test bar, the Game menu, or the end of the encounter)
--     ends any combat, puts the map back (ResetTest, the hero copies deleted,
--     the saved settings and hero tokens restored), clears the record and
--     switches player-host mode off, refreshing back to the Director.

--Where each kind of test starts: the first beat, the first montage beat, or
--the encounter beat (whatever follows a beat plays on, as in a real game).
EncounterOfTheWeekGame.TEST_MODES = {
    { id = "start", name = "From the Start", beatKind = nil },
    { id = "montage", name = "Montage", beatKind = "montage" },
    { id = "combat", name = "Combat", beatKind = "encounter" },
}

local function TestMode(id)
    for _, m in ipairs(EncounterOfTheWeekGame.TEST_MODES) do
        if m.id == id then
            return m
        end
    end
    return nil
end

--The beat a test of this mode starts on: index, beat -- or nil, reason.
function EncounterOfTheWeekGame.TestStartBeat(script, modeid)
    local mode = TestMode(modeid)
    if mode == nil then
        return nil, "unknown test mode"
    end
    local beats = script ~= nil and script.parse ~= nil and script.parse.beats or {}
    if #beats == 0 then
        return nil, "this map has no Encounter of the Week script"
    end
    if mode.beatKind == nil then
        return 1, beats[1]
    end
    for i, beat in ipairs(beats) do
        if beat.kind == mode.beatKind then
            return i, beat
        end
    end
    if mode.beatKind == "montage" then
        return nil, "this map's script has no # Montage beat"
    end
    return nil, "this map's script has no # Encounter beat"
end

--The current map's series parts, { {number, title}, ... } in order, or an
--empty list when it is not a series (EncounterMontage.FindMapScript).
function EncounterOfTheWeekGame.SeriesParts()
    local parts = {}
    pcall(function() parts = EncounterMontage.FindMapScript().seriesParts or {} end)
    return parts
end

--May the local user start a test of this mode on the current map? true, or
--false + a reason (the menu rows hide on false). part: a series' part to
--test (default 1).
function EncounterOfTheWeekGame.CanStartTest(modeid, part)
    if part ~= nil and EncounterOfTheWeekGame.GetTest() == nil then
        --the script that would play is that part's.
        m_testPart = tonumber(part) or 1
        local ok, a, b = pcall(EncounterOfTheWeekGame.CanStartTest, modeid)
        m_testPart = nil
        if not ok then
            return false, tostring(a)
        end
        return a, b
    end
    if not dmhub.isDM then
        return false, "only the Director can test an encounter"
    end
    if EncounterOfTheWeekGame.IsEotwGame() then
        return false, "this is an Encounter of the Week game"
    end
    if EncounterOfTheWeekGame.GetTest() ~= nil then
        return false, "a test is already running"
    end
    local q = dmhub.initiativeQueue
    if q ~= nil and not q.hidden then
        return false, "end combat first"
    end
    local montage = rawget(_G, "EncounterMontage")
    if montage == nil then
        return false, "the Encounter of the Week code is not loaded"
    end
    local script = nil
    local ok = pcall(function() script = montage.FindMapScript() end)
    if not ok or script == nil then
        return false, "this map has no Encounter of the Week script"
    end
    local index, reason = EncounterOfTheWeekGame.TestStartBeat(script, modeid)
    if index == nil then
        return false, reason
    end
    return true
end

--The heroes a test party can be picked from: every hero character in the game
--that is not on the current map. Module pregens first, then by name.
--{ { charid, name, token, pregen }, ... }
function EncounterOfTheWeekGame.TestCandidates()
    local onMap = {}
    for _, tok in ipairs(dmhub.allTokens) do
        onMap[tok.charid] = true
    end
    local result = {}
    for charid, tok in pairs(dmhub.GetAllCharacters() or {}) do
        if not onMap[charid] and tok.properties ~= nil then
            local isHero = false
            pcall(function() isHero = tok.properties:IsHero() end)
            if isHero then
                local pregen = false
                pcall(function() pregen = module.IsCharacterAvailableInModule(charid) end)
                result[#result + 1] = {
                    charid = charid,
                    name = EncounterMontage.HeroDisplayName(tok),
                    token = tok,
                    pregen = pregen,
                }
            end
        end
    end
    table.sort(result, function(a, b)
        if a.pregen ~= b.pregen then
            return a.pregen
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.charid < b.charid
    end)
    return result
end

--Heroes already standing on the current map: they join any test too (the
--montage and combat take every hero on the map), so the picker names them.
function EncounterOfTheWeekGame.HeroesOnMap()
    local result = {}
    for _, hero in ipairs(EncounterMontage.Heroes()) do
        result[#result + 1] = hero.name
    end
    return result
end

--Start a test: options = { mode = "start"|"montage"|"combat", heroes = {
--charid, ... }, part = n (a series' part; default 1) } (characters from
--TestCandidates). Returns true, or false + a reason. The game refreshes into
--player-host mode; the setup runs after.
function EncounterOfTheWeekGame.StartTest(options)
    local ok, reason = EncounterOfTheWeekGame.CanStartTest(options.mode, options.part)
    if not ok then
        return false, reason
    end
    if type(options.heroes) ~= "table" or #options.heroes == 0 then
        return false, "choose at least one hero"
    end
    --parked in a global: the refresh rebuilds the game (and this codemod)
    --but not the Lua state, so the request crosses it -- the same way the
    --titlescreen hands a real arrival over (EotwPendingArrival).
    _G.EotwPendingTest = {
        gameid = dmhub.gameid,
        mode = options.mode,
        part = tonumber(options.part) or 1,
        heroes = options.heroes,
        at = dmhub.Time(),
    }
    printf("EotW test: starting a %s test of part %d with %d heroes", tostring(options.mode), tonumber(options.part) or 1, #options.heroes)
    --the Director becomes a player host. This forces a refresh; the 1s
    --driver of the reloaded game picks the request up.
    dmhub.playerHostModeForced = true
    return true
end

--Back into a test that is still on the record after this client left player-
--host mode (an app restart): switch it on again; the record carries the rest.
function EncounterOfTheWeekGame.ResumeTest()
    dmhub.playerHostModeForced = true
end

--Every game setting a test overrides, saved at the start and put back at the
--end: the forced EotW settings, plus what SetupOnArrival writes.
local function TestSettingIds()
    local ids = { "numheroes", "permission:playersinitiative" }
    for _, entry in ipairs(g_forcedGameSettings) do
        ids[#ids + 1] = entry.id
    end
    return ids
end

--Settings are registered by the codemods as they load, so straight after the
--test's refresh some may not exist yet (touching one logs "Could not find
--setting"). The setup waits for them all.
local function TestSettingsRegistered()
    for _, id in ipairs(TestSettingIds()) do
        if not dmhub.HasSetting(id) then
            return false
        end
    end
    return true
end

local function WriteTest(fn, description)
    local doc = mod:GetDocumentSnapshot(STATE_DOC_ID)
    doc:BeginChange()
    fn(doc.data)
    doc:CompleteChange(description, {undoable = false})
end

--Corpses and loot drops: map objects made from the "corpse" keyword's
--blueprint (ActivatedAbilityRemoveCreatureBehavior's LeaveCorpse/DropLoot,
--run by Monster Death and Hero Death). A test notes the ones already on the
--map and End Test destroys every other, so the deaths leave nothing behind
--while corpses the author placed stay. { [objid] = obj } on the current map.
local function CorpseObjects()
    local result = {}
    local assetids = {}
    pcall(function()
        for _, asset in ipairs(assets:GetObjectsWithKeyword("corpse")) do
            assetids[asset.id] = true
        end
    end)
    local map = game.currentMap
    for _, floor in ipairs((map and map.floors) or {}) do
        pcall(function()
            for objid, obj in pairs(floor.objects or {}) do
                if assetids[obj.assetid] then
                    result[objid] = obj
                end
            end
        end)
    end
    return result
end

--Every token already on the map when a test starts (bystanders, authored
--monsters, heroes left standing there), as full character records, so End
--Test can put each back exactly: position, conditions, stamina -- whatever
--the fight or the map's own scripts did to it (a hostage script that frees
--and walks the Civilians). Kept in its own document: the records are big and
--eotwstate is watched by every client.
--  data.records = { [charid] = ExportCharacter record (JSON text) }
local SNAPSHOT_DOC_ID = "eotwtestsnapshot"

local function SnapshotMapTokens()
    local records = {}
    local n = 0
    local function Add(tok)
        if tok == nil or tok.charid == nil or records[tok.charid] ~= nil then
            return
        end
        local exported = dmhub.ExportCharacter(tok)
        if exported ~= nil then
            records[tok.charid] = exported.record
            n = n + 1
        end
    end
    for _, tok in ipairs(dmhub.allTokens) do
        Add(tok)
    end
    for _, tok in ipairs(dmhub.despawnedTokens or {}) do
        Add(tok)
    end
    local doc = mod:GetDocumentSnapshot(SNAPSHOT_DOC_ID)
    doc:BeginChange()
    doc.data.records = records
    doc:CompleteChange("Encounter test: map tokens noted", {undoable = false})
    return n
end

--Write every noted record back over its character (re-creating any the test
--deleted), then forget them. Returns how many were restored.
local function RestoreMapTokens()
    local doc = mod:GetDocumentSnapshot(SNAPSHOT_DOC_ID)
    local records = doc.data.records
    if type(records) ~= "table" then
        return 0
    end
    local n = 0
    for charid, record in pairs(records) do
        if type(record) == "string" and dmhub.ImportCharacter{ record = record, charid = charid } ~= nil then
            n = n + 1
        end
    end
    doc:BeginChange()
    doc.data.records = nil
    doc:CompleteChange("Encounter test: map tokens restored", {undoable = false})
    return n
end

--The state-doc keys a real arrival and its combat write. A test starts and
--ends with none of them (ResetTest clears the combat ones).
local function ClearTestArrival(data)
    data.placedHeroes = nil
    data.expectedUsers = nil
    data.arrived = nil
    data.arrange = nil
    data.combatStarted = nil
    data.proceedRequested = nil
    data.arrivalItems = nil
    data.alreadyCompleted = nil
    data.abilityBusy = nil
    data.practice = nil
end

--The test's arrival (host, inside a coroutine, already in player-host mode).
--Errors are raised; RunTestSetup ends the test on one.
local function TestArrival(pending)
    local userid = dmhub.loginUserid
    local montage = EncounterMontage
    --a series: the part under test picks the script (and so the island,
    --region and start tiles) until data.test carries it.
    m_testPart = tonumber(pending.part) or 1
    local script = montage.FindMapScript(true)
    local index, beat = EncounterOfTheWeekGame.TestStartBeat(script, pending.mode)
    if index == nil then
        error(beat)
    end

    --a clean slate: whatever a previous test or a dev driver left behind.
    if not montage.ResetTest() then
        error("combat is running")
    end
    m_arrangeBegin = nil

    local saved = { settings = {}, heroTokens = 0 }
    for _, id in ipairs(TestSettingIds()) do
        if dmhub.HasSetting(id) then
            saved.settings[id] = dmhub.GetSettingValue(id)
        end
    end
    pcall(function() saved.heroTokens = CharacterResource.GetGlobalResource(CharacterResource.heroTokenId) end)
    saved.corpses = {}
    for objid, _ in pairs(CorpseObjects()) do
        saved.corpses[objid] = true
    end
    --after the clean-slate reset (so a previous run's leftovers are not
    --noted) and before the hero copies arrive.
    saved.tokens = SnapshotMapTokens()

    WriteTest(function(data)
        ClearTestArrival(data)
        data.test = {
            phase = "setup",
            mode = pending.mode,
            by = userid,
            startedAt = dmhub.serverTime,
            mapid = game.currentMapId,
            part = m_testPart,
            heroes = pending.heroes,
            saved = saved,
        }
    end, "Encounter test: setting up")
    m_testPart = nil

    --bounded to the encounter's region like a real game (released at the
    --end of the test).
    ApplyPlayRegion()

    --copies of the chosen heroes, pasted into the Start zone and claimed as
    --this user's own -- the real arrival's pregen path.
    local entries = {}
    for _, charid in ipairs(pending.heroes) do
        entries[#entries + 1] = { kind = "pregen", id = charid }
    end
    PlaceMyHeroes(entries, {})
    local placed = {}
    for _, charid in pairs(GetPlacedHeroes(userid)) do
        placed[#placed + 1] = charid
    end
    WriteTest(function(data)
        data.test.placed = placed
    end, "Encounter test: heroes placed")
    if #placed == 0 then
        error("none of the chosen heroes could be placed")
    end

    --what a real EotW host writes at setup.
    local numHeroes = math.max(3, math.min(7, #placed))
    dmhub.SetSettingValue("numheroes", numHeroes)
    CharacterResource.SetGlobalResource(CharacterResource.heroTokenId, #placed, "Start of the encounter test")
    dmhub.SetSettingValue("permission:playersinitiative", true)
    EnforceStrictRules()

    --the whole party is here (just this user); the host tick waits the usual
    --3s settle from this stamp.
    WriteTest(function(data)
        data.expectedUsers = { userid }
        data.arrived = { [userid] = dmhub.serverTime }
    end, "Encounter test: arrived")

    --the chosen beat. Stage beats go up now; the encounter beat starts on
    --the host tick.
    local narrative = rawget(_G, "EncounterNarrative")
    if beat.kind == "montage" then
        montage.Begin(script, beat, index)
    elseif beat.kind == "narrative" and narrative ~= nil then
        narrative.Begin(script, beat, index)
    end
    SetBeatIndex(index)

    AttachMapScript()

    WriteTest(function(data)
        data.test.phase = "running"
    end, "Encounter test: running")
    printf("EotW test: running from beat %d (%s) with %d heroes", index, tostring(beat.kind), #placed)
end

local m_testSetupRunning = false

--When this copy of the file loaded. The test's refresh reloads the codemods,
--and only a copy loaded after StartTest may run the setup: the copy from
--before the refresh can see a map and a hud mid-reload, while the core
--files (and the settings they register) are still loading.
local m_loadedAt = dmhub.Time()

local function RunTestSetup(pending)
    m_testSetupRunning = true
    dmhub.Coroutine(function()
        --the refresh rebuilds the game: give it a moment to begin, then wait
        --for it to finish loading and for the map and the hud to come up.
        for _ = 1, 300 do
            if mod.unloaded then
                return
            end
            local progress = dmhub.gameLoadingProgress
            if dmhub.Time() - (tonumber(pending.at) or 0) > 2 and (progress == nil or progress >= 1)
                and game.currentMap ~= nil and GameHud.instance and TestSettingsRegistered() then
                break
            end
            coroutine.yield(0.2)
        end
        coroutine.yield(1)
        --the request stays parked until here: playerHostMode reads true the
        --moment the switch is set, BEFORE the refresh, so the instance that
        --started this may be the one the refresh unloads. Its successor
        --then finds the request still waiting.
        if mod.unloaded or rawget(_G, "EotwPendingTest") ~= pending then
            return
        end
        _G.EotwPendingTest = nil
        local ok, err = pcall(TestArrival, pending)
        m_testSetupRunning = false
        if not ok then
            printf("EotW test: could not start the test: %s", tostring(err))
            EncounterOfTheWeekGame.EndTest()
        end
    end)
end

--The 1s driver: run a test request parked by StartTest once this client is
--in player-host mode (after the refresh the switch caused). A request whose
--switch never took -- no hosting status -- is dropped after a while.
function EncounterOfTheWeekGame.ConsumePendingTest()
    local pending = rawget(_G, "EotwPendingTest")
    if type(pending) ~= "table" or m_testSetupRunning then
        return
    end
    if pending.gameid ~= dmhub.gameid then
        _G.EotwPendingTest = nil
        return
    end
    if dmhub.playerHostMode ~= true then
        if dmhub.Time() - (tonumber(pending.at) or 0) > 30 then
            _G.EotwPendingTest = nil
            dmhub.playerHostModeForced = false
            printf("EotW test: this client never became a player host; the test was not started")
        end
        return
    end
    --leave it for the copy the refresh loads (see m_loadedAt); only if no
    --reload ever comes does this copy take it.
    if m_loadedAt < (tonumber(pending.at) or 0) and dmhub.Time() - (tonumber(pending.at) or 0) < 15 then
        return
    end
    RunTestSetup(pending)
end

--End a test's combat with no victory screen and none of the real teardown's
--battle log or analytics (the proceed override uses it after a test's
--victory screen too).
function EncounterOfTheWeekGame.EndTestCombat()
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return
    end
    ElevateToHostPermissions()
    local ok, err = pcall(function()
        local live = q:try_get("liveEncounter")
        if type(live) == "table" then
            live.victoryAwarded = false
            live.defeatAwarded = false
        end
        q.hidden = true
        q.gameMode = "exploration"
        dmhub:UploadInitiativeQueue()
        CharacterResource.SetMalice(0, "End of the encounter test")
        ActivatedAbilitySummonBehavior.RemoveSummonsAtEndOfCombat()
        Aura.RemoveExpiredMapAnchoredAurasAtEndOfCombat()
    end)
    DropHostPermissions()
    if not ok then
        printf("EotW test: could not end combat: %s", tostring(err))
    end
end

--Put the map back as authored (inside a coroutine; see EndTest).
local function TestTeardown()
    local test = EncounterOfTheWeekGame.GetTest()
    if test ~= nil then
        WriteTest(function(data)
            data.test.phase = "ending"
        end, "Encounter test: ending")
    end

    m_arrangeBegin = nil
    EnsureAIStopped()
    EncounterOfTheWeekGame.EndTestCombat()
    for _ = 1, 25 do
        local q = dmhub.initiativeQueue
        if q == nil or q.hidden then
            break
        end
        coroutine.yield(0.2)
    end

    --the script's state, its allies and spawns, the traps and zones, malice
    --(and it detaches the map script).
    EncounterMontage.ResetTest()

    --the map's own bounds back, if the encounter's region shrank them.
    ElevateToHostPermissions()
    ReleasePlayRegion()
    DropHostPermissions()
    m_testPart = nil

    --the hero copies, and the settings and hero tokens the test overrode.
    local copies = {}
    local seen = {}
    local function AddCopy(charid)
        if type(charid) == "string" and not seen[charid] and dmhub.GetCharacterById(charid) ~= nil then
            seen[charid] = true
            copies[#copies + 1] = charid
        end
    end
    if test ~= nil then
        for _, charid in ipairs(test.placed or {}) do
            AddCopy(charid)
        end
    end
    for _, charid in pairs(GetPlacedHeroes(dmhub.loginUserid)) do
        AddCopy(charid)
    end

    ElevateToHostPermissions()
    local ok, err = pcall(function()
        if #copies > 0 then
            game.DeleteCharacters(copies)
            printf("EotW test: removed %d hero copies", #copies)
        end
        local saved = test ~= nil and test.saved or nil
        --the corpses and loot the test's deaths left (a record from before
        --corpses were noted has no list, and then nothing is touched).
        if type(saved) == "table" and type(saved.corpses) == "table" then
            local n = 0
            for objid, obj in pairs(CorpseObjects()) do
                if not saved.corpses[objid] then
                    obj:Destroy()
                    n = n + 1
                end
            end
            if n > 0 then
                printf("EotW test: removed %d corpse/loot objects", n)
            end
        end
        --the tokens that were on the map before the test, exactly as they were.
        local restored = RestoreMapTokens()
        if restored > 0 then
            printf("EotW test: restored %d map tokens", restored)
        end
        if type(saved) == "table" then
            for id, value in pairs(saved.settings or {}) do
                if dmhub.GetSettingValue(id) ~= value then
                    dmhub.SetSettingValue(id, value)
                end
            end
            CharacterResource.SetGlobalResource(CharacterResource.heroTokenId, tonumber(saved.heroTokens) or 0, "End of the encounter test")
        end
    end)
    DropHostPermissions()
    if not ok then
        printf("EotW test: cleanup failed: %s", tostring(err))
    end

    WriteTest(function(data)
        ClearTestArrival(data)
        data.test = nil
    end, "Encounter test: ended")

    --this client's own end-of-encounter bookkeeping, in case no refresh
    --follows to reset it.
    m_outcomeSeen = false
    m_outcomeKind = nil
    m_outcomesRecorded = false
    m_exitScheduled = false
    m_localProceeded = false
    m_victorySeenAt = nil
    m_awardHoldTicks = 0
    m_outcomeMetTime = nil
end

local m_testEnding = false

--End the test: put the map back and return this client to the Director.
--Safe to call with no test running (it then only leaves player-host mode).
function EncounterOfTheWeekGame.EndTest()
    if m_testEnding then
        return
    end
    m_testEnding = true
    _G.EotwPendingTest = nil
    dmhub.Coroutine(function()
        local ok, err = pcall(TestTeardown)
        if not ok then
            printf("EotW test: ending the test failed: %s", tostring(err))
        end
        m_testEnding = false
        print("EotW test: ended; back to the Director")
        dmhub.playerHostModeForced = false
    end)
end

--- the arrival handoff --------------------------------------------------

--Setup is handed over from the titlescreen: it parks the arrival args in a
--global before entering the game, then calls in here from the engine's
--arrival callback ("Codex Titlescreen/EncounterOfTheWeek.lua"). The two can
--land in either order. The engine fires that callback the instant the
--loading screen clears, while this codemod's id rides in on the /games
--record -- which can arrive a beat later, in which case the callback found
--EncounterOfTheWeekGame still nil and silently skipped setup, leaving the
--member on the engine's default map choice with no heroes placed, and so
--with no vision at all: a black screen showing nothing but the Start zone
--outline (bug 32UW4UQB). So whichever side gets here second runs the setup,
--exactly once.
--
--.ready is the callback's stamp. The engine fires it only once the game has
--finished loading, so it is also this side's guarantee that travelling maps
--and pasting tokens is safe now; without it we would be acting on a
--half-loaded game.
local m_arrivalStarted = false

function EncounterOfTheWeekGame.ConsumePendingArrival()
    if m_arrivalStarted then
        return
    end

    local pending = rawget(_G, "EotwPendingArrival")
    if type(pending) ~= "table" or pending.ready ~= true then
        return
    end

    --only a POSITIVE mismatch rejects: an unreadable gameid must not be what
    --swallows the handoff all over again. Entry overwrites the global every
    --time, and only the callback for the game being entered stamps it ready,
    --so a leftover from another game needs both reads to disagree to matter.
    local currentGame = nil
    pcall(function() currentGame = dmhub.gameid end)
    if pending.gameid ~= nil and currentGame ~= nil and pending.gameid ~= currentGame then
        --parked for a different game; leave it for that game's client.
        return
    end

    m_arrivalStarted = true
    _G.EotwPendingArrival = nil
    EncounterOfTheWeekGame.SetupOnArrival(pending)
end

--The load-time half of the handoff: pick up an arrival the titlescreen's
--callback could not deliver because this codemod had not loaded yet. A no-op
--in every other case -- entering the authoring game, a Lua reload
--mid-session, or the normal ordering where the callback lands second.
EncounterOfTheWeekGame.ConsumePendingArrival()
