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

--The town's city id, on the staging server while EotW is dev-gated. The
--game-side EotW mod (EncounterOfTheWeek/EncounterOfTheWeek.lua) must
--connect to the same city to signal ready / leave.
EotwRoster.CITY_ID = "blackbottom"
EotwRoster.CITY_OPTIONS = { staging = true, route = "city" }

--Server-enforced limits (city-core.ts); these only drive the UI.
EotwRoster.MAX_LIVING = 12
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

local m_conn = nil
--this account's living heroes as the city last listed them (hero views:
--{heroid, rev, status, active, summary, ...}); nil until the first list.
local m_heroes = nil
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
        parts[#parts+1] = string.format("Level %d", level)
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
        name = "Unnamed Hero"
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
    return summary
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
                result[h.id] = record.name or "a party"
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
                Fail(string.format("could not load %s from the city", tostring(hero.summary and hero.summary.name or heroid)))
                return
            end
            SetRev(heroid, result.rev)
            AdoptLobbyParty(heroid)
            Bump()
            --a won encounter may have been waiting on this copy; the import
            --resolves a moment after it is written.
            dmhub.Schedule(1, function()
                if not mod.unloaded then
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

--Carry one won encounter home: put its Victories on the working copy, push
--the copy to the city, then record the outcome there (which logs the
--adventure and marks the encounter completed for this hero). The copy is
--stamped properties.eotwOutcomes[gameid], and that stamp travels with the
--record, so the Victories are never added twice -- not by a retry, nor by
--another machine. The entry's stage says how far it got ("pushed" skips to
--the record).
local function ApplyOutcome(key, entry, tok)
    m_outcomeBusy[key] = true
    local gameid = entry.gameid
    local heroid = entry.heroid

    local function Failed(message)
        m_outcomeBusy[key] = nil
        m_outcomeFailures[key] = (m_outcomeFailures[key] or 0) + 1
        Fail(string.format("could not bring %s home: %s", tostring(tok.name), tostring(message)))
    end

    local function Record()
        if m_conn == nil then
            Failed("not connected")
            return
        end
        m_conn:Request{
            action = "record-outcome",
            args = { heroid = heroid, gameid = gameid, outcome = entry.outcome },
            success = function(result)
                m_outcomeBusy[key] = nil
                SetOutcomeStage(key, nil)
                printf("EotW town: %s's encounter recorded (%s)", tostring(tok.name), tostring(gameid))
                --re-list: the hero's completed encounters changed.
                EotwRoster.Refresh()
            end,
            error = Failed,
        }
    end

    if entry.stage == "pushed" then
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
                        else
                            printf("EotW town: could not give %s to %s: %s", tostring(t.name), tostring(tok.name), tostring(err))
                        end
                    end
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

--Apply every pending outcome whose hero's working copy is in step with the
--city (an import in flight would overwrite the Victories). A hero the city
--no longer lists -- dismissed, or fallen -- has nothing to apply to.
ApplyPendingOutcomes = function()
    if m_heroes == nil or m_conn == nil then
        return
    end
    local revs = GetRevs()
    local _, mine = LoadPendingOutcomes()
    for key, entry in pairs(mine) do
        if type(entry) ~= "table" or type(entry.heroid) ~= "string" or type(entry.gameid) ~= "string" then
            SetOutcomeStage(key, nil)
        elseif not m_outcomeBusy[key] and (m_outcomeFailures[key] or 0) < MAX_OUTCOME_ATTEMPTS then
            if EotwRoster.FindHero(entry.heroid) == nil then
                printf("EotW town: hero %s is no longer in the roster; dropping its outcome", entry.heroid)
                SetOutcomeStage(key, nil)
            else
                local tok = dmhub.GetCharacterById(entry.heroid)
                local hero = EotwRoster.FindHero(entry.heroid)
                if tok ~= nil and hero ~= nil and revs[entry.heroid] == hero.rev and not m_importing[entry.heroid] then
                    ApplyOutcome(key, entry, tok)
                end
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

    --encounters won since the last visit: Victories onto the heroes.
    ApplyPendingOutcomes()
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
            Bump()
            SyncWorkingCopies()
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

--Push a working copy to the city: creates the hero there the first time,
--replaces it afterwards (revision-checked). onDone(ok, message) optional.
function EotwRoster.PushHero(charid, onDone)
    local tok = dmhub.GetCharacterById(charid)
    if tok == nil or m_conn == nil then
        if onDone ~= nil then
            onDone(false, "not connected")
        end
        return
    end
    local data = dmhub.ExportCharacter(tok)
    if data == nil then
        Fail("could not export the hero")
        if onDone ~= nil then
            onDone(false, "export failed")
        end
        return
    end
    local baseRev = GetRevs()[charid] or 0
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
            EotwRoster.Refresh()
            if onDone ~= nil then
                onDone(true)
            end
        end,
        error = function(message)
            Fail(message)
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
        Fail("the new hero never appeared in the lobby")
    end)
end

--Tag a lobby character as a town hero and push it to the city as new.
local function JoinRoster(tok, onDone)
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
        end,
    }
    --the property write applies locally at once; give it a beat so the
    --export carries it, then push.
    dmhub.Schedule(0.3, function()
        if mod.unloaded then
            return
        end
        EotwRoster.PushHero(charid, function(ok, message)
            m_pendingCreates[charid] = nil
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
    return EotwRoster.LivingCount() < EotwRoster.MAX_LIVING
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
            JoinRoster(t, onDone)
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
        Fail(string.format("Your roster is full (%d heroes).", EotwRoster.MAX_LIVING))
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
        Fail("could not start a new hero (no Hero character type)")
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

--Whether a roster hero may still be rebuilt in the EotW builder: only until
--their first encounter (none completed, and not away in a party now).
function EotwRoster.CanRebuildHero(heroid)
    local hero = EotwRoster.FindHero(heroid)
    if hero == nil or EotwRoster.AwayHeroes()[heroid] ~= nil then
        return false
    end
    return #(hero.completed or {}) == 0
end

--Recruit a pregen: copy the module's pregen into the lobby game under the
--player's chosen name, then add it to the roster.
function EotwRoster.RecruitPregen(pregenId, name, onDone)
    if not EotwRoster.CanAddHero() then
        Fail(string.format("Your roster is full (%d heroes).", EotwRoster.MAX_LIVING))
        return
    end
    local source = EncounterOfTheWeek.GetPregenToken(pregenId)
    if source == nil then
        Fail("that pregenerated hero is not available")
        return
    end
    local data = dmhub.ExportCharacter(source)
    if data == nil then
        Fail("could not copy the pregenerated hero")
        return
    end
    local charid = dmhub.ImportCharacter{
        record = data.record,
        assets = data.assets,
        name = name,
    }
    if charid == nil then
        Fail("could not copy the pregenerated hero")
        return
    end
    m_pendingCreates[charid] = true
    WhenCharacterExists(charid, function(tok)
        JoinRoster(tok, onDone)
    end)
end

--Open a roster hero: in the EotW builder while it can still be rebuilt
--(and a host to mount on is given), otherwise in the character sheet.
--Saved back to the city on close either way.
function EotwRoster.EditHero(heroid, host)
    local tok = dmhub.GetCharacterById(heroid)
    if tok == nil then
        Fail("that hero has not loaded yet")
        return
    end
    if host ~= nil and host.valid and EotwRoster.CanRebuildHero(heroid) then
        local Save = function()
            EotwRoster.PushHero(heroid)
        end
        EotwBuilder.Open{
            host = host,
            token = tok,
            title = "Rebuild Your Hero",
            onFinish = Save,
            onClose = Save,
        }
        return
    end
    TitlescreenHeroes.Edit(tok, function()
        EotwRoster.PushHero(heroid)
    end)
end

--Dismiss a hero: gone from the city, then from this machine.
function EotwRoster.DismissHero(heroid, onDone)
    if m_conn == nil then
        return
    end
    m_conn:Request{
        action = "delete-hero",
        args = { heroid = heroid },
        success = function()
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
            Fail(string.format("At most %d heroes can be active.", EotwRoster.MAX_ACTIVE))
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
local function Portrait(portrait, width, height)
    if type(portrait) == "string" and portrait ~= "" then
        return gui.Panel{
            interactable = false,
            width = width,
            height = height,
            valign = "center",
            bgimage = portrait,
            bgcolor = "white",
            cornerRadius = 6,
        }
    end
    return gui.Panel{
        interactable = false,
        width = width,
        height = height,
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

--The name prompt for a recruit: prefilled with the pregen's own name.
local function ShowRecruitNamePrompt(host, pregen, onDone)
    local nameInput = nil
    local dlg
    local Confirm = function()
        local name = ((nameInput ~= nil and nameInput.text) or ""):match("^%s*(.-)%s*$")
        if name == "" then
            return
        end
        EotwRoster.RecruitPregen(pregen.id, name, onDone)
        dlg:DestroySelf()
    end
    dlg = ModalFrame{
        width = 560,
        height = 300,
        children = {
            gui.Label{
                text = "Name your recruit",
                fontSize = 30,
                bold = true,
                color = TEXT,
                width = "auto",
                height = "auto",
                halign = "center",
                tmargin = 18,
            },
            gui.Label{
                text = string.format("A %s joins your roster. What do they call themselves?", EotwRoster.FormatDetails(pregen.level, pregen.ancestry, pregen.className)),
                fontSize = 17,
                color = DIM,
                width = "90%",
                height = "auto",
                halign = "center",
                textAlignment = "center",
                vmargin = 8,
            },
            gui.Input{
                width = 420,
                height = 40,
                halign = "center",
                vmargin = 10,
                fontSize = 22,
                characterLimit = 60,
                placeholderText = "Hero name...",
                create = function(element)
                    nameInput = element
                    element.text = pregen.name or ""
                    element.hasInputFocus = true
                end,
                submit = function(element)
                    Confirm()
                end,
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "bottom",
                bmargin = 18,
                flow = "horizontal",
                Button("Recruit", Confirm, 160),
                Button("Cancel", function() dlg:DestroySelf() end, 160),
            },
        },
    }
    host:AddChild(dlg)
end

--The pregen picker: every pregenerated hero of the week's module.
local function ShowRecruitPicker(host, onDone)
    local pregens = EncounterOfTheWeek.GetPregens()
    local dlg
    local cards = {}
    for _,pregen in ipairs(pregens or {}) do
        local tok = EncounterOfTheWeek.GetPregenToken(pregen.id)
        local portrait = nil
        pcall(function()
            if tok == nil then return end
            local p = tok.offTokenPortrait
            if type(p) == "string" then
                portrait = p
            end
        end)
        cards[#cards+1] = gui.Panel{
            classes = { "eotwGuildPick" },
            width = 170,
            height = 250,
            hmargin = 6,
            vmargin = 6,
            flow = "vertical",
            bgimage = "panels/square.png",
            cornerRadius = 8,
            hoverCursor = "pressbutton",
            press = function()
                audio.FireSoundEvent("Mouse.Click")
                dlg:DestroySelf()
                ShowRecruitNamePrompt(host, pregen, onDone)
            end,
            Portrait(portrait, 150, 190),
            gui.Label{
                interactable = false,
                text = pregen.name,
                fontSize = 16,
                bold = true,
                color = TEXT,
                width = "96%",
                height = "auto",
                halign = "center",
                textAlignment = "center",
                textWrap = false,
                minFontSize = 10,
            },
            gui.Label{
                interactable = false,
                text = EotwRoster.FormatDetails(pregen.level, pregen.ancestry, pregen.className),
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
    local body
    if pregens == nil then
        body = gui.Label{ text = "The pregenerated heroes are still loading. Try again in a moment.", fontSize = 18, color = DIM, width = "90%", height = "auto", halign = "center", textAlignment = "center", vmargin = 40 }
    else
        body = gui.Panel{
            width = "96%",
            height = "100%-150",
            halign = "center",
            vscroll = true,
            rpad = 12,
            borderBox = true,
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                children = cards,
            },
        }
    end
    local titleParts = Title("Recruit a Hero", "Adventurers looking for work. Choose one and give them a name.")
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
                Button("Cancel", function() dlg:DestroySelf() end, 160),
            },
        },
    }
    host:AddChild(dlg)
end

local GUILD_STYLES = {
    {
        selectors = { "eotwGuildRow" },
        bgcolor = "#ffffff0c",
        borderWidth = 1,
        borderColor = "#00000000",
    },
    {
        selectors = { "eotwGuildRow", "hover" },
        bgcolor = "#ffffff16",
    },
    {
        selectors = { "eotwGuildRow", "active" },
        borderColor = "#ffd66baa",
    },
    {
        selectors = { "eotwGuildPick" },
        bgcolor = "#ffffff0c",
    },
    {
        selectors = { "eotwGuildPick", "hover" },
        bgcolor = "#ffffff20",
        brightness = 1.1,
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
}

--One roster row: portrait, name, details, status, and the hero's actions.
local function GuildRow(hero, away, host)
    local heroid = hero.heroid
    local summary = hero.summary or {}
    local tok = dmhub.GetCharacterById(heroid)
    local portrait = summary.portrait
    local name = summary.name or "Hero"
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
        status[#status+1] = "Active in town"
    end
    if away ~= nil then
        status[#status+1] = string.format("Away: %s", away)
    end
    if tok == nil then
        status[#status+1] = "Loading..."
    end

    local confirmingDismiss = false

    return gui.Panel{
        classes = { "eotwGuildRow", cond(hero.active == true, "active", nil) },
        width = "100%",
        height = 112,
        flow = "horizontal",
        bgimage = "panels/square.png",
        cornerRadius = 8,
        pad = 8,
        borderBox = true,
        vmargin = 3,

        Portrait(portrait, 72, 96),

        gui.Panel{
            width = "100%-330",
            height = "100%",
            flow = "vertical",
            valign = "center",
            lmargin = 14,
            gui.Label{
                text = name,
                fontSize = 24,
                bold = true,
                color = TEXT,
                width = "100%",
                height = "auto",
                textWrap = false,
                minFontSize = 12,
            },
            gui.Label{
                text = details,
                fontSize = 16,
                color = DIM,
                width = "100%",
                height = "auto",
            },
            gui.Label{
                text = table.concat(status, "  -  "),
                fontSize = 15,
                italics = true,
                color = "#ffd66b",
                width = "100%",
                height = "auto",
                tmargin = 4,
            },
        },

        gui.Panel{
            width = 230,
            height = "100%",
            halign = "right",
            flow = "horizontal",

            gui.Panel{
                classes = { "eotwGuildIcon", cond(hero.active == true, "on", nil) },
                bgimage = cond(hero.active == true, "phosphor/star-fill.png", "phosphor/star.png"),
                hoverCursor = "pressbutton",
                linger = function(element)
                    gui.Tooltip(cond(hero.active == true, "Active: adventuring in town. Click to rest them.", string.format("Make active: up to %d heroes adventure in town at once.", EotwRoster.MAX_ACTIVE)))(element)
                end,
                press = function()
                    audio.FireSoundEvent("Mouse.Click")
                    EotwRoster.SetActive(heroid, hero.active ~= true)
                end,
            },
            gui.Panel{
                classes = { "eotwGuildIcon" },
                bgimage = "phosphor/pencil-simple.png",
                hoverCursor = "pressbutton",
                linger = function(element)
                    if EotwRoster.CanRebuildHero(heroid) then
                        gui.Tooltip("Rebuild this hero. You can change a hero's build until their first encounter.")(element)
                    else
                        gui.Tooltip("Open this hero's character sheet")(element)
                    end
                end,
                press = function()
                    audio.FireSoundEvent("Mouse.Click")
                    EotwRoster.EditHero(heroid, host)
                end,
            },
            gui.Panel{
                classes = { "eotwGuildIcon" },
                bgimage = "phosphor/trash.png",
                hoverCursor = "pressbutton",
                linger = function(element)
                    if away ~= nil then
                        gui.Tooltip("This hero is in a party and cannot be dismissed.")(element)
                    else
                        gui.Tooltip("Dismiss this hero from your roster (click twice). This cannot be undone.")(element)
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
    local statusLabel = nil
    local createButton = nil
    local recruitButton = nil
    local discardButton = nil
    local confirmingDiscard = false

    local Rebuild = function()
        if listPanel == nil or not listPanel.valid then
            return
        end
        local heroes = EotwRoster.GetHeroes()
        local away = EotwRoster.AwayHeroes()
        local rows = {}
        if heroes == nil then
            rows[1] = gui.Label{ text = "Consulting the guild's ledgers...", fontSize = 18, color = DIM, width = "auto", height = "auto", halign = "center", vmargin = 30 }
        elseif #heroes == 0 then
            rows[1] = gui.Label{ text = "Your roster is empty. Create a hero of your own, or recruit one of the adventurers looking for work.", fontSize = 18, color = DIM, width = "80%", height = "auto", halign = "center", textAlignment = "center", vmargin = 30 }
        else
            for _,hero in ipairs(heroes) do
                rows[#rows+1] = GuildRow(hero, away[hero.heroid], host)
            end
        end
        listPanel.children = rows

        local count = EotwRoster.LivingCount()
        if headerLabel ~= nil and headerLabel.valid then
            headerLabel.text = string.format("%d / %d heroes   <color=#d9b56a>%d / %d active</color>", count, EotwRoster.MAX_LIVING, #EotwRoster.ActiveHeroes(), EotwRoster.MAX_ACTIVE)
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
        local hasDraft = EotwRoster.FindDraft() ~= nil
        if createButton ~= nil and createButton.valid then
            createButton.text = cond(hasDraft, "Continue Your Hero", "Create a Hero")
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
                text = "Your Roster",
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
        },
        gui.Label{
            text = string.format("Mark up to %d heroes as active to adventure in town. Any of them can set out from the Town Gate.", EotwRoster.MAX_ACTIVE),
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
                text = "Create a Hero",
                fontSize = 20,
                width = 230,
                height = 46,
                hmargin = 6,
                create = function(element)
                    createButton = element
                end,
                click = function()
                    if not EotwRoster.CanAddHero() then
                        Fail(string.format("Your roster is full (%d heroes).", EotwRoster.MAX_LIVING))
                        return
                    end
                    EotwRoster.lastError = nil
                    EotwRoster.CreateHero(host)
                end,
            },
            gui.Button{
                text = "Discard Draft",
                fontSize = 20,
                width = 200,
                height = 46,
                hmargin = 6,
                classes = { "collapsed" },
                create = function(element)
                    discardButton = element
                end,
                linger = function(element)
                    gui.Tooltip("Throw away the hero you have not finished (click twice).")(element)
                end,
                resetConfirm = function(element)
                    confirmingDiscard = false
                    element.text = "Discard Draft"
                end,
                click = function(element)
                    if not confirmingDiscard then
                        confirmingDiscard = true
                        element.text = "Really Discard?"
                        element:ScheduleEvent("resetConfirm", 4)
                        return
                    end
                    confirmingDiscard = false
                    element.text = "Discard Draft"
                    EotwRoster.DiscardDraft()
                end,
            },
            gui.Button{
                text = "Recruit a Hero",
                fontSize = 20,
                width = 230,
                height = 46,
                hmargin = 6,
                create = function(element)
                    recruitButton = element
                end,
                click = function()
                    if not EotwRoster.CanAddHero() then
                        Fail(string.format("Your roster is full (%d heroes).", EotwRoster.MAX_LIVING))
                        return
                    end
                    EotwRoster.lastError = nil
                    ShowRecruitPicker(host)
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
                if element.data.seen ~= EotwRoster.revision then
                    element.data.seen = EotwRoster.revision
                    Rebuild()
                end
            end,
        },
    }
    EotwRoster.Refresh()
    return body
end

--- the Graveyard ----------------------------------------------------------

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
            rows[1] = gui.Label{ text = cond(loading, "Reading the headstones...", "No one has fallen yet. May it stay that way."), fontSize = 18, color = DIM, width = "auto", height = "auto", halign = "center", vmargin = 30 }
        end
        for _,g in ipairs(graves) do
            local e = g.epitaph or {}
            local mine = g.userid == dmhub.loginUserid
            local lines = {
                EotwRoster.FormatDetails(e.level, e.ancestry, e.className),
            }
            local fell = "Fell"
            if type(e.encounter) == "string" and e.encounter ~= "" then
                --an encounter key; a community one reads "<title> (<module>)".
                local eotw = rawget(_G, "EncounterOfTheWeek")
                local where = e.encounter
                if eotw ~= nil and eotw.EncounterDisplayName ~= nil then
                    where = eotw.EncounterDisplayName(e.encounter)
                end
                fell = fell .. " in " .. where
            end
            if type(g.at) == "number" then
                fell = fell .. ", " .. DescribeServerTimestamp(g.at)
            end
            lines[#lines+1] = fell
            lines[#lines+1] = string.format("Played by %s", e.owner or "?")
            rows[#rows+1] = gui.Panel{
                width = "100%",
                height = 100,
                flow = "horizontal",
                bgimage = "panels/square.png",
                bgcolor = cond(mine, "#2a2418cc", "#ffffff0a"),
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
                    gui.Label{ text = e.name or "Hero", fontSize = 22, bold = true, color = TEXT, width = "100%", height = "auto" },
                    gui.Label{ text = table.concat(lines, "\n"), fontSize = 14, color = DIM, width = "100%", height = "auto" },
                },
            }
        end
        if more then
            rows[#rows+1] = Button("Older graves...", LoadMore, 220)
        end
        listPanel.children = rows
    end

    local titleParts = Title("The Graveyard", "Here lie the heroes of Blackbottom who did not come home.")
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
                Button("Leave", function() dlg:DestroySelf() end, 180),
            },
        },
    }
    host:AddChild(dlg)
    LoadMore()
    return dlg
end
