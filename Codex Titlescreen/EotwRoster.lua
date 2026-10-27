local mod = dmhub.GetModLoading()

--Encounter of the Week town roster: the heroes a player keeps in the
--Blackbottom city, and the town's Hero's Guild and Graveyard screens.
--
--The roster lives in the City Durable Object (cloudflare-game-server
--src/city.ts), one per town, reached through the same lobbies bridge as a
--lobby (route "city"). Each hero is stored there as the character record
--exactly as a game stores it, plus the asset records its portrait needs.
--
--The character builder can only edit a character in the CURRENT game, which
--at the titlescreen is the local lobby game. So every town hero also has a
--working copy there: a lobby character whose charid IS the hero's id in the
--city, tagged properties.eotwHero = true (which keeps it out of the
--titlescreen's own hero slots). The city is the source of truth:
--  * opening the town lists the roster and imports any hero whose city
--    revision differs from the copy we last synced (dmhub.ImportCharacter);
--  * creating, recruiting or editing a hero pushes the working copy back
--    (dmhub.ExportCharacter -> put-hero, revision-checked);
--  * a copy the city no longer has (dismissed elsewhere, fallen) is removed.
--The last revision synced per hero is a machine-local preference.
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md, "Blackbottom".

EotwRoster = {}

local T = UIText.T
local TP = UIText.Plural

--The town's city id. The game-side EotW mod
--(EncounterOfTheWeek/EncounterOfTheWeek.lua) must connect to the same city,
--on the same server, to signal ready / leave and record outcomes.
EotwRoster.CITY_ID = "blackbottom"

--Which game server the town and its games live on: "release" or "staging".
--Only admins may choose (the titlescreen card's dropdown); everyone else is
--always on release. Declared by the game-side EotW mod too, which reads it
--the same way (EotwUseStaging there), so a game and the town agree.
setting{
    id = "eotw:server",
    default = "release",
    storage = "preference",
}

function EotwRoster.UseStaging()
    return dmhub.isAdminAccount == true and dmhub.GetSettingValue("eotw:server") == "staging"
end

--Options for lobbies:Connect to the town. Read at each connect, so a change
--of server takes effect the next time the town opens.
function EotwRoster.CityOptions()
    return { staging = EotwRoster.UseStaging(), route = "city" }
end

--The storage backend new EotW games are created on, matching the town's server.
function EotwRoster.GameBackend()
    return cond(EotwRoster.UseStaging(), "durableobjects-staging", "durableobjects")
end

--Ask the city how many users are connected, without connecting: callback(count),
--or callback(nil) on failure. Only open city sockets count as presence, so the
--titlescreen can show the town's headcount without being counted in it.
function EotwRoster.FetchHeadcount(callback)
    local host = cond(EotwRoster.UseStaging(), "https://game-server-staging.codexback.com", "https://game-server.codexback.com")
    net.Get{
        url = string.format("%s/api/city/%s/presence", host, EotwRoster.CITY_ID),
        success = function(result)
            local count = type(result) == "table" and result.count or nil
            callback(cond(type(count) == "number", count, nil))
        end,
        error = function(message)
            callback(nil)
        end,
    }
end

--Server-enforced limits (city-core.ts); these only drive the UI. A roster
--starts with BASE_SLOTS hero slots; each completion of the Expand the Guild
--project adds one, up to MAX_SLOTS (the city reports the account's slots).
EotwRoster.BASE_SLOTS = 4
EotwRoster.MAX_SLOTS = 9
EotwRoster.MAX_ACTIVE = 4

--Bumped whenever the roster (or a working copy) changes; UIs poll it.
EotwRoster.revision = 0

--heroid -> the city revision of the working copy we last synced, per
--account, as JSON text: { [userid] = { [heroid] = rev } }.
setting{
    id = "eotw:heroRevs",
    default = "",
    storage = "preference",
}

--Won encounters waiting to be applied to roster heroes, written by the
--game-side EotW mod as the player leaves an encounter (see
--ApplyPendingOutcomes). Declared there too; JSON text:
--{ [userid] = { ["<gameid>|<heroid>"] = {gameid, heroid, outcome, stage} } }.
setting{
    id = "eotw:pendingOutcomes",
    default = "",
    storage = "preference",
}

--Hall of Heroes entries a game this machine hosted could not hand the city
--before it closed (see FlushPendingHall). Declared by the game-side EotW mod
--too; JSON text: { [userid] = { [gameid] = args of the city's hall-record } }.
setting{
    id = "eotw:pendingHall",
    default = "",
    storage = "preference",
}

local m_conn = nil
--this account's living heroes as the city last listed them (hero views:
--{heroid, rev, status, active, summary, ...}); nil until the first list.
local m_heroes = nil
--What this account has unlocked in town (list-heroes' `unlocks`), or nil
--while not yet listed: { dangerRooms = bool }.
local m_unlocks = nil
--This account's roster slots (list-heroes' `slots`), or nil while not listed.
local m_slots = nil
--The leads this account has learned by carousing (list-heroes' `leads`),
--and the respite whose carouse is still open (`carouse`, false when none).
--See EotwLeads.lua.
local m_leads = nil
local m_carouse = nil
local m_refreshing = false
local m_refreshAgain = false
--heroids being imported right now, so a second refresh does not import twice.
local m_importing = {}
--charids created on this machine that have not reached the city yet; the
--sync must not mistake them for heroes deleted elsewhere.
local m_pendingCreates = {}
--the last error a roster operation reported, for the guild's status line.
EotwRoster.lastError = nil

local function Bump()
    EotwRoster.revision = EotwRoster.revision + 1
end

local function Fail(message)
    EotwRoster.lastError = tostring(message)
    printf("EotW town: %s", tostring(message))
    Bump()
end

--- revision map ---------------------------------------------------------

local function LoadAllRevs()
    local text = dmhub.GetSettingValue("eotw:heroRevs")
    local all = nil
    if type(text) == "string" and text ~= "" then
        --FromJson answers {success, result}, not the decoded value.
        local parsed = dmhub.FromJson(text)
        if type(parsed) == "table" and parsed.success then
            all = parsed.result
        end
    end
    if type(all) ~= "table" then
        all = {}
    end
    return all
end

local function GetRevs()
    local all = LoadAllRevs()
    local mine = all[dmhub.loginUserid]
    if type(mine) ~= "table" then
        mine = {}
    end
    return mine
end

local function SetRev(heroid, rev)
    local all = LoadAllRevs()
    local mine = all[dmhub.loginUserid]
    if type(mine) ~= "table" then
        mine = {}
        all[dmhub.loginUserid] = mine
    end
    mine[heroid] = rev
    dmhub.SetSettingValue("eotw:heroRevs", dmhub.ToJson(all))
end

--- display helpers --------------------------------------------------------

--Best-effort class / ancestry / level for display. pcall because a
--character's properties vary (and game types raise on unknown members).
function EotwRoster.HeroDetails(tok)
    local className, ancestry, level = "", "", nil
    pcall(function()
        local classesTable = dmhub.GetTable("classes")
        for _,entry in ipairs(tok.properties:try_get("classes") or {}) do
            local info = classesTable[entry.classid]
            if info ~= nil and info.name ~= nil then
                className = info.name
            end
        end
    end)
    pcall(function()
        local text = tok.properties:RaceOrMonsterType()
        if type(text) == "string" then
            ancestry = text
        end
    end)
    pcall(function()
        local l = tok.properties:CharacterLevel()
        if type(l) == "number" and l >= 1 then
            level = math.floor(l)
        end
    end)
    return className, ancestry, level
end

--"Level 2 Wode Elf Troubadour" from whichever parts are known.
function EotwRoster.FormatDetails(level, ancestry, className)
    local parts = {}
    if level ~= nil then
        parts[#parts+1] = T("roster.details.level", { level = level })
    end
    if ancestry ~= nil and ancestry ~= "" then
        parts[#parts+1] = ancestry
    end
    if className ~= nil and className ~= "" then
        parts[#parts+1] = className
    end
    return table.concat(parts, " ")
end

--The summary the city keeps beside the record: what other players see in
--parties and town lists without loading the whole sheet.
local function BuildSummary(tok)
    local className, ancestry, level = EotwRoster.HeroDetails(tok)
    local name = tok.name
    if name == nil or name == "" then
        name = T("roster.unnamed_hero")
    end
    local summary = { name = name, className = className, ancestry = ancestry }
    if level ~= nil then
        summary.level = level
    end
    pcall(function()
        local p = tok.offTokenPortrait
        if type(p) == "string" and p ~= "" then
            summary.portrait = p
        end
    end)
    pcall(function()
        local bg = tok.portraitBackground
        if type(bg) == "string" and bg ~= "" then
            summary.portraitBackground = bg
        end
    end)
    --a hero who came home dying cannot join a party until they rest (the
    --city refuses the claim; see checkHeroClaim).
    if EotwRoster.TokenIsDying(tok) then
        summary.dying = true
    end
    return summary
end

--Is this character dying (Stamina at 0 or below, but not dead)? Such a
--hero must rest at the Blue Fish Inn before setting out again.
function EotwRoster.TokenIsDying(tok)
    local dying = false
    pcall(function()
        dying = tok.properties:CurrentHitpoints() <= 0 and not tok.properties:IsDead()
    end)
    return dying
end

--Is this roster hero dying? Reads the working copy when it has loaded,
--else the city's summary.
function EotwRoster.IsDying(heroid)
    local tok = dmhub.GetCharacterById(heroid)
    if tok ~= nil then
        return EotwRoster.TokenIsDying(tok)
    end
    local hero = EotwRoster.FindHero(heroid)
    return hero ~= nil and hero.summary ~= nil and hero.summary.dying == true
end

local function IsTownHero(tok)
    local result = false
    pcall(function() result = rawget(tok.properties, "eotwHero") == true end)
    return result
end

--- connection + sync --------------------------------------------------------

--The town screen hands its city connection here when it opens.
function EotwRoster.Attach(conn)
    m_conn = conn
    m_heroes = nil
    m_unlocks = nil
    m_slots = nil
    m_leads = nil
    m_carouse = nil
    EotwRoster.lastError = nil
    Bump()
end

function EotwRoster.Detach(conn)
    if m_conn == conn then
        m_conn = nil
    end
end

function EotwRoster.Connection()
    return m_conn
end

--This account's living heroes (hero views), or nil while not yet listed.
function EotwRoster.GetHeroes()
    return m_heroes
end

function EotwRoster.FindHero(heroid)
    for _,hero in ipairs(m_heroes or {}) do
        if hero.heroid == heroid then
            return hero
        end
    end
    return nil
end

function EotwRoster.LivingCount()
    return #(m_heroes or {})
end

--This account's hero slots (4 plus one per Guild expansion).
function EotwRoster.Slots()
    return m_slots or EotwRoster.BASE_SLOTS
end

--A roster hero's unspent Downtime Activities, as the city last listed them
--(they are earned at a respite and spent on projects; see EotwDowntime).
function EotwRoster.GetDowntime(heroid)
    local hero = EotwRoster.FindHero(heroid)
    return hero ~= nil and tonumber(hero.downtime) or 0
end

--Record a hero's Downtime count the city just reported (after a grant or a
--project roll), so cards update before the next list arrives.
function EotwRoster.SetListedDowntime(heroid, downtime)
    local hero = EotwRoster.FindHero(heroid)
    if hero ~= nil and type(downtime) == "number" then
        hero.downtime = downtime
        Bump()
    end
end

--The account's slots as the city just reported them (a Guild expansion).
function EotwRoster.SetListedSlots(slots)
    if type(slots) == "number" then
        m_slots = slots
        Bump()
    end
end

--Is the hero's working copy loaded and in step with the city, with nothing
--in flight that would overwrite a change made to it now?
function EotwRoster.IsInStep(heroid)
    local hero = EotwRoster.FindHero(heroid)
    if hero == nil or dmhub.GetCharacterById(heroid) == nil then
        return false
    end
    return GetRevs()[heroid] == hero.rev and not m_importing[heroid]
end

--The heroes marked active, in roster order.
function EotwRoster.ActiveHeroes()
    local result = {}
    for _,hero in ipairs(m_heroes or {}) do
        if hero.active == true then
            result[#result+1] = hero
        end
    end
    return result
end

--Has this account unlocked the Proving Pits? The city opens them for good
--once any of the account's heroes has won an Encounter of the Week (the
--current one or a past one). nil while the roster has not been listed.
function EotwRoster.DangerRoomsUnlocked()
    if m_unlocks == nil then
        return nil
    end
    return m_unlocks.dangerRooms == true
end

--Has any of this account's heroes won this encounter (an encounter key; a
--series' later part is "<key>#<n>")? Account-wide, dismissed and fallen
--heroes included: what unlocks a series' next part at the Town Gate. From
--list-heroes' unlocks.completed; false while the roster is not listed.
function EotwRoster.AccountCompleted(key)
    for _, k in ipairs(m_unlocks ~= nil and type(m_unlocks.completed) == "table" and m_unlocks.completed or {}) do
        if k == key then
            return true
        end
    end
    return false
end

--Has this account won this encounter in the Proving Pits? Practice wins
--unlock a series' next part there, and only there (unlocks.practiceWins).
function EotwRoster.PracticeWon(key)
    for _, k in ipairs(m_unlocks ~= nil and type(m_unlocks.practiceWins) == "table" and m_unlocks.practiceWins or {}) do
        if k == key then
            return true
        end
    end
    return false
end

--The city's answer to record-practice-win carries the account's whole list.
function EotwRoster.SetPracticeWins(list)
    if type(list) ~= "table" then
        return
    end
    m_unlocks = m_unlocks or {}
    m_unlocks.practiceWins = list
    Bump()
end

--Is this encounter open for the account on this board ("gate" or
--"practice"): won since its last respite? While a series part is open, its
--next part may be played; a respite closes them all (unlocks.openParts).
--nil when the city does not send openParts (a server from before the rule).
function EotwRoster.PartOpen(key, board)
    local open = m_unlocks ~= nil and m_unlocks.openParts or nil
    if type(open) ~= "table" then
        return nil
    end
    for _, k in ipairs(type(open[board]) == "table" and open[board] or {}) do
        if k == key then
            return true
        end
    end
    return false
end

--Every open encounter key on a board, oldest win first (see PartOpen).
function EotwRoster.OpenParts(board)
    local open = m_unlocks ~= nil and m_unlocks.openParts or nil
    if type(open) ~= "table" or type(open[board]) ~= "table" then
        return {}
    end
    return open[board]
end

--The city answers record-practice-win and a respite with the account's
--open parts ({gate = {...}, practice = {...}}).
function EotwRoster.SetOpenParts(view)
    if type(view) ~= "table" then
        return
    end
    m_unlocks = m_unlocks or {}
    m_unlocks.openParts = view
    Bump()
end

--Has this account found the Arcane Market? It is not open to everyone: a
--lead heard while carousing at the inn starts a project (Find the Arcane
--Market), and completing it puts the market on the map (EotwLeads.lua).
function EotwRoster.MarketUnlocked()
    if m_unlocks ~= nil and m_unlocks.market == true then
        return true
    end
    --the project's completion is known before the next list-heroes.
    local state = EotwDowntime.GetProject("find-arcane-market")
    return state ~= nil and (tonumber(state.completions) or 0) >= 1
end

--Has the town finished building the Hall of Heroes (the community project
--Build the Hall of Heroes)? Until then its place on the map is the
--Construction.
function EotwRoster.HallBuilt()
    if m_unlocks ~= nil and m_unlocks.hallOfHeroes == true then
        return true
    end
    --the community project is re-listed whenever anyone in town works on
    --it, which is sooner than the next list-heroes.
    local state = EotwDowntime.GetProject("build-hall-of-heroes")
    return state ~= nil and (tonumber(state.completions) or 0) >= 1
end

--Has the town finished building the Town Hall (the community project Build
--the Town Hall)? Until then its place on the map is a building site.
function EotwRoster.TownHallBuilt()
    if m_unlocks ~= nil and m_unlocks.townHall == true then
        return true
    end
    local state = EotwDowntime.GetProject("build-town-hall")
    return state ~= nil and (tonumber(state.completions) or 0) >= 1
end

--The lead ids this account has learned, as a set; empty while not listed.
function EotwRoster.LearnedLeads()
    local result = {}
    for _, id in ipairs(m_leads or {}) do
        result[id] = true
    end
    return result
end

--The respite whose one carouse is still open, or nil (none, or nothing
--left to learn; the city decides).
function EotwRoster.CarouseRespite()
    if type(m_carouse) == "string" then
        return m_carouse
    end
    return nil
end

--Record the leads and open carouse the city just reported (list-heroes,
--a respite's grant-downtime, or a carouse). leads may be nil to keep them.
function EotwRoster.SetListedLeads(leads, carouse)
    if type(leads) == "table" then
        local list = {}
        for _, id in ipairs(leads) do
            list[#list+1] = id
        end
        m_leads = list
    end
    --the city sends null (nil here) when no carouse is open.
    m_carouse = cond(type(carouse) == "string", carouse, false)
    Bump()
end

--Has this hero (a hero view from list-heroes) won the named encounter (a
--map name, "Encounter: Goblin Ambush")? The city lists each hero's wins.
function EotwRoster.HasCompleted(hero, encounter)
    for _,name in ipairs(hero ~= nil and hero.completed or {}) do
        if name == encounter then
            return true
        end
    end
    return false
end

--- the Blue Fish Inn: hidden until heroes come home ----------------------

--A new player's town has no inn. It opens once a living hero comes home from
--a Town Gate adventure (won or lost; the Proving Pits send nothing home), and
--the town then plays its reveal once (EncounterOfTheWeek.lua). Per account,
--machine-local, as JSON text: { [userid] = { unlocked = bool, revealed = bool } }.
setting{
    id = "eotw:innState",
    default = "",
    storage = "preference",
}

--Heroes who came home alive this session, in the order their outcomes were
--recorded: { { heroid, damage }, ... }. The inn's reveal picks its speaker here.
local m_homecomings = {}

local function LoadInnStates()
    local all = nil
    local text = dmhub.GetSettingValue("eotw:innState")
    if type(text) == "string" and text ~= "" then
        local parsed = dmhub.FromJson(text)
        if type(parsed) == "table" and parsed.success then
            all = parsed.result
        end
    end
    if type(all) ~= "table" then
        all = {}
    end
    local mine = all[dmhub.loginUserid]
    if type(mine) ~= "table" then
        mine = {}
        all[dmhub.loginUserid] = mine
    end
    return all, mine
end

local function SetInnFlag(key)
    local all, mine = LoadInnStates()
    if mine[key] == true then
        return
    end
    mine[key] = true
    dmhub.SetSettingValue("eotw:innState", dmhub.ToJson(all))
    Bump()
end

--Is the Blue Fish Inn open to this account? Besides the flag a homecoming
--sets on this machine, a roster that has already won an encounter counts,
--so an account that adventured before the inn was hidden (or on another
--machine) keeps it. nil while the roster has not been listed.
function EotwRoster.InnUnlocked()
    local _, mine = LoadInnStates()
    if mine.unlocked == true or mine.revealed == true then
        return true
    end
    if m_heroes == nil then
        return nil
    end
    if EotwRoster.DangerRoomsUnlocked() == true then
        return true
    end
    for _,hero in ipairs(m_heroes) do
        if #(hero.completed or {}) > 0 then
            return true
        end
    end
    return false
end

--Has this machine played the inn's reveal for this account?
function EotwRoster.InnRevealed()
    local _, mine = LoadInnStates()
    return mine.revealed == true
end

function EotwRoster.MarkInnRevealed()
    SetInnFlag("revealed")
end

--This session's homecomings (see m_homecomings), oldest first.
function EotwRoster.Homecomings()
    return m_homecomings
end

--A hero came home alive from a Town Gate adventure: the inn opens.
local function NoteHomecoming(heroid, outcome)
    local wounds = type(outcome) == "table" and outcome.wounds or nil
    local damage = type(wounds) == "table" and tonumber(wounds.damage) or 0
    m_homecomings[#m_homecomings + 1] = { heroid = heroid, damage = damage or 0 }
    SetInnFlag("unlocked")
end

--heroid -> party name for each of this account's heroes claimed by a party
--(forming or underway) in the city's games roster.
function EotwRoster.AwayHeroes()
    local result = {}
    if m_conn == nil then
        return result
    end
    local games = m_conn:GetPath("/state/games") or {}
    for _,record in pairs(games) do
        local player = record.players ~= nil and record.players[dmhub.loginUserid] or nil
        for _,h in ipairs(player ~= nil and player.heroes or {}) do
            if h.kind == "roster" then
                result[h.id] = record.name or T("roster.away.party_fallback")
            end
        end
    end
    return result
end

--Put a working copy in this lobby game's player party. A pregen arrives with
--its module party and a city record with its uploader's lobby party, neither
--of which exists here (the sheet shows "Controlled by: (Invalid)"). The
--import resolves a moment after it is written, hence the short wait.
local function AdoptLobbyParty(charid)
    dmhub.Coroutine(function()
        for i = 1, 50 do
            local tok = dmhub.GetCharacterById(charid)
            local partyid = GetDefaultPartyID()
            if tok ~= nil and partyid ~= nil then
                if tok.partyId ~= partyid then
                    tok.partyId = partyid
                    tok:UploadToken("Join the lobby party")
                end
                return
            end
            coroutine.yield(0.1)
        end
    end)
end

--defined with the coming-home write-back below.
local ApplyPendingOutcomes
local PromoteRosterHeroes
--heroids whose slow-start promotion is being pushed to the city right now.
local m_promoting = {}

--Town heroes are always full level 1 or above. Module pregens are authored on
--the Delian Tomb "slow start" (extraLevelInfo.encounter = 1..4), whose early
--rungs leave out level-1 features such as the heroic abilities; clearing
--.encounter promotes the hero to a full level 1, as the character builder's
--level dropdown does. Only mutates the working copy -- the caller pushes it.
--Returns true if the hero was changed.
local function PromoteSlowStart(tok)
    local props = tok.properties
    if props == nil or props:ExtraLevelInfo().encounter == nil then
        return false
    end
    tok:ModifyProperties{
        description = "Encounter of the Week: full level 1",
        undoable = false,
        execute = function()
            --the field exists (encounter was set), so this is the stored table,
            --not try_get's default; write it back so the clear persists.
            local info = props:ExtraLevelInfo()
            info.encounter = nil
            props.extraLevelInfo = info
        end,
    }
    printf("EotW town: %s promoted from the slow start to full level 1", tostring(tok.name))
    return true
end

--Import one hero's record from the city into its working copy.
local function FetchAndImport(hero)
    local heroid = hero.heroid
    if m_importing[heroid] or m_conn == nil then
        return
    end
    m_importing[heroid] = true
    m_conn:Request{
        action = "get-hero",
        args = { heroid = heroid, asJson = true },
        success = function(result)
            m_importing[heroid] = nil
            if mod.unloaded then
                return
            end
            local charid = dmhub.ImportCharacter{
                record = result.record,
                assets = result.assets,
                charid = heroid,
            }
            if charid == nil then
                Fail(T("roster.error.load_failed", { hero = tostring(hero.summary and hero.summary.name or heroid) }))
                return
            end
            SetRev(heroid, result.rev)
            AdoptLobbyParty(heroid)
            Bump()
            --a won encounter may have been waiting on this copy; the import
            --resolves a moment after it is written.
            dmhub.Schedule(1, function()
                if not mod.unloaded then
                    PromoteRosterHeroes()
                    ApplyPendingOutcomes()
                end
            end)
        end,
        error = function(message)
            m_importing[heroid] = nil
            Fail(message)
        end,
    }
end

--The working copies live in the lobby game, which loads in the background
--after startup: until it has, its characters (and asset records) are not
--there to compare against or import into.
local function LobbyReady()
    return dmhub.inGame and dmhub.isLobbyGame and dmhub.gameLoadingProgress == 1
end

--- coming home: won encounters ------------------------------------------

--Pending outcomes this session is working on right now, and how often each
--has failed (a write the city keeps refusing must not loop forever; the
--next session tries again).
local m_outcomeBusy = {}
local m_outcomeFailures = {}
local MAX_OUTCOME_ATTEMPTS = 3

--Is a returning hero's outcome being carried home right now?
function EotwRoster.OutcomesInFlight()
    return next(m_outcomeBusy) ~= nil
end

local function LoadPendingOutcomes()
    local all = nil
    local text = dmhub.GetSettingValue("eotw:pendingOutcomes")
    if type(text) == "string" and text ~= "" then
        local parsed = dmhub.FromJson(text)
        if type(parsed) == "table" and parsed.success then
            all = parsed.result
        end
    end
    if type(all) ~= "table" then
        all = {}
    end
    local mine = all[dmhub.loginUserid]
    if type(mine) ~= "table" then
        mine = {}
        all[dmhub.loginUserid] = mine
    end
    return all, mine
end

--Move one pending outcome on to `stage`, or drop it (stage nil).
local function SetOutcomeStage(key, stage)
    local all, mine = LoadPendingOutcomes()
    if mine[key] == nil then
        return
    end
    if stage == nil then
        mine[key] = nil
    else
        mine[key].stage = stage
    end
    dmhub.SetSettingValue("eotw:pendingOutcomes", dmhub.ToJson(all))
end

--Analytics: a town hero's class, ancestry and level, for eotw_hero_* events.
local function AnalyticsHero(tok)
    local fields = {}
    pcall(function()
        local props = tok.properties
        local classInfo = props:GetClass()
        fields.heroClass = classInfo ~= nil and classInfo.name or nil
        fields.heroAncestry = props:RaceOrMonsterType()
        fields.heroLevel = props:Level()
    end)
    return fields
end

--Carry one won encounter home: put its Victories on the working copy, push
--the copy to the city, then record the outcome there (which logs the
--adventure and marks the encounter completed for this hero). The copy is
--stamped properties.eotwOutcomes[gameid], and that stamp travels with the
--record, so the Victories are never added twice -- not by a retry, nor by
--another machine. The entry's stage says how far it got ("pushed" skips to
--the record).
--An outcome with `died` set is a hero who fell: it skips the copy and the
--push, and record-outcome {died} buries the hero (fallen, off the roster, a
--grave in the Graveyard); the next re-list drops the working copy.
local function ApplyOutcome(key, entry, tok)
    m_outcomeBusy[key] = true
    local gameid = entry.gameid
    local heroid = entry.heroid
    local died = type(entry.outcome) == "table" and entry.outcome.died == true

    local function Failed(message)
        m_outcomeBusy[key] = nil
        m_outcomeFailures[key] = (m_outcomeFailures[key] or 0) + 1
        Fail(T("roster.error.bring_home_failed", { hero = tostring(tok.name), reason = tostring(message) }))
    end

    local function Record()
        if m_conn == nil then
            Failed(T("roster.error.not_connected"))
            return
        end
        m_conn:Request{
            action = "record-outcome",
            args = { heroid = heroid, gameid = gameid, outcome = entry.outcome, died = died },
            success = function(result)
                m_outcomeBusy[key] = nil
                SetOutcomeStage(key, nil)
                --analytics: what the game brought this hero home with (a
                --death is the burial).
                local fields = AnalyticsHero(tok)
                local o = type(entry.outcome) == "table" and entry.outcome or {}
                fields.heroid = heroid
                fields.runid = gameid
                fields.encounter = o.encounter
                fields.result = o.result
                fields.died = died
                fields.victories = o.victories
                fields.treasures = type(o.treasures) == "table" and #o.treasures or 0
                EotwAnalytics.Track("eotw_hero_outcome", fields)
                if died then
                    printf("EotW town: %s fell and is buried in the Graveyard (%s)", tostring(tok.name), tostring(gameid))
                else
                    printf("EotW town: %s's encounter recorded (%s)", tostring(tok.name), tostring(gameid))
                    NoteHomecoming(heroid, entry.outcome)
                end
                --re-list: the hero's completed encounters changed, or the
                --hero left the roster for the Graveyard.
                EotwRoster.Refresh()
            end,
            error = Failed,
        }
    end

    if died or entry.stage == "pushed" then
        Record()
        return
    end

    local stamped = false
    pcall(function()
        local applied = rawget(tok.properties, "eotwOutcomes")
        stamped = type(applied) == "table" and applied[gameid] == true
    end)
    if not stamped then
        local victories = tonumber(type(entry.outcome) == "table" and entry.outcome.victories or 0) or 0
        --non-consumable treasure the hero won in the encounter (the game
        --records it; consumables stay behind).
        local treasures = type(entry.outcome) == "table" and entry.outcome.treasures or nil
        tok:ModifyProperties{
            description = "Victory from Encounter of the Week",
            undoable = false,
            execute = function()
                local props = tok.properties
                if victories > 0 then
                    props:SetVictories(props:GetVictories() + victories)
                end
                for _, t in ipairs(type(treasures) == "table" and treasures or {}) do
                    local qty = math.floor(tonumber(t.quantity) or 0)
                    if type(t.itemid) == "string" and qty > 0 then
                        local ok, err = pcall(function() props:GiveItem(t.itemid, qty) end)
                        if ok then
                            printf("EotW town: %s brings home %s", tostring(tok.name), tostring(t.name))
                            --equippable treasure is put on while there is room
                            --(user direction 2026-10-19), as it was in the game.
                            for _ = 1, qty do
                                local equipped = nil
                                pcall(function() equipped = EotwHeroSheet.EquipInPlace(tok, t.itemid) end)
                                if equipped == nil then
                                    break
                                end
                            end
                        else
                            printf("EotW town: could not give %s to %s: %s", tostring(t.name), tostring(tok.name), tostring(err))
                        end
                    end
                end
                --the hero's wounds come home with them (Downtime): only a
                --respite at the Blue Fish Inn heals them.
                local wounds = type(entry.outcome) == "table" and entry.outcome.wounds or nil
                if type(wounds) == "table" then
                    EotwRoster.SetWounds(props, wounds.damage, wounds.recoveriesUsed)
                end
                --Secret Twin: the assassin came for them (EncounterMontage),
                --so their past has caught up; the next respite rolls again.
                if type(entry.outcome) == "table" and entry.outcome.assassinMet then
                    props[EotwDowntime.ASSASSIN_FIELD] = nil
                end
                local applied = {}
                local old = rawget(props, "eotwOutcomes")
                if type(old) == "table" then
                    for k,v in pairs(old) do
                        applied[k] = v
                    end
                end
                applied[gameid] = true
                props.eotwOutcomes = applied
            end,
        }
        printf("EotW town: %s gains %d Victory", tostring(tok.name), victories)
    end

    --the property write applies locally at once; give it a beat so the
    --export carries it (as JoinRoster does), then push.
    dmhub.Schedule(0.3, function()
        if mod.unloaded then
            return
        end
        EotwRoster.PushHero(heroid, function(ok, message)
            if not ok then
                Failed(message)
                return
            end
            SetOutcomeStage(key, "pushed")
            Record()
        end)
    end)
end

--Set a hero's lost Stamina and spent Recoveries to the given values (the
--state they ended an encounter in). Call inside ModifyProperties.
function EotwRoster.SetWounds(props, damage, recoveriesUsed)
    damage = math.max(0, math.floor(tonumber(damage) or 0))
    props.damage_taken = damage
    local id = CharacterResource.recoveryResourceId
    local want = math.max(0, math.floor(tonumber(recoveriesUsed) or 0))
    local used = props:GetResourceUsage(id, "long") or 0
    if want > used then
        props:ConsumeResource(id, "long", want - used, "Spent in the encounter")
    elseif want < used then
        props:RefreshResource(id, "long", used - want, "Encounter of the Week")
    end
end

--Apply every pending outcome whose hero's working copy is in step with the
--city (an import in flight would overwrite the Victories). A hero the city
--no longer lists -- dismissed, or fallen -- has nothing to apply to.
ApplyPendingOutcomes = function()
    if m_heroes == nil or m_conn == nil then
        return
    end
    local revs = GetRevs()
    local _, mine = LoadPendingOutcomes()
    --one outcome per hero at a time: each pushes the hero, and two pushes
    --from the same revision collide (a series played on in one game leaves
    --one outcome per part). The next goes once the re-list comes back.
    local heroBusy = {}
    for key, entry in pairs(mine) do
        if m_outcomeBusy[key] and type(entry) == "table" and type(entry.heroid) == "string" then
            heroBusy[entry.heroid] = true
        end
    end
    for key, entry in pairs(mine) do
        if type(entry) ~= "table" or type(entry.heroid) ~= "string" or type(entry.gameid) ~= "string" then
            SetOutcomeStage(key, nil)
        elseif not m_outcomeBusy[key] and not heroBusy[entry.heroid] and (m_outcomeFailures[key] or 0) < MAX_OUTCOME_ATTEMPTS then
            if EotwRoster.FindHero(entry.heroid) == nil then
                printf("EotW town: hero %s is no longer in the roster; dropping its outcome", entry.heroid)
                SetOutcomeStage(key, nil)
            else
                local tok = dmhub.GetCharacterById(entry.heroid)
                local hero = EotwRoster.FindHero(entry.heroid)
                if tok ~= nil and hero ~= nil and revs[entry.heroid] == hero.rev and not m_importing[entry.heroid] and not m_promoting[entry.heroid] then
                    heroBusy[entry.heroid] = true
                    ApplyOutcome(key, entry, tok)
                end
            end
        end
    end
end

--Promote roster heroes recruited before PromoteSlowStart ran at recruit
--time, then push them. Only copies in step with the city (an import in flight
--would overwrite the change). A hero with an outcome still to push is changed
--but not pushed here: that outcome's push carries it, and two pushes from the
--same base revision would collide.
PromoteRosterHeroes = function()
    if m_heroes == nil or m_conn == nil then
        return
    end
    local revs = GetRevs()
    local outcomeWillPush = {}
    local _, pending = LoadPendingOutcomes()
    for _, entry in pairs(pending) do
        if type(entry) == "table" and type(entry.heroid) == "string" and entry.stage ~= "pushed" then
            outcomeWillPush[entry.heroid] = true
        end
    end
    for _, hero in ipairs(m_heroes) do
        local heroid = hero.heroid
        local tok = dmhub.GetCharacterById(heroid)
        if tok ~= nil and revs[heroid] == hero.rev and not m_importing[heroid] and not m_promoting[heroid] and PromoteSlowStart(tok) then
            if not outcomeWillPush[heroid] then
                m_promoting[heroid] = true
                --as in JoinRoster: let the write land before the export.
                dmhub.Schedule(0.3, function()
                    if mod.unloaded then
                        return
                    end
                    EotwRoster.PushHero(heroid, function()
                        m_promoting[heroid] = nil
                    end)
                end)
            end
        end
    end
end

--Bring the lobby working copies in line with the city's roster.
local function SyncWorkingCopies()
    if not LobbyReady() then
        dmhub.Schedule(1, function()
            if not mod.unloaded then
                SyncWorkingCopies()
            end
        end)
        return
    end
    local revs = GetRevs()
    local listed = {}
    for _,hero in ipairs(m_heroes or {}) do
        listed[hero.heroid] = true
        local tok = dmhub.GetCharacterById(hero.heroid)
        if tok == nil or revs[hero.heroid] ~= hero.rev then
            FetchAndImport(hero)
        elseif tok.partyId ~= GetDefaultPartyID() then
            AdoptLobbyParty(hero.heroid)
        end
    end

    --a town hero the city no longer lists was dismissed (on this machine or
    --another) or has fallen: drop its working copy. One with no synced
    --revision never reached the city at all, so it is pushed instead.
    local remove = {}
    for _,tok in ipairs(table.values(dmhub.GetAllCharacters())) do
        local charid = tok.charid
        if charid ~= nil and IsTownHero(tok) and not listed[charid] and not m_pendingCreates[charid] then
            if revs[charid] ~= nil then
                remove[#remove+1] = charid
            else
                m_pendingCreates[charid] = true
                EotwRoster.PushHero(charid, function()
                    m_pendingCreates[charid] = nil
                end)
            end
        end
    end
    if #remove > 0 then
        game.DeleteCharacters(remove)
        Bump()
    end

    PromoteRosterHeroes()
    --encounters won since the last visit: Victories onto the heroes.
    ApplyPendingOutcomes()
end

--Queue won encounters for heroes to bring home -- the same queue the game
--fills at a victory (eotw:pendingOutcomes) -- and start applying them.
--entries: { { gameid, heroid, outcome }, ... }. Used for results a game's
--host left with the city while this player was away (see the town's
--"While You Were Away").
function EotwRoster.AddPendingOutcomes(entries)
    local all, mine = LoadPendingOutcomes()
    for _, entry in ipairs(entries) do
        mine[entry.gameid .. "|" .. entry.heroid] = {
            gameid = entry.gameid,
            heroid = entry.heroid,
            stage = "new",
            outcome = entry.outcome,
        }
    end
    dmhub.SetSettingValue("eotw:pendingOutcomes", dmhub.ToJson(all))
    ApplyPendingOutcomes()
end

--Send the Hall of Heroes entries a hosted game left behind (eotw:pendingHall),
--each once per town visit; drop each once the city has answered, accepted
--or refused (the city keeps one entry per game, so a resend is harmless).
local m_hallSending = {}
local function FlushPendingHall()
    if m_conn == nil then
        return
    end
    local text = dmhub.GetSettingValue("eotw:pendingHall")
    if type(text) ~= "string" or text == "" then
        return
    end
    --FromJson answers {success, result}, not the decoded value.
    local parsed = dmhub.FromJson(text)
    if type(parsed) ~= "table" or not parsed.success or type(parsed.result) ~= "table" then
        return
    end
    local mine = parsed.result[dmhub.loginUserid]
    if type(mine) ~= "table" then
        return
    end
    for gameid, entry in pairs(mine) do
        if not m_hallSending[gameid] and type(entry) == "table" then
            m_hallSending[gameid] = true
            local function Done()
                local now = dmhub.FromJson(dmhub.GetSettingValue("eotw:pendingHall") or "")
                if type(now) == "table" and now.success and type(now.result) == "table" then
                    local all = now.result
                    if type(all[dmhub.loginUserid]) == "table" then
                        all[dmhub.loginUserid][gameid] = nil
                        if next(all[dmhub.loginUserid]) == nil then
                            all[dmhub.loginUserid] = nil
                        end
                    end
                    dmhub.SetSettingValue("eotw:pendingHall", cond(next(all) == nil, "", dmhub.ToJson(all)))
                end
            end
            m_conn:Request{
                action = "hall-record",
                args = entry,
                success = function()
                    printf("EotW town: sent the Hall of Heroes entry for game %s", tostring(gameid))
                    Done()
                end,
                error = function(message)
                    printf("EotW town: the Hall of Heroes refused game %s: %s", tostring(gameid), tostring(message))
                    Done()
                end,
            }
        end
    end
end

--Re-list this account's roster from the city (and sync the working copies).
function EotwRoster.Refresh()
    if m_conn == nil or not m_conn.connected then
        return
    end
    if m_refreshing then
        m_refreshAgain = true
        return
    end
    m_refreshing = true
    m_conn:Request{
        action = "list-heroes",
        success = function(result)
            m_refreshing = false
            if mod.unloaded then
                return
            end
            local heroes = {}
            for _,hero in ipairs(result.heroes or {}) do
                heroes[#heroes+1] = hero
            end
            m_heroes = heroes
            m_unlocks = type(result.unlocks) == "table" and result.unlocks or {}
            m_slots = tonumber(result.slots) or EotwRoster.BASE_SLOTS
            EotwRoster.SetListedLeads(result.leads, result.carouse)
            Bump()
            SyncWorkingCopies()
            FlushPendingHall()
            if m_refreshAgain then
                m_refreshAgain = false
                EotwRoster.Refresh()
            end
        end,
        error = function(message)
            m_refreshing = false
            Fail(message)
        end,
    }
end

--- writes -----------------------------------------------------------------

--Pushes waiting for the city's reply, by hero. Two pushes in flight would
--send the same baseRev and the city would reject the later one as stale, so
--a push asked for meanwhile waits and runs once the first lands.
--heroid -> { again = bool, waiting = { onDone... } }
local m_pushing = {}

--Push a working copy to the city: creates the hero there the first time,
--replaces it afterwards (revision-checked). onDone(ok, message) optional.
function EotwRoster.PushHero(charid, onDone)
    local inFlight = m_pushing[charid]
    if inFlight ~= nil then
        inFlight.again = true
        if onDone ~= nil then
            inFlight.waiting[#inFlight.waiting+1] = onDone
        end
        return
    end

    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or m_conn == nil then
        if onDone ~= nil then
            onDone(false, T("roster.error.not_connected"))
        end
        return
    end
    local data = dmhub.ExportCharacter(tok)
    if data == nil then
        Fail(T("roster.error.export_failed"))
        if onDone ~= nil then
            onDone(false, T("roster.error.export_failed_reason"))
        end
        return
    end
    local baseRev = GetRevs()[charid] or 0
    local state = { again = false, waiting = {} }
    m_pushing[charid] = state

    --the push landed or failed: let a push asked for meanwhile go (with the new
    --rev), or after a failure tell its callers it did not happen
    local function Settle(ok, message)
        m_pushing[charid] = nil
        if ok and state.again then
            EotwRoster.PushHero(charid, function(againOk, againMessage)
                for _,fn in ipairs(state.waiting) do
                    fn(againOk, againMessage)
                end
            end)
            return
        end
        for _,fn in ipairs(state.waiting) do
            fn(ok, message)
        end
    end

    m_conn:Request{
        action = "put-hero",
        args = {
            heroid = charid,
            baseRev = baseRev,
            summary = BuildSummary(tok),
            record = data.record,
            assets = data.assets,
        },
        success = function(result)
            SetRev(charid, result.rev)
            EotwRoster.lastError = nil
            Settle(true)
            EotwRoster.Refresh()
            if onDone ~= nil then
                onDone(true)
            end
        end,
        error = function(message)
            Fail(message)
            Settle(false, message)
            --a stale revision means another machine saved this hero first:
            --reload the city's copy.
            EotwRoster.Refresh()
            if onDone ~= nil then
                onDone(false, message)
            end
        end,
    }
end

--Run fn once the character resolves in the lobby game (a create or an
--import lands through a server echo).
local function WhenCharacterExists(charid, fn)
    dmhub.Coroutine(function()
        for _ = 1, 200 do
            if mod.unloaded then
                return
            end
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil then
                fn(tok)
                return
            end
            coroutine.yield(0.05)
        end
        Fail(T("roster.error.never_appeared"))
    end)
end

--Tag a lobby character as a town hero and push it to the city as new.
--how ("pregen" | "titlescreen" | "built") says where the hero came from.
local function JoinRoster(tok, onDone, how)
    local charid = tok.charid
    m_pendingCreates[charid] = true
    AdoptLobbyParty(charid)
    tok:ModifyProperties{
        description = "Join the Blackbottom roster",
        undoable = false,
        execute = function()
            tok.properties.eotwHero = true
            tok.properties.creatorid = dmhub.userid
            tok.properties.originalid = charid
            tok.properties.mtime = ServerTimestamp()
            --a complication's picked trinket (Secret Twin) is in hand
            EotwBuild.SyncTreasureGrants(tok)
        end,
    }
    --a recruited pregen arrives on the slow start.
    PromoteSlowStart(tok)
    --the property write applies locally at once; give it a beat so the
    --export carries it, then push.
    dmhub.Schedule(0.3, function()
        if mod.unloaded then
            return
        end
        EotwRoster.PushHero(charid, function(ok, message)
            m_pendingCreates[charid] = nil
            if ok then
                local fields = AnalyticsHero(tok)
                fields.how = how
                fields.heroid = charid
                fields.roster = EotwRoster.LivingCount()
                EotwAnalytics.Track("eotw_hero_recruit", fields)
            end
            if not ok then
                --the city refused it (e.g. the roster is full): this machine
                --must not keep a town hero the city does not know about.
                game.DeleteCharacters({charid})
            elseif #EotwRoster.ActiveHeroes() < EotwRoster.MAX_ACTIVE then
                --a new hero starts out active while there is room.
                EotwRoster.SetActive(charid, true)
            end
            if onDone ~= nil then
                onDone(ok, message)
            end
        end)
    end)
end

function EotwRoster.CanAddHero()
    return EotwRoster.LivingCount() < EotwRoster.Slots()
end

--Why a hero cannot be added: the roster fills every slot.
function EotwRoster.FullRosterMessage()
    if EotwRoster.Slots() >= EotwRoster.MAX_SLOTS then
        return T("guild.full.max", { slots = EotwRoster.Slots() })
    end
    return T("guild.full.slots", { slots = EotwRoster.Slots() })
end

--The player's unfinished hero, if any: a lobby character the EotW builder
--is working on, tagged properties.eotwDraft. It never reaches the city and
--does not count against the roster limit. One per player.
function EotwRoster.FindDraft()
    for _,tok in ipairs(table.values(dmhub.GetAllCharacters())) do
        local isDraft = false
        pcall(function()
            local props = tok.properties
            isDraft = rawget(props, "eotwDraft") == true and rawget(props, "creatorid") == dmhub.userid
        end)
        if isDraft then
            return tok
        end
    end
    return nil
end

--Throw away the player's unfinished hero.
function EotwRoster.DiscardDraft()
    local draft = EotwRoster.FindDraft()
    if draft ~= nil then
        game.DeleteCharacters({draft.charid})
        Bump()
    end
end

--Open the EotW builder on the draft. Finishing it joins the roster;
--closing keeps it as the draft, unless nothing was chosen at all.
local function OpenDraft(host, tok, onDone)
    if host == nil or not host.valid then
        return
    end
    EotwBuilder.Open{
        host = host,
        token = tok,
        onFinish = function(t)
            t:ModifyProperties{
                description = "Finish the hero",
                undoable = false,
                execute = function()
                    t.properties.eotwDraft = false
                end,
            }
            JoinRoster(t, onDone, "built")
            Bump()
        end,
        onClose = function(t)
            if EotwBuild.IsUnstarted(t) then
                game.DeleteCharacters({t.charid})
            end
            Bump()
        end,
    }
end

--Build a new hero in the EotW builder (or carry on with the draft); it
--joins the roster when the player finishes it. host is the panel the
--builder mounts on (the town screen).
function EotwRoster.CreateHero(host, onDone)
    if not EotwRoster.CanAddHero() then
        Fail(EotwRoster.FullRosterMessage())
        return
    end
    local draft = EotwRoster.FindDraft()
    if draft ~= nil then
        OpenDraft(host, draft, onDone)
        return
    end
    local heroType = nil
    for _,v in pairs(dmhub.GetTable(CharacterType.tableName) or {}) do
        if not rawget(v, "hidden") and v.name == "Hero" then
            heroType = v
            break
        end
    end
    if heroType == nil then
        Fail(T("roster.error.no_hero_type"))
        return
    end
    local charid = game.CreateCharacter("character", heroType)
    WhenCharacterExists(charid, function(tok)
        tok:ModifyProperties{
            description = "Start a hero",
            undoable = false,
            execute = function()
                tok.properties.mtime = ServerTimestamp()
                tok.properties.originalid = charid
                tok.properties.creatorid = dmhub.userid
                tok.properties.eotwDraft = true
            end,
        }
        Bump()
        OpenDraft(host, tok, onDone)
    end)
end

--Whether a roster hero may be rebuilt in the EotW builder: any time they are
--home in Blackbottom (on the roster and not away in a party now).
function EotwRoster.CanRebuildHero(heroid)
    return EotwRoster.FindHero(heroid) ~= nil and EotwRoster.AwayHeroes()[heroid] == nil
end

--Recruit a pregen: copy the module's pregen into the lobby game under the
--player's chosen name, then add it to the roster.
function EotwRoster.RecruitPregen(pregenId, name, onDone)
    if not EotwRoster.CanAddHero() then
        Fail(EotwRoster.FullRosterMessage())
        return
    end
    local source = EncounterOfTheWeek.GetPregenToken(pregenId)
    if source == nil then
        Fail(T("roster.error.pregen_unavailable"))
        return
    end
    local data = dmhub.ExportCharacter(source)
    if data == nil then
        Fail(T("roster.error.pregen_copy_failed"))
        return
    end
    local charid = dmhub.ImportCharacter{
        record = data.record,
        assets = data.assets,
        name = name,
    }
    if charid == nil then
        Fail(T("roster.error.pregen_copy_failed"))
        return
    end
    m_pendingCreates[charid] = true
    WhenCharacterExists(charid, function(tok)
        JoinRoster(tok, onDone, "pregen")
    end)
end

--The living roster hero copied from this titlescreen hero, if any (the copy
--carries properties.eotwSourceId = the titlescreen hero's charid).
function EotwRoster.FindCopyOf(sourceCharid)
    for _,tok in ipairs(table.values(dmhub.GetAllCharacters())) do
        local match = false
        pcall(function()
            match = IsTownHero(tok) and rawget(tok.properties, "eotwSourceId") == sourceCharid
        end)
        if match and EotwRoster.FindHero(tok.charid) ~= nil then
            return tok
        end
    end
    return nil
end

--Recruit one of the player's own titlescreen heroes: a COPY joins the town
--roster, and the titlescreen hero is never touched. Town heroes start fresh,
--so the copy comes in at level 1 (as NormalizeHeroLevel does in an EotW
--game) with no items (treasure is earned in town); its kit is kept.
function EotwRoster.RecruitTitlescreenHero(source, name, onDone)
    if not EotwRoster.CanAddHero() then
        Fail(EotwRoster.FullRosterMessage())
        return
    end
    if source == nil or not source.valid then
        Fail(T("roster.error.hero_unavailable"))
        return
    end
    local sourceid = source.charid
    local data = dmhub.ExportCharacter(source)
    if data == nil then
        Fail(T("roster.error.hero_copy_failed"))
        return
    end
    local charid = dmhub.ImportCharacter{
        record = data.record,
        assets = data.assets,
        name = name,
    }
    if charid == nil then
        Fail(T("roster.error.hero_copy_failed"))
        return
    end
    m_pendingCreates[charid] = true
    WhenCharacterExists(charid, function(tok)
        tok:ModifyProperties{
            description = "Encounter of the Week: a fresh copy",
            undoable = false,
            execute = function()
                local props = tok.properties
                props.eotwSourceId = sourceid
                --the copy still names the original as its lobby-sync source;
                --JoinRoster re-points it, but do it here too so nothing ever
                --saves this stripped copy over the original's char-cache.
                props.originalid = charid
                --level 1: CharacterLevel() is max(class levels, levelOverride).
                if props:try_get("levelOverride", 1) ~= 1 then
                    props.levelOverride = 1
                end
                for _,entry in ipairs(props:try_get("classes", {})) do
                    entry.level = 1
                end
                --no items: the pack and every equipment slot.
                props.inventory = {}
                props.equipment = {}
                props.equipmentMeta = {}
                --a complication's trinket is part of the build, not earned
                --treasure: unclaim it so JoinRoster hands it over again.
                for _,state in pairs(props:try_get("treasureGrants", {})) do
                    if type(state) == "table" then
                        state.claimed = false
                        state.eotwGiven = nil
                    end
                end
            end,
        }
        JoinRoster(tok, onDone, "titlescreen")
    end)
end

--Open a roster hero: in the EotW builder when it can be rebuilt (home, not
--away in a party, and a host to mount on is given), otherwise in the EotW
--hero sheet.
function EotwRoster.EditHero(heroid, host)
    local tok = dmhub.GetCharacterById(heroid)
    if tok == nil then
        Fail(T("roster.error.not_loaded"))
        return
    end
    if host ~= nil and host.valid and EotwRoster.CanRebuildHero(heroid) then
        local Save = function()
            EotwRoster.PushHero(heroid)
        end
        EotwBuilder.Open{
            host = host,
            token = tok,
            title = T("guild.rebuild_title"),
            --a created hero keeps the Ancestry and Class it was made with
            lockedSteps = { ancestry = true, class = true },
            onFinish = Save,
            onClose = Save,
        }
        return
    end
    --when it cannot be rebuilt, a roster Hero opens the EotW hero sheet, not the full
    --editable sheet; its own controls (equip, spend a Recovery, appearance)
    --push the Hero to the City themselves
    EotwHeroSheet.Show{ charid = heroid, context = "town" }
end

--Dismiss a hero: gone from the city, then from this machine.
function EotwRoster.DismissHero(heroid, onDone)
    if m_conn == nil then
        return
    end
    local dismissed = dmhub.GetCharacterById(heroid)
    local fields = dismissed ~= nil and AnalyticsHero(dismissed) or {}
    fields.heroid = heroid
    m_conn:Request{
        action = "delete-hero",
        args = { heroid = heroid },
        success = function()
            EotwAnalytics.Track("eotw_hero_dismiss", fields)
            if dmhub.GetCharacterById(heroid) ~= nil then
                game.DeleteCharacters({heroid})
            end
            EotwRoster.Refresh()
            if onDone ~= nil then
                onDone(true)
            end
        end,
        error = function(message)
            Fail(message)
            if onDone ~= nil then
                onDone(false, message)
            end
        end,
    }
end

--Make a hero active or inactive (at most MAX_ACTIVE active).
function EotwRoster.SetActive(heroid, active)
    if m_conn == nil then
        return
    end
    local ids = {}
    for _,hero in ipairs(EotwRoster.ActiveHeroes()) do
        if hero.heroid ~= heroid then
            ids[#ids+1] = hero.heroid
        end
    end
    if active then
        if #ids >= EotwRoster.MAX_ACTIVE then
            Fail(T("guild.error.max_active", { max = EotwRoster.MAX_ACTIVE }))
            return
        end
        ids[#ids+1] = heroid
    end
    m_conn:Request{
        action = "set-active",
        args = { heroids = ids },
        success = function()
            EotwRoster.Refresh()
        end,
        error = Fail,
    }
end

--One page of the Hall of Heroes. args {encounter?, sort?, offset?, limit?};
--onDone(result) with {entries, more, encounters, sort} (see the city's list-hall).
function EotwRoster.ListHall(args, onDone)
    if m_conn == nil then
        return
    end
    m_conn:Request{
        action = "list-hall",
        args = args,
        success = onDone,
        error = Fail,
    }
end

--One Hall of Heroes entry with its saved victory screen. onDone(result) with
--the entry's fields plus `snapshot`; onFail(message) optional.
function EotwRoster.GetHallEntry(gameid, onDone, onFail)
    if m_conn == nil then
        return
    end
    m_conn:Request{
        action = "get-hall-entry",
        args = { gameid = gameid },
        success = onDone,
        error = function(message)
            Fail(message)
            if onFail ~= nil then
                onFail(message)
            end
        end,
    }
end

--One page of the shared graveyard. onDone(result) with {graves, more}.
function EotwRoster.ListGraveyard(before, onDone)
    if m_conn == nil then
        return
    end
    m_conn:Request{
        action = "list-graveyard",
        args = { before = before, limit = 50 },
        success = onDone,
        error = Fail,
    }
end

--- shared UI bits ---------------------------------------------------------

local TEXT = "#efe4cc"
local DIM = "#c9bfa9"

local function ModalFrame(args)
    local panel
    panel = gui.Panel{
        floating = true,
        width = args.width,
        height = args.height,
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        --opaque: near-opaque alphas (f8) still let the town map show through.
        bgcolor = "#14110dff",
        borderWidth = 2,
        borderColor = "#8c7a55",
        cornerRadius = 10,
        flow = "vertical",
        styles = { Styles.Default },
        captureEscape = true,
        --above the town screen's own escape, which would close the town.
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            element:DestroySelf()
        end,
        children = args.children,
    }
    return panel
end

local function Title(text, subtitle)
    local children = {
        gui.Label{
            text = text,
            fontSize = 34,
            bold = true,
            color = TEXT,
            width = "auto",
            height = "auto",
            halign = "center",
            tmargin = 16,
        },
    }
    if subtitle ~= nil then
        children[#children+1] = gui.Label{
            text = subtitle,
            fontSize = 18,
            italics = true,
            color = DIM,
            width = "90%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            vmargin = 4,
        }
    end
    return children
end

local function Button(text, click, width)
    return gui.Button{
        text = text,
        fontSize = 20,
        width = width or 200,
        height = 44,
        hmargin = 6,
        click = click,
    }
end

--A portrait thumbnail from a character's portrait id (or a silhouette).
--click (optional): what clicking the portrait does.
local function Portrait(portrait, width, height, halign, click)
    if type(portrait) == "string" and portrait ~= "" then
        return gui.Panel{
            interactable = click ~= nil,
            click = click,
            width = width,
            height = height,
            halign = halign,
            valign = "center",
            bgimage = portrait,
            bgcolor = "white",
            cornerRadius = 6,
        }
    end
    return gui.Panel{
        interactable = click ~= nil,
        click = click,
        width = width,
        height = height,
        halign = halign,
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#ffffff10",
        cornerRadius = 6,
        gui.Panel{
            interactable = false,
            width = "60%",
            height = "100% width",
            halign = "center",
            valign = "center",
            bgimage = "phosphor/user-fill.png",
            bgcolor = "#ffffff2a",
        },
    }
end

--- the Hero's Guild ---------------------------------------------------------

--A fresh name for a recruit from its ancestry's name generator, or the
--pregen's own name when the ancestry has none.
local function RecruitName(pregen)
    local tok = EncounterOfTheWeek.GetPregenToken(pregen.id)
    local name = nil
    if tok ~= nil then
        name = EotwBuild.GenerateName(tok.properties --[[@as character]])
    end
    return name or pregen.name or ""
end

--The name prompt for a recruit. recruit = {
--  initialName = the prefilled name,
--  rollName = function() -> a fresh name (the reroll button),
--  prompt = the line under the title,
--  confirm = function(name, onDone) that does the recruiting }.
local function ShowRecruitNamePrompt(host, recruit, onDone)
    local nameInput = nil
    local dlg
    local Confirm = function()
        local name = ((nameInput ~= nil and nameInput.text) or ""):match("^%s*(.-)%s*$")
        if name == "" then
            return
        end
        recruit.confirm(name, onDone)
        dlg:DestroySelf()
    end
    dlg = ModalFrame{
        width = 560,
        height = 300,
        children = {
            gui.Label{
                text = T("guild.name_prompt.title"),
                fontSize = 30,
                bold = true,
                color = TEXT,
                width = "auto",
                height = "auto",
                halign = "center",
                tmargin = 18,
            },
            gui.Label{
                text = recruit.prompt,
                fontSize = 17,
                color = DIM,
                width = "90%",
                height = "auto",
                halign = "center",
                textAlignment = "center",
                vmargin = 8,
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                vmargin = 10,
                flow = "horizontal",
                gui.Input{
                    width = 380,
                    height = 40,
                    valign = "center",
                    fontSize = 22,
                    characterLimit = 60,
                    placeholderText = T("guild.name_prompt.placeholder"),
                    create = function(element)
                        nameInput = element
                        element.text = recruit.initialName or ""
                        element.hasInputFocus = true
                    end,
                    submit = function(element)
                        Confirm()
                    end,
                },
                --rolls another name from the ancestry's name table.
                gui.Panel{
                    width = 32,
                    height = 32,
                    valign = "center",
                    lmargin = 10,
                    bgimage = "phosphor/arrow-clockwise.png",
                    bgcolor = DIM,
                    styles = {
                        {
                            selectors = { "hover" },
                            bgcolor = "#ffffff",
                            scale = 1.12,
                        },
                    },
                    linger = function(element)
                        gui.Tooltip(T("guild.name_prompt.reroll_tooltip"))(element)
                    end,
                    press = function()
                        audio.FireSoundEvent("Mouse.Click")
                        if nameInput ~= nil and nameInput.valid then
                            nameInput.text = recruit.rollName()
                        end
                    end,
                },
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "bottom",
                bmargin = 18,
                flow = "horizontal",
                Button(T("guild.name_prompt.recruit_button"), Confirm, 160),
                Button(T("guild.name_prompt.cancel_button"), function() dlg:DestroySelf() end, 160),
            },
        },
    }
    host:AddChild(dlg)
end

--The recruit picker's card styles. The picker mounts on the town screen,
--outside the Guild list that carries GUILD_STYLES, so it brings its own.
local PICKER_STYLES = {
    {
        selectors = { "eotwGuildPick" },
        bgcolor = "#ffffff0c",
    },
    {
        selectors = { "eotwGuildPick", "hover" },
        bgcolor = "#ffffff20",
        brightness = 1.1,
    },
    --a card that cannot be picked (that hero is already in the roster).
    {
        selectors = { "eotwGuildPick", "blocked", "hover" },
        bgcolor = "#ffffff0c",
        brightness = 1,
    },
}

--One card in the recruit picker. blockedText, when set, greys the card out
--and says why it cannot be picked.
local function RecruitCard(portrait, name, details, press, blockedText)
    local art = Portrait(portrait, 150, 190, "center")
    if blockedText ~= nil and type(portrait) == "string" and portrait ~= "" then
        --the tint's alpha fades the portrait image itself.
        art.selfStyle.bgcolor = "#ffffff59"
    end
    return gui.Panel{
        classes = { "eotwGuildPick", cond(blockedText ~= nil, "blocked", nil) },
        width = 170,
        height = 250,
        hmargin = 6,
        vmargin = 6,
        flow = "vertical",
        bgimage = "panels/square.png",
        cornerRadius = 8,
        press = function()
            if blockedText ~= nil then
                return
            end
            audio.FireSoundEvent("Mouse.Click")
            press()
        end,
        art,
        gui.Label{
            interactable = false,
            text = name,
            fontSize = 16,
            bold = true,
            color = cond(blockedText ~= nil, DIM, TEXT),
            width = "96%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            textWrap = false,
            minFontSize = 10,
        },
        gui.Label{
            interactable = false,
            text = blockedText or details,
            fontSize = 12,
            color = DIM,
            width = "96%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            textWrap = false,
            minFontSize = 8,
        },
    }
end

--A character's portrait id, or nil.
local function PortraitOf(tok)
    local portrait = nil
    pcall(function()
        if tok == nil then return end
        local p = tok.offTokenPortrait
        if type(p) == "string" then
            portrait = p
        end
    end)
    return portrait
end

--A section heading inside the recruit picker.
local function PickerHeading(text, subtitle)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 10,
        bmargin = 4,
        gui.Label{
            text = text,
            fontSize = 22,
            bold = true,
            color = TEXT,
            width = "auto",
            height = "auto",
            lmargin = 8,
        },
        gui.Label{
            text = subtitle,
            fontSize = 15,
            italics = true,
            color = DIM,
            width = "100%-16",
            height = "auto",
            lmargin = 8,
        },
    }
end

local function CardGrid(cards)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        children = cards,
    }
end

--The recruit picker: the player's own titlescreen heroes (copied in at
--level 1 with no items), then every pregenerated hero of the week's module,
--then the pregens of the player's Hero modules, one section per module.
local function ShowRecruitPicker(host, onDone)
    local pregens = EncounterOfTheWeek.GetPregens()
    local dlg

    local ownCards = {}
    for _,tok in ipairs(TitlescreenHeroes.List()) do
        local className, ancestry, level = EotwRoster.HeroDetails(tok)
        local name = tok.name
        if name == nil or name == "" then
            name = T("guild.picker.unnamed_hero")
        end
        local blocked = nil
        if EotwRoster.FindCopyOf(tok.charid) ~= nil then
            blocked = T("guild.picker.already_in_roster")
        end
        ownCards[#ownCards+1] = RecruitCard(PortraitOf(tok), name, EotwRoster.FormatDetails(level, ancestry, className), function()
            dlg:DestroySelf()
            ShowRecruitNamePrompt(host, {
                initialName = name,
                rollName = function()
                    return EotwBuild.GenerateName(tok.properties --[[@as character]]) or name
                end,
                prompt = T("guild.name_prompt.copy", { name = name, details = EotwRoster.FormatDetails(1, ancestry, className) }),
                confirm = function(newName, done)
                    EotwRoster.RecruitTitlescreenHero(tok, newName, done)
                end,
            }, onDone)
        end, blocked)
    end

    local pregenCards = {}
    --Hero module name -> its pregens' cards, and the names in first-seen order.
    local heroModuleCards = {}
    local heroModuleNames = {}
    for _,pregen in ipairs(pregens or {}) do
        local tok = EncounterOfTheWeek.GetPregenToken(pregen.id)
        local cards = pregenCards
        if pregen.source ~= nil then
            cards = heroModuleCards[pregen.source]
            if cards == nil then
                cards = {}
                heroModuleCards[pregen.source] = cards
                heroModuleNames[#heroModuleNames+1] = pregen.source
            end
        end
        cards[#cards+1] = RecruitCard(PortraitOf(tok), pregen.name, EotwRoster.FormatDetails(pregen.level, pregen.ancestry, pregen.className), function()
            dlg:DestroySelf()
            ShowRecruitNamePrompt(host, {
                initialName = RecruitName(pregen),
                rollName = function()
                    return RecruitName(pregen)
                end,
                prompt = T("guild.name_prompt.pregen", { details = EotwRoster.FormatDetails(pregen.level, pregen.ancestry, pregen.className) }),
                confirm = function(name, done)
                    EotwRoster.RecruitPregen(pregen.id, name, done)
                end,
            }, onDone)
        end)
    end

    local sections = {}
    if #ownCards > 0 then
        sections[#sections+1] = PickerHeading(T("guild.picker.own_heading"), T("guild.picker.own_subtitle"))
        sections[#sections+1] = CardGrid(ownCards)
    end
    sections[#sections+1] = PickerHeading(T("guild.picker.hire_heading"), T("guild.picker.hire_subtitle"))
    if pregens == nil then
        sections[#sections+1] = gui.Label{ text = T("guild.picker.pregens_loading"), fontSize = 18, color = DIM, width = "90%", height = "auto", halign = "center", textAlignment = "center", vmargin = 40 }
    else
        sections[#sections+1] = CardGrid(pregenCards)
    end
    for _,source in ipairs(heroModuleNames) do
        sections[#sections+1] = PickerHeading(source, T("guild.picker.module_subtitle"))
        sections[#sections+1] = CardGrid(heroModuleCards[source])
    end

    local body = gui.Panel{
        width = "96%",
        height = "100%-150",
        halign = "center",
        vscroll = true,
        rpad = 12,
        borderBox = true,
        styles = PICKER_STYLES,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = sections,
        },
    }
    local titleParts = Title(T("guild.picker.title"), T("guild.picker.subtitle"))
    dlg = ModalFrame{
        width = 1000,
        height = 720,
        children = {
            titleParts[1],
            titleParts[2],
            body,
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "bottom",
                bmargin = 14,
                Button(T("guild.picker.cancel_button"), function() dlg:DestroySelf() end, 160),
            },
        },
    }
    host:AddChild(dlg)
end

local GUILD_STYLES = {
    {
        selectors = { "eotwGuildRow" },
        bgcolor = "#221b13",
        borderWidth = 1,
        borderColor = "#5a4b33",
    },
    {
        selectors = { "eotwGuildRow", "hover" },
        bgcolor = "#2c2318",
    },
    --an active hero's row: a gold stripe down its left edge and a gold
    --frame on the portrait. Resting heroes keep both quiet.
    {
        selectors = { "eotwGuildStripe" },
        bgcolor = "#00000000",
    },
    {
        selectors = { "eotwGuildStripe", "parent:active" },
        bgcolor = "#d9b56a",
    },
    {
        selectors = { "eotwGuildPortrait" },
        borderWidth = 2,
        borderColor = "#8c7a55",
    },
    {
        selectors = { "eotwGuildPortrait", "parent:active" },
        borderColor = "#d9b56a",
    },
    --one stat in the row's strip: the value over its caption.
    {
        selectors = { "eotwGuildStatValue" },
        fontSize = 18,
        bold = true,
        color = TEXT,
        width = "auto",
        height = "auto",
        halign = "center",
    },
    {
        selectors = { "eotwGuildStatKey" },
        fontSize = 12,
        color = DIM,
        width = "auto",
        height = "auto",
        halign = "center",
    },
    {
        selectors = { "eotwGuildIcon" },
        width = 30,
        height = 30,
        valign = "center",
        hmargin = 6,
        bgcolor = "#c9bfa9",
    },
    {
        selectors = { "eotwGuildIcon", "hover" },
        bgcolor = "#ffffff",
        scale = 1.12,
    },
    {
        selectors = { "eotwGuildIcon", "on" },
        bgcolor = "#ffd66b",
    },
    --the row's actions, stacked in a column at its right edge.
    {
        selectors = { "eotwGuildIcon", "stacked" },
        width = 24,
        height = 24,
        hmargin = 0,
        vmargin = 3,
        halign = "center",
    },
}

--The stat strip in a roster row: stamina, recoveries and the
--characteristics (in the game system's own order), read off the hero's
--character. refresh(tok) repaints it; a nil tok shows dashes.
local function GuildStatStrip()
    local cells = {}
    local function Cell(key, read)
        local value = gui.Label{
            classes = { "eotwGuildStatValue" },
            text = "-",
        }
        cells[#cells+1] = { label = value, read = read }
        return gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            valign = "center",
            hmargin = 7,
            value,
            gui.Label{
                classes = { "eotwGuildStatKey" },
                text = key,
            },
        }
    end

    local children = {
        Cell(T("guild.stats.stamina"), function(c)
            local cur, max = c:CurrentHitpoints(), c:MaxHitpoints()
            if cur >= max then
                return tostring(max)
            end
            return string.format("%d/%d", cur, max)
        end),
        Cell(T("guild.stats.recoveries"), function(c)
            local id = CharacterResource.recoveryResourceId
            local max = c:GetResources()[id] or 0
            local used = c:GetResourceUsage(id, "long") or 0
            return tostring(math.max(0, max - used))
        end),
    }

    local attrList = {}
    for _, info in pairs(creature.attributesInfo) do
        attrList[#attrList+1] = info
    end
    table.sort(attrList, function(a, b) return a.order < b.order end)
    for _, info in ipairs(attrList) do
        local attrid = info.id
        children[#children+1] = Cell(string.sub(info.description, 1, 1), function(c)
            return string.format("%+d", c:GetAttribute(attrid):Modifier())
        end)
    end

    local strip = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        valign = "center",
        children = children,
    }

    local refresh = function(tok)
        for _, cell in ipairs(cells) do
            local text = "-"
            if tok ~= nil and tok.properties ~= nil then
                pcall(function() text = cell.read(tok.properties) end)
            end
            cell.label.text = text
        end
    end
    return strip, refresh
end

--One roster row: portrait, name, details, status, and the hero's actions.
--The row persists across roster refreshes: GuildPanel fires "refreshRow"
--with the hero's latest record instead of building a new row, so a video
--portrait keeps playing rather than restarting on every change.
local function GuildRow(hero, away, host)
    local heroid = hero.heroid
    local confirmingDismiss = false

    --the Hero's art and name open the EotW hero sheet (the row's icons keep
    --their own actions, so the click sits here rather than on the row)
    local function OpenSheet()
        audio.FireSoundEvent("Mouse.Click")
        EotwHeroSheet.Show{ charid = heroid, context = "town" }
    end
    local portraitPanel = Portrait(nil, 72, 96, nil, OpenSheet)
    portraitPanel:AddClass("eotwGuildPortrait")
    local shownPortrait = nil
    local statStrip, refreshStats = GuildStatStrip()

    local nameLabel = gui.Label{
        text = "",
        fontSize = 24,
        bold = true,
        click = OpenSheet,
        color = TEXT,
        width = "100%",
        height = "auto",
        textWrap = false,
        minFontSize = 12,
    }
    local detailsLabel = gui.Label{
        text = "",
        fontSize = 16,
        color = DIM,
        width = "100%",
        height = "auto",
    }
    local statusLabel = gui.Label{
        text = "",
        fontSize = 15,
        italics = true,
        color = "#ffd66b",
        width = "100%",
        height = "auto",
        tmargin = 4,
    }
    local activeIcon = gui.Panel{
        classes = { "eotwGuildIcon", "stacked" },
        bgimage = "phosphor/star.png",
        linger = function(element)
            gui.Tooltip(cond(hero.active == true, T("guild.row.active_tooltip"), T("guild.row.make_active_tooltip", { max = EotwRoster.MAX_ACTIVE })))(element)
        end,
        press = function()
            audio.FireSoundEvent("Mouse.Click")
            EotwRoster.SetActive(heroid, hero.active ~= true)
        end,
    }

    return gui.Panel{
        classes = { "eotwGuildRow" },
        width = "100%",
        height = 112,
        flow = "horizontal",
        bgimage = "panels/square.png",
        cornerRadius = 8,
        --the stripe sits close to the left edge; the portrait carries
        --the rest of the inset.
        lpad = 5,
        rpad = 12,
        vpad = 8,
        borderBox = true,
        vmargin = 3,

        create = function(element)
            element:FireEvent("refreshRow", hero, away)
        end,

        refreshRow = function(element, newHero, newAway)
            hero = newHero
            away = newAway

            local summary = hero.summary or {}
            local tok = dmhub.GetCharacterById(heroid)
            local portrait = summary.portrait
            local name = summary.name or T("guild.row.hero_fallback")
            local details = EotwRoster.FormatDetails(summary.level, summary.ancestry, summary.className)
            if tok ~= nil then
                pcall(function()
                    local p = tok.offTokenPortrait
                    if type(p) == "string" then
                        portrait = p
                    end
                end)
                local className, ancestry, level = EotwRoster.HeroDetails(tok)
                details = EotwRoster.FormatDetails(level, ancestry, className)
                if tok.name ~= nil and tok.name ~= "" then
                    name = tok.name
                end
            end

            local status = {}
            if hero.active == true then
                status[#status+1] = T("guild.row.active")
            end
            if away ~= nil then
                status[#status+1] = T("guild.row.away", { party = away })
            end
            if tok == nil then
                status[#status+1] = T("guild.row.loading")
            end

            element:SetClass("active", hero.active == true)
            nameLabel.text = name
            detailsLabel.text = details
            statusLabel.text = table.concat(status, "  -  ")
            activeIcon:SetClass("on", hero.active == true)
            refreshStats(tok)
            activeIcon.bgimage = cond(hero.active == true, "phosphor/star-fill.png", "phosphor/star.png")

            --only touch the portrait when it actually changes: re-setting a
            --video bgimage restarts it.
            if type(portrait) ~= "string" or portrait == "" then
                portrait = nil
            end
            if portrait ~= shownPortrait then
                shownPortrait = portrait
                portraitPanel.bgimage = portrait or "panels/square.png"
                portraitPanel.selfStyle.bgcolor = cond(portrait ~= nil, "white", "#ffffff10")
                --the panel was built as a silhouette; its user icon child would
                --otherwise sit on top of the real portrait.
                for _, child in ipairs(portraitPanel.children) do
                    child:SetClass("hidden", portrait ~= nil)
                end
            end
            --crop the art to the frame's 3:4 rather than squashing it in.
            --Needs the character, so it lands once the hero has loaded.
            if portrait ~= nil and tok ~= nil then
                local rect = nil
                pcall(function() rect = tok:GetPortraitRectForAspect(72 / 96, portrait) end)
                portraitPanel.selfStyle.imageRect = rect
            end
        end,

        gui.Panel{
            classes = { "eotwGuildStripe" },
            interactable = false,
            width = 4,
            height = "100%",
            rmargin = 4,
            cornerRadius = 2,
            bgimage = "panels/square.png",
        },

        portraitPanel,

        gui.Panel{
            width = 220,
            height = "auto",
            flow = "vertical",
            valign = "center",
            lmargin = 14,
            nameLabel,
            detailsLabel,
            statusLabel,
        },

        --a hairline between the hero's name and their numbers.
        gui.Panel{
            interactable = false,
            width = 1,
            height = "70%",
            valign = "center",
            hmargin = 8,
            bgimage = "panels/square.png",
            bgcolor = "#5a4b33",
        },
        statStrip,

        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            flow = "vertical",

            activeIcon,
            gui.Panel{
                classes = { "eotwGuildIcon", "stacked" },
                bgimage = "phosphor/pencil-simple.png",
                linger = function(element)
                    if EotwRoster.CanRebuildHero(heroid) then
                        gui.Tooltip(T("guild.row.rebuild_tooltip"))(element)
                    else
                        gui.Tooltip(T("guild.row.sheet_tooltip"))(element)
                    end
                end,
                press = function()
                    audio.FireSoundEvent("Mouse.Click")
                    EotwRoster.EditHero(heroid, host)
                end,
            },
            gui.Panel{
                classes = { "eotwGuildIcon", "stacked" },
                bgimage = "phosphor/trash.png",
                linger = function(element)
                    if away ~= nil then
                        gui.Tooltip(T("guild.row.dismiss_away_tooltip"))(element)
                    else
                        gui.Tooltip(T("guild.row.dismiss_tooltip"))(element)
                    end
                end,
                resetConfirm = function(element)
                    confirmingDismiss = false
                    element:SetClass("on", false)
                end,
                press = function(element)
                    audio.FireSoundEvent("Mouse.Click")
                    if away ~= nil then
                        return
                    end
                    if not confirmingDismiss then
                        confirmingDismiss = true
                        element:SetClass("on", true)
                        element:ScheduleEvent("resetConfirm", 4)
                        return
                    end
                    EotwRoster.DismissHero(heroid)
                end,
            },
        },
    }
end

--The Hero's Guild: the player's whole roster, with Create and Recruit. This
--is the body of the guild's full-screen location (the town screen draws the
--art, the title and the way back around it), so it fills its parent. host is
--the panel to mount the guild's own dialogs on (the town screen).
function EotwRoster.GuildPanel(host)
    local listPanel = nil
    local headerLabel = nil
    local slotPips = nil
    local statusLabel = nil
    local createButton = nil
    local recruitButton = nil
    local projectButton = nil
    local discardButton = nil
    local confirmingDiscard = false
    local rowsById = {} --heroid -> that hero's GuildRow panel

    local Rebuild = function()
        if listPanel == nil or not listPanel.valid then
            return
        end
        local heroes = EotwRoster.GetHeroes()
        local away = EotwRoster.AwayHeroes()
        local rows = {}
        if heroes == nil then
            rows[1] = gui.Label{ text = T("guild.loading"), fontSize = 18, color = DIM, width = "auto", height = "auto", halign = "center", vmargin = 30 }
        elseif #heroes == 0 then
            rows[1] = gui.Label{ text = T("guild.empty"), fontSize = 18, color = DIM, width = "80%", height = "auto", halign = "center", textAlignment = "center", vmargin = 30 }
        else
            --reuse each hero's existing row so its portrait is not recreated.
            local nextRowsById = {}
            for _,hero in ipairs(heroes) do
                local row = rowsById[hero.heroid]
                if row ~= nil and row.valid then
                    row:FireEvent("refreshRow", hero, away[hero.heroid])
                else
                    row = GuildRow(hero, away[hero.heroid], host)
                end
                nextRowsById[hero.heroid] = row
                rows[#rows+1] = row
            end
            rowsById = nextRowsById
        end
        listPanel.children = rows

        local count = EotwRoster.LivingCount()
        --one pip per slot the roster has: filled for a hero, hollow for a
        --free slot. How many more the Guild could ever build is not shown
        --(user direction): players just try to expand it.
        if slotPips ~= nil and slotPips.valid then
            local pips = {}
            local slots = math.max(EotwRoster.Slots(), count)
            for i = 1, slots do
                local icon = cond(i <= count, "phosphor/circle-fill.png", "phosphor/circle.png")
                local color = "#d9b56a"
                pips[#pips+1] = gui.Panel{
                    width = 14,
                    height = 14,
                    hmargin = 2,
                    valign = "center",
                    bgimage = icon,
                    bgcolor = color,
                }
            end
            slotPips.children = pips
        end
        if headerLabel ~= nil and headerLabel.valid then
            headerLabel.text = T("guild.header.slots", { heroes = count, slots = EotwRoster.Slots(), active = "<color=#d9b56a>" .. T("guild.header.active", { active = #EotwRoster.ActiveHeroes(), max = EotwRoster.MAX_ACTIVE }) .. "</color>" })
        end
        if statusLabel ~= nil and statusLabel.valid then
            statusLabel.text = EotwRoster.lastError or ""
        end
        local canAdd = heroes ~= nil and EotwRoster.CanAddHero()
        for _,b in ipairs({ createButton, recruitButton }) do
            if b ~= nil and b.valid then
                b.selfStyle.opacity = cond(canAdd, 1, 0.45)
            end
        end
        --a full roster can start the project that builds another slot (no
        --project runs by default; an ongoing one shows on the scene's left).
        if projectButton ~= nil and projectButton.valid then
            local downtime = rawget(_G, "EotwDowntime")
            --offered whenever the roster is full and no project is under way,
            --even once the guild cannot grow (its dialog then says so), so
            --nothing hints at how many expansions there are.
            local offer = heroes ~= nil and not canAdd
                and downtime ~= nil and downtime.CanOffer("expand-guild")
            projectButton:SetClass("collapsed", not offer)
        end
        local hasDraft = EotwRoster.FindDraft() ~= nil
        if createButton ~= nil and createButton.valid then
            createButton.text = cond(hasDraft, T("guild.continue_button"), T("guild.create_button"))
        end
        if discardButton ~= nil and discardButton.valid then
            discardButton:SetClass("collapsed", not hasDraft)
        end
    end

    --the roster fills the body; the count line heads it, and the guild's
    --actions sit along the bottom. The way back to town is the location's.
    local body = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bmargin = 10,
            gui.Label{
                text = T("guild.roster_heading"),
                fontSize = 26,
                bold = true,
                color = TEXT,
                width = "auto",
                height = "auto",
                valign = "center",
            },
            gui.Label{
                text = "",
                fontSize = 18,
                color = DIM,
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
                create = function(element)
                    headerLabel = element
                end,
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "center",
                lmargin = 10,
                linger = function(element)
                    gui.Tooltip(T("guild.slots_tooltip", { slots = EotwRoster.Slots() }))(element)
                end,
                create = function(element)
                    slotPips = element
                end,
            },
        },
        gui.Label{
            text = T("guild.intro", { max = EotwRoster.MAX_ACTIVE }),
            fontSize = 16,
            italics = true,
            color = DIM,
            width = "100%",
            height = "auto",
            bmargin = 12,
        },
        gui.Panel{
            width = "100%",
            height = "100%-190",
            flow = "vertical",
            vscroll = true,
            rpad = 12,
            borderBox = true,
            styles = GUILD_STYLES,
            create = function(element)
                listPanel = element
                Rebuild()
            end,
        },
        gui.Label{
            text = "",
            fontSize = 16,
            color = "#ff8888",
            width = "100%",
            height = 22,
            textAlignment = "center",
            create = function(element)
                statusLabel = element
            end,
        },
        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "bottom",
            flow = "horizontal",
            gui.Button{
                text = T("guild.create_button"),
                fontSize = 18,
                width = "auto",
                minWidth = 140,
                hpad = 16,
                height = 42,
                hmargin = 4,
                create = function(element)
                    createButton = element
                end,
                click = function()
                    if not EotwRoster.CanAddHero() then
                        Fail(EotwRoster.FullRosterMessage())
                        return
                    end
                    EotwRoster.lastError = nil
                    EotwRoster.CreateHero(host)
                end,
            },
            gui.Button{
                text = T("guild.discard_button"),
                fontSize = 18,
                width = "auto",
                minWidth = 140,
                hpad = 16,
                height = 42,
                hmargin = 4,
                classes = { "collapsed" },
                create = function(element)
                    discardButton = element
                end,
                linger = function(element)
                    gui.Tooltip(T("guild.discard_tooltip"))(element)
                end,
                resetConfirm = function(element)
                    confirmingDiscard = false
                    element.text = T("guild.discard_button")
                end,
                click = function(element)
                    if not confirmingDiscard then
                        confirmingDiscard = true
                        element.text = T("guild.discard_confirm")
                        element:ScheduleEvent("resetConfirm", 4)
                        return
                    end
                    confirmingDiscard = false
                    element.text = T("guild.discard_button")
                    EotwRoster.DiscardDraft()
                end,
            },
            gui.Button{
                text = T("guild.recruit_button"),
                fontSize = 18,
                width = "auto",
                minWidth = 140,
                hpad = 16,
                height = 42,
                hmargin = 4,
                create = function(element)
                    recruitButton = element
                end,
                click = function()
                    if not EotwRoster.CanAddHero() then
                        Fail(EotwRoster.FullRosterMessage())
                        return
                    end
                    EotwRoster.lastError = nil
                    ShowRecruitPicker(host)
                end,
            },
            gui.Button{
                classes = { "collapsed" },
                text = T("guild.project_button"),
                fontSize = 18,
                width = "auto",
                minWidth = 140,
                hpad = 16,
                height = 42,
                hmargin = 4,
                create = function(element)
                    projectButton = element
                end,
                linger = function(element)
                    gui.Tooltip(T("guild.project_tooltip"))(element)
                end,
                click = function()
                    EotwRoster.lastError = nil
                    Bump()
                    EotwDowntime.ShowStartProjectDialog(host, "expand-guild")
                end,
            },
            --admins: search everyone's heroes to remove one or warn/ban
            --its owner (the Guild otherwise lists only your own).
            gui.Button{
                classes = { cond(dmhub.isAdminAccount, nil, "collapsed") },
                text = "Find Heroes",
                fontSize = 18,
                width = "auto",
                minWidth = 140,
                hpad = 16,
                height = 42,
                hmargin = 4,
                click = function()
                    EotwModeration.ShowFindHeroesDialog()
                end,
            },
        },

        --rebuild whenever the roster (or a working copy) changes.
        gui.Panel{
            floating = true,
            width = 1,
            height = 1,
            interactable = false,
            data = { seen = -1 },
            thinkTime = 0.25,
            think = function(element)
                local downtime = rawget(_G, "EotwDowntime")
                local rev = EotwRoster.revision + (downtime ~= nil and downtime.revision or 0) * 100000
                if element.data.seen ~= rev then
                    element.data.seen = rev
                    Rebuild()
                end
            end,
        },
    }
    EotwRoster.Refresh()
    EotwDowntime.RefreshProjects()
    return body
end

--- the Graveyard ----------------------------------------------------------

--The Encounter of the Week number a grave belongs to, for the hero sheet's
--epitaph ("Fell in X, week n"): the encounter's place in the City's schedule
--(this week, or how many weeks back), else worked out from when they fell.
--nil when there is no schedule to go by.
local function GraveWeek(encounter, at)
    local eotw = rawget(_G, "EncounterOfTheWeek")
    if eotw == nil or eotw.GetWeek == nil then
        return nil
    end
    local week = eotw.GetWeek()
    if week == nil or type(week.week) ~= "number" then
        return nil
    end
    if encounter ~= nil and encounter == week.current then
        return week.week
    end
    for i,past in ipairs(type(week.past) == "table" and week.past or {}) do
        if past == encounter then
            return math.max(1, week.week - i)
        end
    end
    if type(at) == "number" and type(week.since) == "number" then
        --server times are in milliseconds (or seconds on older records)
        local perDay = cond(at > 1e12, 86400000, 86400)
        if at >= week.since then
            return week.week
        end
        return math.max(1, week.week - math.ceil((week.since - at) / perDay / 7))
    end
    return nil
end

--Open a fallen Hero from the Graveyard in the EotW hero sheet as a memorial
--(grey art, epitaph, no controls). The Hero is fetched from the City; one the
--owner later dismissed can no longer load, and the sheet says so.
local function OpenFallen(g)
    local e = g.epitaph or {}
    local where = e.encounter
    local eotw = rawget(_G, "EncounterOfTheWeek")
    if where ~= nil and eotw ~= nil and eotw.EncounterDisplayName ~= nil then
        where = eotw.EncounterDisplayName(e.encounter)
    end
    local fallen = {
        encounter = where,
        week = GraveWeek(e.encounter, g.at),
        playedBy = e.owner,
    }
    audio.FireSoundEvent("Mouse.Click")
    --the sheet opens at once on its loading state, and fills in when the
    --Hero arrives
    EotwHeroSheet.Show{ charid = g.heroid, name = e.name, context = "town", fallen = fallen }
    if m_conn == nil or g.userid == nil or g.heroid == nil then
        return
    end
    m_conn:Request{
        action = "get-hero",
        args = { userid = g.userid, heroid = g.heroid, asJson = true },
        success = function(result)
            if mod.unloaded then
                return
            end
            local tok = dmhub.CreateDetachedCharacter{
                record = result.record,
                assets = result.assets,
            }
            if tok ~= nil and EotwHeroSheet.IsShowing(g.heroid) then
                EotwHeroSheet.Show{ token = tok, charid = g.heroid, name = e.name, context = "town", fallen = fallen, switching = true }
            end
        end,
        error = function(message)
            printf("EotW Graveyard: could not load %s: %s", tostring(e.name), tostring(message))
        end,
    }
end

--Everyone's fallen heroes, newest first, with this account's marked.
function EotwRoster.ShowGraveyard(host)
    local dlg
    local listPanel = nil
    local graves = {}
    local more = false
    local loading = false

    local Rebuild
    local LoadMore = function()
        if loading then
            return
        end
        loading = true
        local before = #graves > 0 and graves[#graves].id or nil
        EotwRoster.ListGraveyard(before, function(result)
            loading = false
            for _,g in ipairs(result.graves or {}) do
                graves[#graves+1] = g
            end
            more = result.more == true
            Rebuild()
        end)
    end

    Rebuild = function()
        if listPanel == nil or not listPanel.valid then
            return
        end
        local rows = {}
        if #graves == 0 then
            rows[1] = gui.Label{ text = cond(loading, T("graveyard.loading"), T("graveyard.empty")), fontSize = 18, color = DIM, width = "auto", height = "auto", halign = "center", vmargin = 30 }
        end
        for _,g in ipairs(graves) do
            local e = g.epitaph or {}
            local mine = g.userid == dmhub.loginUserid
            local lines = {
                EotwRoster.FormatDetails(e.level, e.ancestry, e.className),
            }
            local where = nil
            if type(e.encounter) == "string" and e.encounter ~= "" then
                --an encounter key; a community one reads "<title> (<module>)".
                local eotw = rawget(_G, "EncounterOfTheWeek")
                where = e.encounter
                if eotw ~= nil and eotw.EncounterDisplayName ~= nil then
                    where = eotw.EncounterDisplayName(e.encounter)
                end
            end
            local when = nil
            if type(g.at) == "number" then
                when = DescribeServerTimestamp(g.at)
            end
            local fell
            if where ~= nil and when ~= nil then
                fell = T("graveyard.fell_in_on", { where = where, when = when })
            elseif where ~= nil then
                fell = T("graveyard.fell_in", { where = where })
            elseif when ~= nil then
                fell = T("graveyard.fell_on", { when = when })
            else
                fell = T("graveyard.fell")
            end
            lines[#lines+1] = fell
            lines[#lines+1] = T("graveyard.played_by", { player = e.owner or "?" })
            rows[#rows+1] = gui.Panel{
                width = "100%",
                height = 100,
                flow = "horizontal",
                bgimage = "panels/square.png",
                bgcolor = cond(mine, "#2a2418cc", "#ffffff0a"),
                --a grave opens its Hero's memorial sheet
                click = function()
                    OpenFallen(g)
                end,
                --admins: remove the hero, or warn/ban the player who owned it.
                rightClick = function(element)
                    EotwModeration.PopupHeroMenu(element, {
                        userid = g.userid,
                        heroid = g.heroid,
                        heroName = e.name,
                        ownerName = e.owner,
                        onScrubbed = function()
                            for i, other in ipairs(graves) do
                                if other == g then
                                    table.remove(graves, i)
                                    break
                                end
                            end
                            Rebuild()
                        end,
                    })
                end,
                cornerRadius = 8,
                pad = 8,
                borderBox = true,
                vmargin = 3,
                Portrait(e.portrait, 63, 84),
                gui.Panel{
                    width = "100%-90",
                    height = "100%",
                    flow = "vertical",
                    valign = "center",
                    lmargin = 14,
                    gui.Label{ text = e.name or T("graveyard.hero_fallback"), fontSize = 22, bold = true, color = TEXT, width = "100%", height = "auto" },
                    gui.Label{ text = table.concat(lines, "\n"), fontSize = 14, color = DIM, width = "100%", height = "auto" },
                },
            }
        end
        if more then
            rows[#rows+1] = Button(T("graveyard.older_button"), LoadMore, 220)
        end
        listPanel.children = rows
    end

    local titleParts = Title(T("graveyard.title"), T("graveyard.subtitle"))
    dlg = ModalFrame{
        width = 900,
        height = 820,
        children = {
            titleParts[1],
            titleParts[2],
            gui.Panel{
                width = "94%",
                height = "100%-190",
                halign = "center",
                flow = "vertical",
                vscroll = true,
                rpad = 12,
                borderBox = true,
                vmargin = 8,
                create = function(element)
                    listPanel = element
                    Rebuild()
                end,
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "bottom",
                bmargin = 14,
                Button(T("graveyard.leave_button"), function() dlg:DestroySelf() end, 180),
            },
        },
    }
    host:AddChild(dlg)
    LoadMore()
    return dlg
end

--- the Hall of Heroes -----------------------------------------------------
--Every party that won an Encounter of the Week, from the city's Hall of
--Heroes (written by each game's host at the victory). A tab per encounter,
--sorted newest first or best first; an entry opens the victory screen the
--party saw (DSVictoryScreen.ShowReplay).

--The Hall's sort orders: the city's sort id and the button text.
local HALL_SORTS = {
    { id = "recent", text = T("roster.hall.sort_recent") },
    { id = "fastest", text = T("roster.hall.sort_fastest") },
    { id = "rounds", text = T("roster.hall.sort_rounds") },
    { id = "deaths", text = T("roster.hall.sort_deaths") },
}

--"1h 05m" / "42 min" / "under a minute" for a play time in seconds.
local function FormatPlayTime(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds <= 0 then
        return T("roster.hall.time_unknown")
    end
    if seconds < 60 then
        return T("roster.hall.time_under_minute")
    end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then
        return T("roster.hall.time_minutes", { minutes = minutes })
    end
    return T("roster.hall.time_hours", { hours = math.floor(minutes / 60), minutes = string.format("%02d", minutes % 60) })
end

--An encounter key as a player reads it (a community encounter names its module).
local function HallEncounterName(key, fallback)
    local eotw = rawget(_G, "EncounterOfTheWeek")
    if type(key) == "string" and key ~= "" and eotw ~= nil and eotw.EncounterDisplayName ~= nil then
        local ok, name = pcall(eotw.EncounterDisplayName, key)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end
    return fallback or key or T("roster.hall.encounter_fallback")
end

--A small toggle for the Hall's tab and sort strips.
local function HallChip(text, selected, click)
    return gui.Label{
        text = text,
        fontSize = 16,
        bold = selected,
        color = cond(selected, TEXT, DIM),
        width = "auto",
        height = "auto",
        hpad = 12,
        vpad = 5,
        borderBox = true,
        hmargin = 3,
        vmargin = 3,
        bgimage = "panels/square.png",
        bgcolor = cond(selected, "#8c7a5599", "#ffffff10"),
        cornerRadius = 6,
        styles = {
            { selectors = {"hover"}, bgcolor = cond(selected, "#8c7a55cc", "#ffffff22") },
        },
        click = function()
            audio.FireSoundEvent("Mouse.Click")
            click()
        end,
    }
end

--Open an entry's saved victory screen over `host`.
local function OpenHallEntry(host, entry)
    audio.FireSoundEvent("Mouse.Click")
    EotwRoster.GetHallEntry(entry.gameid, function(result)
        if mod.unloaded or host == nil or not host.valid then
            return
        end
        if type(result.snapshot) ~= "table" or next(result.snapshot) == nil then
            Fail(T("roster.hall.no_snapshot"))
            return
        end
        local summary = type(result.summary) == "table" and result.summary or {}
        local caption = HallEncounterName(result.encounter, summary.title)
        if type(result.at) == "number" then
            caption = T("roster.hall.replay_caption", { encounter = caption, when = DescribeServerTimestamp(result.at) })
        end
        DSVictoryScreen.ShowReplay(host, result.snapshot, { caption = caption })
    end)
end

--The Hall of Heroes location's card: tabs, sort and the list of entries (the
--scene above it carries the title). host mounts the victory-screen replays.
function EotwRoster.HallPanel(host)
    local listPanel = nil
    local tabsPanel = nil
    local sortPanel = nil
    local entries = {}
    local encounters = {}
    local more = false
    local loading = false
    --the current tab ("" = every encounter) and sort; a request answered
    --after either changed is dropped (see `generation`).
    local encounter = ""
    local sort = "recent"
    local generation = 0

    local Rebuild
    local LoadMore = function()
        if loading then
            return
        end
        loading = true
        local g = generation
        EotwRoster.ListHall({ encounter = encounter, sort = sort, offset = #entries }, function(result)
            if g ~= generation then
                return
            end
            loading = false
            for _,e in ipairs(result.entries or {}) do
                entries[#entries+1] = e
            end
            more = result.more == true
            encounters = result.encounters or {}
            Rebuild()
        end)
    end

    --Start the list over for a new tab or sort.
    local function Reload()
        generation = generation + 1
        entries = {}
        more = false
        loading = false
        Rebuild()
        LoadMore()
    end

    local function EntryRow(rank, e)
        local summary = type(e.summary) == "table" and e.summary or {}
        local heroes = summary.heroes or {}
        local mine = false
        local names, fallen = {}, {}
        local portraits = {}
        for _,h in ipairs(heroes) do
            names[#names+1] = h.name or T("roster.hall.hero_fallback")
            if h.died then
                fallen[#fallen+1] = h.name or T("roster.hall.hero_fallback")
            end
            if h.userid == dmhub.loginUserid then
                mine = true
            end
            if #portraits < 6 then
                portraits[#portraits+1] = Portrait(h.portrait, 45, 60, "left")
            end
        end
        local playerNames = {}
        for _,p in ipairs(summary.players or {}) do
            playerNames[#playerNames+1] = p.name or "?"
            if p.userid == dmhub.loginUserid then
                mine = true
            end
        end

        local when = HallEncounterName(e.encounter, summary.title)
        if type(e.at) == "number" then
            when = T("roster.hall.encounter_when", { encounter = when, when = DescribeServerTimestamp(e.at) })
        end
        local deaths = tonumber(e.deaths) or 0
        local deathText = T("roster.hall.no_deaths")
        if deaths > 0 then
            if #fallen > 0 then
                deathText = TP("roster.hall.deaths_named", deaths, { names = table.concat(fallen, ", ") })
            else
                deathText = TP("roster.hall.deaths", deaths)
            end
        end
        local rounds = tonumber(e.rounds) or 0
        local stats = TP("roster.hall.stats", rounds, { time = FormatPlayTime(e.seconds), deaths = deathText })

        local children = {}
        if rank ~= nil then
            children[#children+1] = gui.Label{ text = string.format("#%d", rank), fontSize = 22, bold = true, color = TEXT, width = 52, height = "auto", valign = "center", textAlignment = "center" }
        end
        children[#children+1] = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            valign = "center",
            children = portraits,
        }
        children[#children+1] = gui.Panel{
            width = "100%-" .. tostring(#portraits * 45 + 30 + cond(rank ~= nil, 52, 0)),
            height = "auto",
            flow = "vertical",
            valign = "center",
            lmargin = 14,
            gui.Label{ text = table.concat(names, ", "), fontSize = 20, bold = true, color = TEXT, width = "100%", height = "auto" },
            gui.Label{ text = T("roster.hall.played_by", { players = table.concat(playerNames, ", ") }), fontSize = 14, color = DIM, width = "100%", height = "auto" },
            gui.Label{ text = when, fontSize = 14, color = DIM, width = "100%", height = "auto" },
            gui.Label{ text = stats, fontSize = 14, color = TEXT, width = "100%", height = "auto" },
        }

        return gui.Panel{
            width = "100%",
            height = "auto",
            minHeight = 84,
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = cond(mine, "#2a2418cc", "#ffffff0a"),
            styles = {
                { selectors = {"hover"}, bgcolor = cond(mine, "#3a3220dd", "#ffffff18") },
            },
            --an entry opens the victory screen the party saw
            click = function()
                OpenHallEntry(host, e)
            end,
            hover = gui.Tooltip(T("roster.hall.entry_tooltip")),
            cornerRadius = 8,
            pad = 8,
            borderBox = true,
            vmargin = 3,
            children = children,
        }
    end

    Rebuild = function()
        if tabsPanel ~= nil and tabsPanel.valid then
            local chips = { HallChip(T("roster.hall.all_tab"), encounter == "", function()
                if encounter ~= "" then
                    encounter = ""
                    Reload()
                end
            end) }
            for _,enc in ipairs(encounters) do
                local key = enc.encounter
                chips[#chips+1] = HallChip(string.format("%s (%d)", HallEncounterName(key), tonumber(enc.count) or 0), encounter == key, function()
                    if encounter ~= key then
                        encounter = key
                        Reload()
                    end
                end)
            end
            tabsPanel.children = chips
        end
        if sortPanel ~= nil and sortPanel.valid then
            local chips = { gui.Label{ text = T("roster.hall.sort_label"), fontSize = 16, color = DIM, width = "auto", height = "auto", valign = "center", rmargin = 6 } }
            for _,s in ipairs(HALL_SORTS) do
                chips[#chips+1] = HallChip(s.text, sort == s.id, function()
                    if sort ~= s.id then
                        sort = s.id
                        Reload()
                    end
                end)
            end
            sortPanel.children = chips
        end
        if listPanel == nil or not listPanel.valid then
            return
        end
        local rows = {}
        if #entries == 0 then
            rows[1] = gui.Label{ text = cond(loading, T("roster.hall.loading"), T("roster.hall.empty")), fontSize = 18, color = DIM, width = "auto", height = "auto", halign = "center", vmargin = 30 }
        end
        for i,e in ipairs(entries) do
            --a ranked order numbers its rows; newest-first does not
            rows[#rows+1] = EntryRow(cond(sort ~= "recent", i, nil), e)
        end
        if more then
            rows[#rows+1] = Button(T("roster.hall.more_button"), LoadMore, 220)
        end
        listPanel.children = rows
    end

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        create = function(element)
            LoadMore()
        end,
        children = {
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                create = function(element)
                    tabsPanel = element
                    Rebuild()
                end,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 4,
                create = function(element)
                    sortPanel = element
                    Rebuild()
                end,
            },
            --the tab and sort strips above take about 100 (more if the
            --tabs wrap onto a second row), the tribute button below 45.
            gui.Panel{
                width = "100%",
                height = "100%-155",
                flow = "vertical",
                vscroll = true,
                rpad = 12,
                borderBox = true,
                tmargin = 8,
                create = function(element)
                    listPanel = element
                    Rebuild()
                end,
            },
            --who built the Hall (the community project it was).
            EotwDowntime.TributeButton(host, "build-hall-of-heroes"),
        },
    }
end
