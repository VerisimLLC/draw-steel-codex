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

--Handoff to the town: what a won encounter means for each of this
--machine's town heroes, written before leaving the game and applied by the
--town once the player is back (EotwRoster.ApplyPendingOutcomes: the
--Victory onto the roster hero, then the city's record-outcome). JSON text:
--{ [userid] = { ["<gameid>|<heroid>"] = {gameid, heroid, outcome, stage} } }.
--Machine-local so it survives the game switch and a crash on the way home.
--The titlescreen re-declares it.
setting{
    id = "eotw:pendingOutcomes",
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
--(map ids change with every publish; names do not). Returns moduleid, map
--name; nil or "" is the official default map. A copy of the titlescreen's
--EncounterOfTheWeek.ParseEncounterKey -- keep the two in step.
local function ParseEncounterKey(key)
    if type(key) ~= "string" or key == "" then
        return OFFICIAL_MODULE, DEFAULT_ENCOUNTER_MAP
    end
    local moduleid, mapName = key:match("^([^|]+)|(.+)$")
    if moduleid == nil then
        return OFFICIAL_MODULE, key
    end
    return moduleid, mapName
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
--
--A montage clause can open further zone types to start in ("the Start2 zone
--becomes a starting area", EncounterZones.UnlockedStartZones): their tiles
--join the result, so the confinement and its outline grow to cover them.
--Pass baseOnly = true for the Start zone alone (where heroes are placed).
local function StartZoneLocs(baseOnly)
    local map = game.currentMap
    if map == nil then
        return {}
    end

    local startNames = { start = true }
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
                        or (record.keywordName ~= nil and startNames[string.lower(record.keywordName)])) then
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
local function SendLobbyRequest(action, args, onDone)
    local lobbies = rawget(_G, "lobbies")
    if lobbies == nil then
        printf("EotW: engine has no lobbies API; cannot send %s", tostring(action))
        return
    end

    local conn = lobbies:Connect(LOBBY_ID, LOBBY_OPTIONS)
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
        local treasure = EncounterOfTheWeekGame.TreasureGained(token)
        if #treasure == 0 then
            return nil
        end
        return "Treasure: " .. DescribeTreasure(treasure)
    end)
end)

--Note what this won encounter means for each of MY town heroes, for the
--town to apply once the player is home (see eotw:pendingOutcomes). Only
--heroes alive at the end count: the dead are left for the burial
--write-back (not built yet), and a defeat records nothing for the same
--reason. A hero who had already won it records the outcome with 0
--Victories.
local function RecordPendingOutcomes()
    if m_outcomesRecorded then
        return
    end
    m_outcomesRecorded = true

    local encounter = nil
    pcall(function() encounter = mod:GetDocumentSnapshot(STATE_DOC_ID).data.encounterMap end)
    if type(encounter) ~= "string" or encounter == "" then
        printf("EotW: no encounter name recorded; the town will not hear of this victory")
        return
    end

    local completed = AlreadyCompletedHeroes()
    local entries = {}
    for key, charid in pairs(GetPlacedHeroes(dmhub.loginUserid)) do
        --town heroes travel as "lobby:<heroid>" (see PlaceMyHeroes).
        local heroid = string.match(key, "^lobby:(.+)$")
        local tok = heroid ~= nil and dmhub.GetCharacterById(charid) or nil
        local alive = false
        pcall(function() alive = tok ~= nil and tok.properties ~= nil and not tok.properties:IsDead() end)
        if alive then
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
            entries[#entries + 1] = {
                gameid = dmhub.gameid,
                heroid = heroid,
                stage = "new",
                outcome = outcome,
            }
        end
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
        end
        --the Victory has landed: note it for the town now, not only on the
        --way out, so a crash on the victory screen does not lose it.
        if outcome == "victory" and awarded then
            RecordPendingOutcomes()
        end
        return
    end

    if m_outcomeSeen and m_localProceeded then
        m_exitScheduled = true
        printf("EotW: encounter concluded; returning to the titlescreen")

        --a victory whose award this client never saw (the host tore combat
        --down in the same moment) is still a victory for the town.
        if m_outcomeKind == "victory" then
            RecordPendingOutcomes()
        end

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

--The banner resolved: hold for the arrangement when the heroes won.
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
        pcall(function() EncounterOfTheWeekGame.EnsureMapScriptRunning() end)
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
EncounterOfTheWeekGame.FindMapEncounter = FindMapEncounter

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
                    token:ChangeLocation(dest)
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
                            token:ChangeLocation(dest)
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
            WaitForPastedCharacters(pastedIds)

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
                    myPasted[#myPasted+1] = charid
                    mine[HeroKey(heroEntry)] = charid
                    changed = true
                end
            end
        end
    end

    --another client arriving in the same instant may have pasted onto the
    --same tiles; spread any pile before recording placement.
    UnstackPlacedHeroes(myPasted, anchor)

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

    if not EncounterOfTheWeekGame.IsEotwGame() or not IsDMOrPlayerHost() then
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
--fallback when the banner's continuation was lost); options.noArrange: no
--arrangement hold.
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
            --a winning party arranges itself before the first turn.
            holdBeforeQueue = cond(options.noArrange, nil, HoldForArrangement),
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

    ctx:RunOnce(string.format("draw-steel-%d", index), function()
        StartEncounterCombat(sides)
    end)
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

    --keep the forced game settings (strict rules, monster stamina
    --visibility) asserted for the life of the game (no-op writes are
    --skipped, so this is free when nothing changed).
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
        --surges the montage banked can only be granted with a live queue
        --(they are a clearOutsideOfCombat resource); this is a no-op once
        --the bank is empty.
        pcall(EncounterMontage.ApplyPendingCombatBoons)
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
        if IsDMOrPlayerHost() then
            --stamp it, so members arriving after the lobby record expires,
            --and every resume, land on the same map.
            RecordEncounterMap(encounterKey, encounterMapId)

            --an opening montage goes up before the heroes land, so it is
            --the stage that the held loading screen reveals.
            BeginOpeningMontage()
        end

        PlaceMyHeroes(args.heroes, args.clipboardIds)
        RecordCompletedHeroes(args.heroes)

        --the heroes are in: let the loading screen go, unless a montage
        --stage is what this player should be looking at -- then its create
        --event releases the hold once it is on screen.
        if MontageStageExpected() then
            printf("EotW: leaving the loading screen to the montage stage")
        else
            ReleaseLoadingScreen()
        end

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

            --the map script takes it from here: combat entry once everyone
            --has arrived, then Monster AI supervision.
            AttachMapScript()

            --signal ready even if the spawn failed: better to let everyone
            --in to see the problem than to leave them waiting forever.
            SignalGameReady()
        end
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
