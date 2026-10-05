local mod = dmhub.GetModLoading()

--Encounter of the Week: a dev-gated game mode where groups of players fight
--an AI-run encounter on a weekly map. This file holds the dev setting gate,
--the global entry point, and the titlescreen screen. The titlescreen's
--top-right link (CodexTitlescreen.lua) calls EncounterOfTheWeek.ShowScreen().
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md.
--
--This lives in the Codex Titlescreen module (NOT the EncounterOfTheWeek mod)
--because separate dev codemods only load in games that install them -- the
--titlescreen runs in the local lobby game, which loads only the core codex.
--It must be registered before CodexTitlescreen.lua, which reads the global.
--
--The screen is the town of Blackbottom: the town map with clickable
--locations (the Hero's Guild, the Town Gate, the Graveyard) and the player's
--active heroes along the bottom. It connects to the Blackbottom City -- a
--server-arbitrated lobby (chat, presence, the parties roster) that also
--stores every account's heroes -- through the engine's lobbies bridge
--(lobbies:Connect, route "city"). All city state is written server-side;
--this UI renders the document and sends typed requests. The roster, the
--Guild and the Graveyard live in EotwRoster.lua; the hero cards in
--EotwHeroCard.lua.

EncounterOfTheWeek = {}

--Dev gate. No editor entry, so it never appears in the settings UI;
--toggle from chat with: /toggle dev:encounteroftheweek
EncounterOfTheWeek.enabledSetting = setting{
    id = "dev:encounteroftheweek",
    default = false,
    storage = "preference",
}

--True if the Encounter of the Week mode is available to this user at all.
function EncounterOfTheWeek.Enabled()
    return dmhub.GetSettingValue("dev:encounteroftheweek") == true
end

--Debug "New Player Window" (the Codex menu while this screen is open, admin
--accounts only; see EncounterOfTheWeek.CodexMenuItems): launches a second
--copy of the app logged in as the secondary account with `--eotw`. That
--child opens this screen on reaching the titlescreen and is from then on an
--ordinary separate player -- its own roster, heroes and parties -- so the
--multiplayer flow can be exercised from one machine.
EncounterOfTheWeek.autoOpen = false
do
    for _,str in ipairs(dmhub.commandLineArguments) do
        if str == "--eotw" then
            EncounterOfTheWeek.autoOpen = true
        end
    end
end

--One shot: true the first time it is asked in a child launched with --eotw.
--The titlescreen calls ShowScreen for it on reaching the selection screen
--(the arg bypasses the dev gate, so the secondary account needs no setup).
function EncounterOfTheWeek.WantsAutoOpen()
    local result = EncounterOfTheWeek.autoOpen
    EncounterOfTheWeek.autoOpen = false
    return result
end

--Set by the game-side EotW codemod just before it exits a finished game
--(victory/defeat concluded): holds that game's id, or "". The screen's
--resume refresh destroys the finished game / clears the account slot and
--resets this -- a decided encounter is never offered for resume. Same
--setting id as the game codemod's declaration (settings are keyed globally).
setting{
    id = "eotw:concludedgame",
    default = "",
    storage = "preference",
}

--The town's city (see EotwRoster.lua), on staging until EotW nears release.
local LOBBY_ID = EotwRoster.CITY_ID
local LOBBY_OPTIONS = EotwRoster.CITY_OPTIONS

--The town map: Miska Fredman's Blackbottom map with its grid and labels
--removed, as a core image asset. PLACEHOLDER: a psd-tools render, slightly
--washed out next to Photoshop's -- replace with a Photoshop export at the
--same 4096x2980 (see the design doc) and update this id.
local CITY_MAP_IMAGE = "39beb163-c5b5-408d-be3c-191825776239"
local CITY_MAP_ASPECT = 4096 / 2980

--Art for the locations that take over the whole screen when opened (see
--LocationScene in CreateScreen): Czepeku Scenes stills (3840x2160) uploaded
--as core image assets, tagged with their creator so the scene credits them
--(DMHub Core UI/CreatorCredit.lua). A scene's art may also be a video id.
local GUILD_ART = "db897e57-df62-48f0-a241-87add567824c" --Viking Longhouse, Original Day
local GATE_ART = "db5bcf88-00fc-4e0b-89c9-5ddb98d1a772" --Market Streets, Original Day
CreatorCredit.RegisterArt(GUILD_ART, "czepeku")
CreatorCredit.RegisterArt(GATE_ART, "czepeku")

--The town's locations, as fractions of the map image (so they survive a
--re-export at another size). open(ctx) runs on click; locked(ctx) returns
--the reason the location is closed, or nil. A location with a scene opens
--full screen over its art instead of as a dialog over the map; focusX is
--where to crop the art on screens that are not 16:9.
local CITY_LOCATIONS = {
    {
        id = "guild",
        label = "Hero's Guild",
        icon = "phosphor/shield-star-fill.png",
        x = 0.44,
        y = 0.42,
        scene = {
            art = GUILD_ART,
            aspect = 16 / 9,
            focusX = 0.5,
            title = "The Hero's Guild",
            tagline = "A fire in the hearth, shields on the walls, and a ledger of every hero sworn to the guild. Create a hero, take on a recruit, or choose who adventures in town.",
        },
        open = function(ctx) ctx.OpenGuild() end,
    },
    {
        id = "gate",
        label = "Town Gate",
        icon = "phosphor/sword-fill.png",
        x = 0.53,
        y = 0.135,
        scene = {
            art = GATE_ART,
            aspect = 16 / 9,
            focusX = 0.35,
            title = "The Town Gate",
            tagline = "Parties muster in the market below the old tower before they set out. Join one that is forming, or gather your own.",
        },
        locked = function(ctx)
            if EotwRoster.GetHeroes() == nil then
                return "The guild is still checking your roster..."
            end
            if EotwRoster.LivingCount() == 0 then
                return "You need a hero before you can venture out. Visit the Hero's Guild."
            end
            return nil
        end,
        open = function(ctx) ctx.OpenGate() end,
    },
    {
        id = "graveyard",
        label = "Graveyard",
        icon = "phosphor/cross-fill.png",
        x = 0.31,
        y = 0.86,
        open = function(ctx) ctx.OpenGraveyard() end,
    },
}

--The CITY_LOCATIONS row with this id.
--- @param id string
--- @return table
local function CityLocation(id)
    for _,loc in ipairs(CITY_LOCATIONS) do
        if loc.id == id then
            return loc
        end
    end
    error("EotW: no town location " .. id)
end

--Style pack for gui.Check in the create dialog. The titlescreen's legacy
--cascade has no checkbox rules (they live in the themed default styles), so
--without these the check square never paints and the label wraps into a
--sliver. Same pattern and values as ModShare.lua's g_CheckboxStyles.
local g_CheckboxStyles = {
    {
        selectors = {"checkbox"},
        bgimage = true,
        flow = "horizontal",
        bgcolor = "clear",
        height = 30,
        width = "auto",
        minWidth = 200,
        hpad = 4,
    },
    {
        selectors = {"checkBackground"},
        bgimage = true,
        bgcolor = "#080B09",
        halign = "left",
        valign = "center",
        height = "70%",
        width = "100% height",
        rmargin = 6,
        borderColor = "#DFDFDF",
        borderWidth = 2,
    },
    {
        selectors = {"checkMark"},
        bgimage = true,
        bgcolor = "#CECECE",
        halign = "center",
        valign = "center",
        width = "50%",
        height = "50%",
    },
    {
        selectors = {"checkboxLabel"},
        halign = "left",
        valign = "center",
        textAlignment = "left",
        borderWidth = 0,
        width = "auto",
        height = "auto",
        fontSize = 18,
    },
}

--What EotW games are created with. The real starting module is
--codex-encounteroftheweek (Phase 5 -- not yet authored/published), so until
--it exists we stand in the Custom Campaign starter so created games are
--playable. Games live on the staging DO backend alongside the lobby.
local STARTING_MODULE = "mcdm-encounteroftheweek"
local GAME_BACKEND = "durableobjects-staging"

--Art for the standard game loading screen shown while entering an EotW game
--(and recorded as the game's cover art at create time). Same image the
--Delian Tomb adventure uses; update alongside the weekly encounter.
local LOADING_SCREEN_ART = "panels/backgrounds/delian-tomb-bg.png"

--The week's module ships one or more encounter maps: one named exactly
--this (the default) and any number named "<this>: <title>". The create-game
--dialog lists them and the choice rides on the lobby roster record as the
--map's NAME (ids change weekly; names do not). Mirrored by the publisher
--(tools/eotw_publish, is_encounter_map_name) and the game-side resolver in
--EncounterOfTheWeek/EncounterOfTheWeek.lua -- keep the three in step.
local ENCOUNTER_MAP_NAME = "Encounter"

--The party size an EotW game allows: Begin needs MIN_HEROES filled slots and
--a game holds at most MAX_HEROES. The lobby server enforces both
--(MIN_HEROES_TO_LAUNCH / SLOTS_TOTAL in cloudflare-game-server/src/lobby-core.ts);
--these only drive the UI, so keep them in step with it.
local MIN_HEROES = 4
local MAX_HEROES = 6

--How long to let the loading screen dissolve in before this screen ducks
--out from under it. The titlescreen's loading screen fades in over 0.3s
--(the "loadingScreen"/"create" style pair in CodexTitlescreen.lua); hiding
--any sooner makes the player watch this screen blink out and the loading
--art transition in over the bare titlescreen instead.
local LOADING_SCREEN_FADE_IN_SECONDS = 0.35

--Hero card geometry (3:4 portrait aspect, matching the character panel's
--portrait frame) and the entrance-animation timing for new heroes.
local HERO_CARD_WIDTH = 176
local HERO_CARD_HEIGHT = 235
local HERO_CARD_ASPECT = HERO_CARD_WIDTH / HERO_CARD_HEIGHT
local HERO_CARD_GROW_TIME = 0.3

--Portrait warm-up cadence (see the warm-up section below). The eligible
--set grows asynchronously -- the pregen snapshot lands after the screen
--opens, and its art has to be re-registered after returning from a game --
--so the warmer re-scans a few times rather than assuming one pass sees
--everything. It stops early once the pregen cache has landed and a pass
--finds nothing new.
local PORTRAIT_WARM_RESCAN_SECONDS = 2
local PORTRAIT_WARM_PASSES = 8
--Warming is amortized: mounting every portrait panel in one tick made the
--engine decode a dozen textures inside a single frame, which was most of
--the hitch a cold open used to show. A handful per tick spreads that over
--frames. The first pass now starts as soon as the screen is built, which
--is UNDER the loading veil: the veil waits for the warm-up to settle before
--it reveals (see PortraitWarmupSettled), so those decodes are spent on a
--deliberate loading screen instead of hitching a screen the player is
--already looking at.
local PORTRAIT_WARM_BATCH = 3
local PORTRAIT_WARM_BATCH_SECONDS = 0.05
local PORTRAIT_WARM_START_SECONDS = 0.05

--Opening the screen is not free: building the panel tree, connecting to
--the lobby and pulling the first textures cost a beat or two, and doing
--all of it inline meant the screen appeared and then froze mid-paint for
--a second or more. So a cheap veil (text only -- nothing that has to
--stream) goes up first, the real screen is built behind it, and the two
--cross-fade once the build has settled. Every delay below is measured
--from the moment the preceding step FINISHED -- ScheduleEvent is
--wall-clock, so a build that stalls the frame pushes the reveal back
--instead of uncovering a half-drawn screen.
local VEIL_FADE_IN_SECONDS = 0.12
--let the veil paint and finish fading in before the build stalls a frame.
local VEIL_BUILD_DELAY_SECONDS = 0.15
--after the build returns, a beat for layout before we start asking whether
--the screen's art has arrived.
local VEIL_SETTLE_SECONDS = 0.35
local VEIL_CROSSFADE_SECONDS = 0.3

--After that beat the veil WAITS for the screen's streamed art (the
--portraits, warmed by CreatePortraitWarmer) instead of revealing on a
--timer, so the texture decodes land behind the veil rather than hitching a
--screen the player is already looking at. Two escape hatches keep that
--from inheriting the worst case of the slowest -- or a never-arriving --
--image, which is exactly what sank the rejected Add-a-Hero cover: a
--stretch with NO progress at all counts as settled, and a hard deadline
--reveals regardless.
local VEIL_WAIT_POLL_SECONDS = 0.1
local VEIL_WAIT_IDLE_SECONDS = 0.5
local VEIL_WAIT_MAX_SECONDS = 4

--- the encounter pool ------------------------------------------------
--Every encounter a party can set out to face, for the Form a Party dialog.
--It comes from two kinds of module:
--  * the official module (STARTING_MODULE). Every EotW game is created from
--    it, because it carries the EotW and Monster AI codemods, the Start
--    keyword and the Hero Death rule. Its own encounter maps are in the pool.
--  * community "Encounter of the Week" modules: any module published Public
--    with moduleType == EncounterOfTheWeek.MODULE_TYPE (the publish dialog,
--    DMHub Core Panels/ModShare.lua). When a party picks one of these, the
--    host installs that module on top of the official one during setup
--    (EncounterOfTheWeek/EncounterOfTheWeek.lua, EnsureEncounterModule).
--Both are read from module records -- contentSummary lists the maps and
--publishingProperties.eotwEncounters the "# Town Gate" text -- so listing
--the pool downloads no module content. A map counts only if it follows the
--encounter naming rule below.

EncounterOfTheWeek.OFFICIAL_MODULE = STARTING_MODULE
EncounterOfTheWeek.MODULE_TYPE = "eotw"

--nil until loaded; then the pool, a list of entries
--  { key, moduleid, mapName, title, official, moduleName, author, townGate }
--with the official module's first (its default map leading), then each
--community module's, grouped, modules ordered by name.
local m_encounters = nil
local m_encountersFetching = false
--key -> entry, for the same entries.
local m_encounterByKey = {}
--Every community EotW module the last fetch saw, pulled ones included, for
--the admin pool dialog: list of { moduleid, name, author, pulled, count }.
local m_poolModules = {}
--callbacks waiting on the fetch in flight (EncounterOfTheWeek.RefreshPool).
local m_poolCallbacks = {}

--The naming rule: exactly ENCOUNTER_MAP_NAME, or "ENCOUNTER_MAP_NAME: <title>".
function EncounterOfTheWeek.IsEncounterMapName(name)
    if type(name) ~= "string" then
        return false
    end
    return name == ENCOUNTER_MAP_NAME or name:sub(1, #ENCOUNTER_MAP_NAME + 2) == ENCOUNTER_MAP_NAME .. ": "
end

--An encounter is named by a KEY string. For the official module it is the
--map name ("Encounter: Goblin Ambush"), which is all party records and
--completions carried before the pool existed. For a community module it is
--"<moduleid>|<map name>", so two modules can each ship an "Encounter".
--The key rides the party record (`encounter`), the game's state doc, the
--outcome log and the City's completions (one Victory per hero per key).
--The game side parses it with its own copy of ParseEncounterKey
--(EncounterOfTheWeek/EncounterOfTheWeek.lua); keep the two in step.
function EncounterOfTheWeek.EncounterKey(moduleid, mapName)
    if moduleid == nil or moduleid == "" or moduleid == STARTING_MODULE then
        return mapName
    end
    return moduleid .. "|" .. mapName
end

--key -> moduleid, map name. nil or "" is the official module's default map.
function EncounterOfTheWeek.ParseEncounterKey(key)
    if type(key) ~= "string" or key == "" then
        return STARTING_MODULE, ENCOUNTER_MAP_NAME
    end
    local moduleid, mapName = key:match("^([^|]+)|(.+)$")
    if moduleid == nil then
        return STARTING_MODULE, key
    end
    return moduleid, mapName
end

--"Encounter: Goblin Ambush" -> "Goblin Ambush". The bare default map reads
--as its own name.
function EncounterOfTheWeek.MapTitle(mapName)
    if type(mapName) ~= "string" then
        return ENCOUNTER_MAP_NAME
    end
    return mapName:match("^" .. ENCOUNTER_MAP_NAME .. ":%s*(.+)$") or mapName
end

--A key as a player should read it: the official module's map names as they
--always were, and "<title> (<module name>)" for a community encounter. Uses
--the module id when the pool has not loaded (or no longer lists it).
function EncounterOfTheWeek.EncounterDisplayName(key)
    local moduleid, mapName = EncounterOfTheWeek.ParseEncounterKey(key)
    if moduleid == STARTING_MODULE then
        return mapName
    end
    local entry = m_encounterByKey[key]
    local moduleName = moduleid
    if entry ~= nil and entry.moduleName ~= nil and entry.moduleName ~= "" then
        moduleName = entry.moduleName
    end
    return string.format("%s (%s)", EncounterOfTheWeek.MapTitle(mapName), moduleName)
end

--The pool entries one module record offers, default map first, then by title.
local function ModuleEncounters(info, moduleid)
    local official = moduleid == STARTING_MODULE
    local summary, published, name, author = nil, nil, nil, nil
    pcall(function() summary = info.contentSummary end)
    pcall(function() published = info.publishingProperties.eotwEncounters end)
    pcall(function() name = info.name end)
    pcall(function() author = info.authorid end)

    local result = {}
    local seen = {}
    for _,entry in ipairs(summary or {}) do
        local kind = string.lower(tostring(entry.type or ""))
        if kind == "map" or kind == "maps" then
            for _,item in ipairs(entry.items or {}) do
                if EncounterOfTheWeek.IsEncounterMapName(item) and not seen[item] then
                    seen[item] = true
                    local townGate = nil
                    local story = type(published) == "table" and published[item] or nil
                    if type(story) == "table" and type(story.townGate) == "string" and story.townGate ~= "" then
                        townGate = story.townGate
                    end
                    result[#result+1] = {
                        key = EncounterOfTheWeek.EncounterKey(moduleid, item),
                        moduleid = moduleid,
                        mapName = item,
                        title = EncounterOfTheWeek.MapTitle(item),
                        official = official,
                        moduleName = name,
                        author = author,
                        townGate = townGate,
                    }
                end
            end
        end
    end
    table.sort(result, function(a, b)
        if (a.mapName == ENCOUNTER_MAP_NAME) ~= (b.mapName == ENCOUNTER_MAP_NAME) then
            return a.mapName == ENCOUNTER_MAP_NAME
        end
        return a.title < b.title
    end)
    return result
end

--A community module record's pool standing: "pool" if its encounters are
--offered, "pulled" if an admin took it out, or nil if it does not belong
--(not an EotW module, not Public, deleted or deprecated). The index the
--candidates come from is an incrementally updated local cache that never
--hears about a module leaving it, so this is always asked of a fresh record.
local function PoolStanding(info)
    local standing = nil
    pcall(function()
        if info.moduleType ~= EncounterOfTheWeek.MODULE_TYPE or not info.published or info.deleted or info.deprecated then
            return
        end
        if info.publishingProperties.eotwPulled == true then
            standing = "pulled"
        else
            standing = "pool"
        end
    end)
    return standing
end

--Kick off (or re-kick after a failure) the pool fetch. Safe to call any
--time; no-ops while a fetch is in flight or once loaded, unless force.
function EncounterOfTheWeek.CacheEncounters(force)
    if m_encountersFetching then
        return
    end
    if m_encounters ~= nil and not force then
        return
    end
    if module.DownloadModuleInfo == nil then
        m_encounters = {}
        return
    end

    m_encountersFetching = true

    local officialEntries = nil
    --moduleid -> { info, standing, entries } for each community module.
    local community = {}
    --one for the official record and one for the index query; each
    --community record fetched adds one.
    local pending = 2

    local Finish = function()
        pending = pending - 1
        if pending > 0 then
            return
        end
        m_encountersFetching = false
        local callbacks = m_poolCallbacks
        m_poolCallbacks = {}
        if mod.unloaded then
            return
        end

        if officialEntries ~= nil then
            local list = {}
            for _,entry in ipairs(officialEntries) do
                list[#list+1] = entry
            end

            local modules = {}
            for moduleid,c in pairs(community) do
                local name = nil
                pcall(function() name = c.info.name end)
                local author = nil
                pcall(function() author = c.info.authorid end)
                modules[#modules+1] = {
                    moduleid = moduleid,
                    name = name or moduleid,
                    author = author,
                    pulled = c.standing == "pulled",
                    count = #c.entries,
                    entries = c.entries,
                }
            end
            table.sort(modules, function(a, b)
                if a.name ~= b.name then
                    return a.name < b.name
                end
                return a.moduleid < b.moduleid
            end)
            for _,m in ipairs(modules) do
                if not m.pulled then
                    for _,entry in ipairs(m.entries) do
                        list[#list+1] = entry
                    end
                end
                m.entries = nil
            end

            local byKey = {}
            for _,entry in ipairs(list) do
                byKey[entry.key] = entry
            end
            m_encounters = list
            m_encounterByKey = byKey
            m_poolModules = modules
            printf("EotW: the pool holds %d encounter(s): %d official, the rest from %d community module(s)", #list, #officialEntries, #modules)
        end
        --else the official record failed: m_encounters stays as it was
        --(nil on a first fetch), so the next open retries.

        for _,callback in ipairs(callbacks) do
            callback()
        end
    end

    module.DownloadModuleInfo{
        moduleid = STARTING_MODULE,
        success = function(info)
            officialEntries = ModuleEncounters(info, STARTING_MODULE)
            Finish()
        end,
        failure = function(msg)
            printf("EotW: could not fetch the official module record for the encounter pool: %s", tostring(msg))
            Finish()
        end,
    }

    module.QueryModuleIndex{
        index = "all",
        success = function(index)
            local ids = {}
            index:Search{
                text = "",
                maxResults = 1000000,
                success = function(result)
                    for _,item in ipairs(result.items or {}) do
                        local moduleType, id = nil, nil
                        pcall(function()
                            moduleType = item.moduleType
                            id = item.fullid
                        end)
                        if moduleType == EncounterOfTheWeek.MODULE_TYPE and type(id) == "string" and id ~= STARTING_MODULE then
                            ids[#ids+1] = id
                        end
                    end
                end,
            }
            pending = pending + #ids
            for _,id in ipairs(ids) do
                module.DownloadModuleInfo{
                    moduleid = id,
                    success = function(info)
                        local standing = PoolStanding(info)
                        if standing ~= nil then
                            community[id] = { info = info, standing = standing, entries = ModuleEncounters(info, id) }
                        end
                        Finish()
                    end,
                    failure = function(msg)
                        printf("EotW: could not fetch pool module %s: %s", id, tostring(msg))
                        Finish()
                    end,
                }
            end
            Finish()
        end,
        failure = function(msg)
            printf("EotW: could not query the module index for the encounter pool: %s", tostring(msg))
            Finish()
        end,
    }
end

--Re-fetch the pool now (it is otherwise fetched once per app run), then
--call callback() when it lands. Used by the admin pool dialog, and by Form a
--Party so a module published since the town opened shows up.
function EncounterOfTheWeek.RefreshPool(callback)
    if callback ~= nil then
        m_poolCallbacks[#m_poolCallbacks+1] = callback
    end
    EncounterOfTheWeek.CacheEncounters(true)
end

--nil while unavailable/loading; otherwise the pool's entries (see m_encounters).
function EncounterOfTheWeek.GetEncounters()
    EncounterOfTheWeek.CacheEncounters()
    return m_encounters
end

--The pool entry for a key, or nil (not loaded, pulled, or unknown).
function EncounterOfTheWeek.GetEncounter(key)
    if key == nil or key == "" then
        key = ENCOUNTER_MAP_NAME
    end
    return m_encounterByKey[key]
end

--Every community EotW module the last fetch saw, pulled ones included:
--a list of { moduleid, name, author, pulled, count }.
function EncounterOfTheWeek.GetPoolModules()
    return m_poolModules
end

--An encounter's backstory (its script's "# Town Gate" text), or nil. key is
--an encounter key as the party record carries it; "" or nil is the default map.
function EncounterOfTheWeek.GetTownGateText(key)
    local entry = EncounterOfTheWeek.GetEncounter(key)
    if entry == nil then
        return nil
    end
    return entry.townGate
end

--Admin: take a community module out of the pool (pulled = true) or put it
--back. Flips publishingProperties.eotwPulled on the module's own record; the
--database rules let an admin write any module record, and the author's next
--publish keeps the flag (the publish dialog only rewrites the properties it
--owns). callback(ok, message) when done.
function EncounterOfTheWeek.SetModulePulled(moduleid, pulled, callback)
    module.DownloadModuleInfo{
        moduleid = moduleid,
        success = function(info)
            local ok, err = pcall(function()
                info.publishingProperties.eotwPulled = cond(pulled, true, nil)
                info:Upload{
                    success = function()
                        printf("EotW: module %s %s the encounter pool", moduleid, cond(pulled, "pulled from", "restored to"))
                        if callback ~= nil then
                            callback(true)
                        end
                    end,
                    failure = function(msg)
                        if callback ~= nil then
                            callback(false, msg)
                        end
                    end,
                }
            end)
            if not ok and callback ~= nil then
                callback(false, tostring(err))
            end
        end,
        failure = function(msg)
            if callback ~= nil then
                callback(false, msg)
            end
        end,
    }
end

--── pregen hero cache ────────────────────────────────────────────────
--The codex-encounteroftheweek module ships premade heroes as module
--characters. We eagerly download its content snapshot (engine API
--module.DownloadModuleSnapshot; the snapshot is permanently disk-cached,
--so this is one network fetch per module version) and keep a light list
--for the slot-filling picker.

local PREGEN_MODULE_ID = "mcdm-encounteroftheweek"

--nil until loaded; then a sorted list of {id, name, className, ancestry, level}.
local m_pregens = nil
--tokens from the snapshot keyed by id, for later use (portraits, launch).
local m_pregenTokens = nil
local m_pregensFetching = false

--Best-effort class name for display; works for lobby hero tokens and for
--detached module-snapshot tokens alike. pcall because token.properties
--shapes vary (and game-typed instances raise on unknown members).
local function GetHeroClassName(token)
    local result = ""
    pcall(function()
        local classesTable = dmhub.GetTable("classes")
        local classes = token.properties:try_get("classes")
        if classes ~= nil then
            for _,entry in ipairs(classes) do
                local info = classesTable[entry.classid]
                if info ~= nil and info.name ~= nil then
                    result = info.name
                end
            end
        end
    end)
    return result
end

--Best-effort ancestry name for display (e.g. "Wode Elf"); "" when the
--token's properties cannot answer.
local function GetHeroAncestry(token)
    local result = ""
    pcall(function()
        local text = token.properties:RaceOrMonsterType()
        if type(text) == "string" then
            result = text
        end
    end)
    return result
end

--Best-effort hero level for display; nil when unknown.
local function GetHeroLevel(token)
    local result = nil
    pcall(function()
        local level = token.properties:CharacterLevel()
        if type(level) == "number" and level >= 1 then
            result = math.floor(level)
        end
    end)
    return result
end

--"Level 2 Wode Elf Troubadour" from whichever display parts are known.
local function FormatHeroDetails(level, ancestry, className)
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

--True when an image id is a cloud-asset GUID whose asset record is not
--loaded -- such an id cannot render (bgimage falls through to nothing).
--Non-GUID ids (md5:/thumb:/#special, icon paths, userdata portraits)
--resolve through other pipelines and are never flagged.
local function IsUnresolvableAssetId(id)
    if type(id) ~= "string" then
        return false
    end
    if string.match(id, "^%x+%-%x+%-%x+%-%x+%-%x+$") == nil then
        return false
    end
    local known = false
    pcall(function() known = assets.allAssets[id] ~= nil end)
    return not known
end

--Entering any game clears module asset stores (engine ClearModules), so
--after returning to the titlescreen the cached pregen tokens' portrait
--GUIDs can no longer resolve. Re-invoking the snapshot download makes the
--engine re-register the module's image assets (its streamed payload is
--disk-cached -- no network); on engine builds without that registration
--this is a cheap no-op and the cards fall back to silhouettes.
local m_pregenArtFetching = false
local function EnsurePregenArt()
    if m_pregenArtFetching or m_pregens == nil or module.DownloadModuleSnapshot == nil then
        return
    end
    local sample = nil
    for _,tok in pairs(m_pregenTokens or {}) do
        pcall(function() sample = tok.offTokenPortrait end)
        if sample ~= nil then
            break
        end
    end
    if not IsUnresolvableAssetId(sample) then
        return
    end
    m_pregenArtFetching = true
    module.DownloadModuleSnapshot{
        moduleid = PREGEN_MODULE_ID,
        success = function()
            m_pregenArtFetching = false
        end,
        failure = function()
            m_pregenArtFetching = false
        end,
    }
end

--Kick off (or re-kick after a failure) the pregen snapshot download.
--Safe to call any time; no-ops while a fetch is in flight or done (though
--a completed cache still re-checks that the pregen ART is registered --
--see EnsurePregenArt).
function EncounterOfTheWeek.CachePregens()
    if m_pregens ~= nil then
        EnsurePregenArt()
        return
    end
    if m_pregensFetching then
        return
    end
    --Engine builds without the snapshot API: quietly do nothing (the
    --picker shows pregens as unavailable). Unknown members on userdata
    --read as nil, so this probe is safe.
    if module.DownloadModuleSnapshot == nil then
        return
    end

    m_pregensFetching = true
    module.DownloadModuleSnapshot{
        moduleid = PREGEN_MODULE_ID,
        success = function(snapshot)
            m_pregensFetching = false
            if mod.unloaded then
                return
            end
            local result = {}
            local tokens = {}
            for charid,tok in pairs(snapshot.characters or {}) do
                --the snapshot holds EVERY character in the module,
                --including monsters placed on its maps and stray blanks;
                --only real heroes belong in the pregen picker.
                local isHero = false
                pcall(function() isHero = tok.properties:IsHero() == true end)
                if isHero then
                    tokens[charid] = tok
                    result[#result+1] = {
                        id = charid,
                        name = tok.name or "Hero",
                        className = GetHeroClassName(tok),
                        ancestry = GetHeroAncestry(tok),
                        level = GetHeroLevel(tok),
                    }
                end
            end
            --A snapshot with zero heroes means something upstream was not
            --ready (e.g. the eager boot-time warm can run before the codex
            --rules that define IsHero are loaded, so every pcall probe
            --fails). Do not commit an empty cache -- leaving m_pregens nil
            --lets the next GetPregens/ShowScreen call retry.
            if #result == 0 then
                printf("EotW: pregen snapshot yielded no heroes; will retry")
                return
            end
            table.sort(result, function(a,b) return a.name < b.name end)
            m_pregenTokens = tokens
            m_pregens = result
        end,
        failure = function(msg)
            --The module may simply not be published yet; allow a retry
            --the next time the screen opens.
            m_pregensFetching = false
            printf("EotW: could not fetch pregen module: %s", tostring(msg))
        end,
    }
end

--nil while unavailable/loading; otherwise the {id, name, className} list.
function EncounterOfTheWeek.GetPregens()
    EncounterOfTheWeek.CachePregens()
    return m_pregens
end

--The snapshot token for a pregen id (nil until the cache is loaded).
function EncounterOfTheWeek.GetPregenToken(id)
    if m_pregenTokens == nil then
        return nil
    end
    return m_pregenTokens[id]
end

--== portrait warm-up ==================================================
--The Add-a-Hero picker's cards carry streamed portrait art, so a grid
--built cold paints in halves: some cards drawn, a hitch while the rest
--decode, then the remainder popping in. Nothing in the engine preloads an
--image on request -- a texture streams because a live panel references it
--(ImageDownloader.SetImageByIdentifier, see Assets/IMAGE_MANAGEMENT.md) --
--so opening the EotW screen mounts a warmer instead: one 1x1 panel per
--eligible portrait, stacked invisibly in the screen's top-left corner,
--whose only job is to make the engine fetch the texture. By the time the
--player reaches the picker the images are resident and the grid paints in
--one pass. Nothing blocks on this: a portrait that has not arrived yet
--just behaves as it does today.
--
--Eligible = the heroes the picker can actually offer: this machine's
--titlescreen heroes and the module's pregens. Other players' heroes are
--skipped deliberately -- their portraits are per-game cloud assets that do
--not resolve here at all, which is why those cards show a silhouette.
--
--Image ids resolve by id alone; panel size selects no mip and no
--thumbnail, so a 1x1 panel warms exactly the texture the full-size card
--will later use.

--Every image id the picker could need, deduped. Reads are pcall'd because
--lobby tokens and detached snapshot tokens vary in shape, and ids are not
--always strings (userdata portraits resolve through their own pipeline),
--so the dedupe key is the id itself rather than a string.
local function EligiblePortraitImageIds()
    local seen = {}
    local result = {}

    local Add = function(id)
        if id == nil or id == "" or seen[id] ~= nil then
            return
        end
        --An unregistered cloud GUID cannot stream at all; skip it rather
        --than queue a fetch that never resolves. Left unmarked, so a later
        --pass picks it up once the module's art registers.
        if IsUnresolvableAssetId(id) then
            return
        end
        seen[id] = true
        result[#result+1] = id
    end

    local AddToken = function(tok)
        if tok == nil then
            return
        end
        pcall(function()
            local p = tok.offTokenPortrait
            --spine portraits are skeletons loaded through addressables,
            --not streamed textures; instantiating one offscreen would cost
            --more than it saves.
            if p ~= nil and not p.hasSpineAnimation then
                Add(p)
            end
        end)
        pcall(function()
            Add(tok.portraitBackground)
        end)
    end

    for _,tok in ipairs(table.values(dmhub.GetAllCharacters())) do
        AddToken(tok)
    end
    for _,tok in pairs(m_pregenTokens or {}) do
        AddToken(tok)
    end

    return result
end

--How the warm-up is going, for the loading veil to wait on (see
--PortraitWarmupSettled). Replaced wholesale by each new warmer; the veil
--only ever looks at the current screen's.
local m_warmState = nil

--The warmer panel. Floating and 1x1, so it takes part in no layout.
local function CreatePortraitWarmer()
    --ids already given a panel; a warm panel is never removed, so the
    --texture stays resident for as long as the screen is open.
    local m_warmed = {}

    --Progress for this screen. 'changed' is stamped by anything that counts
    --as progress -- a panel mounted, a texture arrived -- so the veil can
    --tell "still streaming" from "nothing is ever going to arrive".
    local warmState = {
        mounted = 0,
        ready = 0,
        drained = false,
        changed = dmhub.Time(),
    }
    m_warmState = warmState

    return gui.Panel{
        id = "eotwPortraitWarmer",
        interactable = false,
        floating = true,
        halign = "left",
        valign = "top",
        width = 1,
        height = 1,
        flow = "none",

        --deferred rather than fired inline: the first pass adds children,
        --and doing that while the panel is still starting is asking for
        --trouble. The delay is long enough to clear the screen's opening
        --cross-fade too, so no texture decode lands during the reveal.
        create = function(element)
            element:ScheduleEvent("warmPortraits", PORTRAIT_WARM_START_SECONDS, PORTRAIT_WARM_PASSES)
        end,

        --One pass = mount panels for the ids found this scan, but only
        --PORTRAIT_WARM_BATCH of them per tick: each panel makes the engine
        --stream and decode a texture, and doing a dozen at once costs a
        --visible frame. A pass that fills its batch comes straight back for
        --the rest; a pass with room to spare has drained the current
        --eligible set and waits out the rescan interval.
        warmPortraits = function(element, passesLeft)
            local added = 0
            for _,id in ipairs(EligiblePortraitImageIds()) do
                if added >= PORTRAIT_WARM_BATCH then
                    break
                end
                if m_warmed[id] == nil then
                    m_warmed[id] = true
                    added = added + 1
                    warmState.mounted = warmState.mounted + 1
                    warmState.changed = dmhub.Time()

                    --reported once per panel: imageLoaded fires on create
                    --for a texture that is already resident and again if
                    --the panel's image is later re-initialized.
                    local reported = false
                    element:AddChild(gui.Panel{
                        interactable = false,
                        width = 1,
                        height = 1,
                        halign = "left",
                        valign = "top",
                        bgimage = id,
                        bgcolor = "white",
                        imageLoaded = function(warmPanel)
                            if reported then
                                return
                            end
                            reported = true
                            warmState.ready = warmState.ready + 1
                            warmState.changed = dmhub.Time()
                        end,
                    })
                end
            end

            --more waiting in this scan: keep going without spending a pass.
            if added >= PORTRAIT_WARM_BATCH then
                element:ScheduleEvent("warmPortraits", PORTRAIT_WARM_BATCH_SECONDS, passesLeft)
                return
            end

            --Done: the pregen cache has landed and this pass found nothing
            --new, so the eligible set is complete. While m_pregens is still
            --nil the snapshot (or its art registration) is in flight, so
            --keep looking until the passes run out. Either way there is no
            --more warming to come, which is what 'drained' tells the veil:
            --from here on, only the mounted panels' textures are pending.
            if m_pregens ~= nil and added == 0 then
                warmState.drained = true
                return
            end
            if passesLeft > 1 then
                element:ScheduleEvent("warmPortraits", PORTRAIT_WARM_RESCAN_SECONDS, passesLeft - 1)
            else
                warmState.drained = true
            end
        end,
    }
end

--Whether the warm-up has quiesced, which is what the loading veil holds
--for: every panel the warmer has mounted has reported its texture and the
--eligible set is drained, OR nothing at all has moved for
--VEIL_WAIT_IDLE_SECONDS. The idle rule is what makes this safe to gate the
--UI on. An image whose record exists but whose texture never arrives fires
--no imageLoaded and would otherwise hold the veil until the deadline every
--single time -- the exact failure that sank the rejected Add-a-Hero cover
--(see the design doc). If nothing is arriving, the screen is as loaded as
--it is ever going to be, so reveal it.
local function PortraitWarmupSettled()
    local st = m_warmState
    if st == nil then
        --no warmer mounted: nothing to wait for.
        return true
    end
    if st.drained and st.ready >= st.mounted then
        return true
    end
    return dmhub.Time() - st.changed >= VEIL_WAIT_IDLE_SECONDS
end

--Eagerly warm the cache shortly after the titlescreen loads (deferred so
--boot-time systems are up), and whenever the dev gate turns on.
dmhub.Schedule(5, function()
    if mod.unloaded then
        return
    end
    if EncounterOfTheWeek.Enabled() then
        EncounterOfTheWeek.CachePregens()
    end
end)

--The currently mounted EotW screen, if any (nil or destroyed when closed).
local m_screen = nil

--The loading veil, while an open is in flight (see CreateLoadingVeil).
local m_veil = nil

local CreateScreen

--The veil the screen is built behind. Deliberately cheap: a flat dark
--panel and two labels, no streamed art of its own, so it can be up and
--painted within a frame of the click. It owns the whole opening sequence
--(build, settle, cross-fade) because every step has to be scheduled from
--the end of the previous one -- see the VEIL_* constants.
local function CreateLoadingVeil(root)
    --the screen's authoring scale (same math as CreateScreen), so the
    --veil's title is the size the screen's title will be.
    local dialog = root.data.dialog
    local uiscale = dialog.width / 1920
    if 1920 * (dialog.height / dialog.width) < 1080 then
        uiscale = dialog.height / 1080
    end

    return gui.Panel{
        id = "eotwLoadingVeil",
        classes = { "eotwVeil" },
        floating = true,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "none",
        bgimage = "panels/square.png",

        --swallow clicks on the titlescreen underneath for the length of
        --the open. Escape cancels it outright -- a player who changes
        --their mind should not have to wait for the screen to arrive and
        --then close it.
        captureEscape = true,
        escape = function(element)
            if m_screen ~= nil and m_screen.valid then
                m_screen:DestroySelf()
                m_screen = nil
            end
            element:DestroySelf()
        end,

        styles = {
            Styles.Default,
            {
                selectors = { "eotwVeil" },
                bgcolor = "#08070bfa",
                opacity = 1,
            },
            {
                selectors = { "eotwVeil", "create" },
                opacity = 0,
                transitionTime = VEIL_FADE_IN_SECONDS,
            },
            {
                selectors = { "eotwVeil", "dying" },
                opacity = 0,
                transitionTime = VEIL_CROSSFADE_SECONDS,
            },
        },

        data = { blocker = nil, waitDeadline = 0 },

        create = function(element)
            element:ScheduleEvent("buildScreen", VEIL_BUILD_DELAY_SECONDS)
        end,

        --Build the real screen, hidden, underneath. This is the expensive
        --step and may well stall the frame; the veil is already painted,
        --so that stall is spent on a deliberate loading screen instead of
        --on a half-drawn one.
        buildScreen = function(element)
            if mod.unloaded or root == nil or not root.valid then
                element:DestroySelf()
                return
            end

            --make sure the pregen list is (being) loaded by the time the
            --player reaches a game's slot picker, and the encounter list by
            --the time they open the create-game dialog.
            EncounterOfTheWeek.CachePregens()
            EncounterOfTheWeek.CacheEncounters()

            m_screen = CreateScreen{ titlescreen = root }
            m_screen:SetClass("eotwOpening", true)
            root:AddChild(m_screen)

            --The screen is invisible behind the veil but NOT inert: it has
            --to render, since that is what makes its textures stream, and
            --a live panel takes clicks whatever its opacity. So cap it
            --with a transparent blocker -- added last, so it sits above
            --everything in the screen including the floating close button
            --(which lands under the titlescreen link that opened us). The
            --reveal drops it; the self-destruct is the safety net for a
            --reveal that never comes.
            element.data.blocker = gui.Panel{
                id = "eotwOpeningBlocker",
                floating = true,
                width = "100%",
                height = "100%",
                halign = "center",
                valign = "center",
                bgimage = "panels/square.png",
                bgcolor = "clear",
                create = function(blocker)
                    --outlives the longest possible wait, so it is a safety
                    --net for a reveal that never comes and never a race
                    --with one that is merely slow.
                    blocker:ScheduleEvent("destroySelf", VEIL_SETTLE_SECONDS + VEIL_WAIT_MAX_SECONDS + 2)
                end,
                destroySelf = function(blocker)
                    blocker:DestroySelf()
                end,
            }
            m_screen:AddChild(element.data.blocker)

            --The settle beat covers layout and gets the warmer going; after
            --it the veil polls for the art rather than revealing blind.
            element.data.waitDeadline = dmhub.Time() + VEIL_SETTLE_SECONDS + VEIL_WAIT_MAX_SECONDS
            element:ScheduleEvent("waitForImages", VEIL_SETTLE_SECONDS)
        end,

        --Hold the veil while the screen's portraits are still streaming, so
        --the decodes hitch the veil instead of the revealed screen. Both
        --exits out of PortraitWarmupSettled (all-arrived, or nothing moving)
        --are backed by the deadline here, so a trickle of art that keeps
        --reporting progress forever cannot hold the screen hostage either.
        waitForImages = function(element)
            if PortraitWarmupSettled() == false and dmhub.Time() < element.data.waitDeadline then
                element:ScheduleEvent("waitForImages", VEIL_WAIT_POLL_SECONDS)
                return
            end

            element:FireEvent("revealScreen")
        end,

        revealScreen = function(element)
            if element.data.blocker ~= nil and element.data.blocker.valid then
                element.data.blocker:DestroySelf()
            end
            element.data.blocker = nil

            --the screen can be gone already (escape, or a game load
            --started under us); either way the veil's job is over.
            if m_screen ~= nil and m_screen.valid then
                m_screen:SetClass("eotwOpening", false)
            end
            element:SetClass("dying", true)
            element:ScheduleEvent("destroySelf", VEIL_CROSSFADE_SECONDS + 0.05)
        end,

        destroySelf = function(element)
            element:DestroySelf()
        end,

        destroy = function(element)
            if m_veil == element then
                m_veil = nil
            end
        end,

        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
            flow = "vertical",
            uiscale = uiscale,

            gui.Label{
                text = "Encounter of the Week",
                fontSize = 48,
                bold = true,
                color = Styles.textColor,
                width = "auto",
                height = "auto",
                halign = "center",
                vmargin = 8,
            },

            --the usual codex loading ticker (see CreateGameLoadingScreen);
            --fixed width so the growing dots do not shuffle it sideways.
            gui.Label{
                text = "Loading",
                fontSize = 22,
                color = Styles.textColor,
                opacity = 0.7,
                width = 200,
                height = "auto",
                halign = "center",
                textAlignment = "center",
                data = { n = 0 },
                thinkTime = 0.25,
                think = function(element)
                    element.data.n = (element.data.n + 1) % 4
                    element.text = "Loading" .. string.rep(".", element.data.n)
                end,
            },
        },
    }
end

--Opens the Encounter of the Week screen over the titlescreen, hosted on
--CodexTitlescreenRoot the same way the shop screen is. No-op if the screen
--is already open (or opening) or we are not at the titlescreen.
function EncounterOfTheWeek.ShowScreen()
    if m_screen ~= nil and m_screen.valid then
        --a screen hidden for a game load (see the beginLoading handler)
        --is still ours: reopen it rather than leave the player with a link
        --that does nothing.
        m_screen.data.loadingUp = false
        m_screen:SetClass("hidden", false)
        return
    end

    --an open already in flight; a second click must not stack a second
    --veil (nor a second screen behind it).
    if m_veil ~= nil and m_veil.valid then
        return
    end

    local root = rawget(_G, "CodexTitlescreenRoot")
    if root == nil or not root.valid then
        return
    end

    m_veil = CreateLoadingVeil(root)
    root:AddChild(m_veil)
end

--True while the screen is up (not closed, and not hidden for a game load).
function EncounterOfTheWeek.IsScreenOpen()
    return m_screen ~= nil and m_screen.valid and not m_screen:HasClass("hidden")
end

--Extra rows for the titlescreen's Codex menu (CodexTitleBar appends them).
--Admins get "New Player Window" while the town is open: a second app window
--logged in as the secondary account, which opens straight into this screen
--(see EncounterOfTheWeek.autoOpen). connect = false so the child does not
--borrow this process's lobby game -- it loads the secondary account's own.
function EncounterOfTheWeek.CodexMenuItems()
    if not dmhub.isAdminAccount or not EncounterOfTheWeek.IsScreenOpen() then
        return {}
    end
    return {
        {
            text = "New Player Window",
            icon = "phosphor/users-three.png",
            click = function()
                dmhub.DuplicateWindowInNewProcess{
                    asplayer = true,
                    connect = false,
                    args = "--eotw",
                }
            end,
        },
        {
            text = "Encounter Pool...",
            icon = "phosphor/sword-fill.png",
            click = function()
                EncounterOfTheWeek.ShowPoolDialog()
            end,
        },
    }
end

--Admin: the community encounter modules and their standing in the pool, with
--Pull / Restore on each (EncounterOfTheWeek.SetModulePulled). Mounted over
--the town screen; refetches the pool when it opens and after every change.
function EncounterOfTheWeek.ShowPoolDialog()
    if m_screen == nil or not m_screen.valid then
        return
    end

    local dlg
    local listPanel
    local statusLabel

    local SetStatus = function(text, isError)
        if statusLabel ~= nil and statusLabel.valid then
            statusLabel.text = text or ""
            statusLabel.selfStyle.color = cond(isError, "#ff8888", Styles.textColor)
        end
    end

    local Rebuild
    Rebuild = function()
        if listPanel == nil or not listPanel.valid then
            return
        end
        local rows = {}
        local modules = EncounterOfTheWeek.GetPoolModules()
        if #modules == 0 then
            rows[1] = gui.Label{
                text = "No community Encounter of the Week modules are published yet.",
                fontSize = 18,
                italics = true,
                color = Styles.textColor,
                width = "100%",
                height = "auto",
                textAlignment = "center",
                vmargin = 12,
            }
        end
        for _,m in ipairs(modules) do
            local byline = m.moduleid
            if m.author ~= nil and m.author ~= "" then
                byline = string.format("%s, by %s", m.moduleid, m.author)
            end
            rows[#rows+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 4,
                gui.Panel{
                    width = "100%-150",
                    height = "auto",
                    flow = "vertical",
                    valign = "center",
                    gui.Label{
                        text = m.name,
                        fontSize = 20,
                        bold = true,
                        color = cond(m.pulled, "#888888", Styles.textColor),
                        width = "100%",
                        height = "auto",
                    },
                    gui.Label{
                        text = string.format("%s -- %d encounter%s%s", byline, m.count, cond(m.count == 1, "", "s"), cond(m.pulled, " -- PULLED", "")),
                        fontSize = 14,
                        color = "#b8ad96",
                        width = "100%",
                        height = "auto",
                    },
                },
                gui.Button{
                    text = cond(m.pulled, "Restore", "Pull"),
                    fontSize = 18,
                    width = 130,
                    height = 38,
                    valign = "center",
                    click = function(element)
                        SetStatus(cond(m.pulled, "Restoring ", "Pulling ") .. m.name .. "...")
                        EncounterOfTheWeek.SetModulePulled(m.moduleid, not m.pulled, function(ok, message)
                            if not ok then
                                SetStatus("Could not change the module: " .. tostring(message), true)
                                return
                            end
                            EncounterOfTheWeek.RefreshPool(function()
                                SetStatus("")
                                Rebuild()
                            end)
                        end)
                    end,
                },
            }
        end
        listPanel.children = rows
    end

    dlg = gui.Panel{
        floating = true,
        width = 640,
        height = "auto",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#111111ff",
        borderWidth = 2,
        borderColor = Styles.textColor,
        flow = "vertical",
        pad = 16,
        borderBox = true,
        styles = { Styles.Default },

        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            element:DestroySelf()
        end,

        gui.Label{
            text = "Encounter Pool",
            fontSize = 32,
            bold = true,
            color = Styles.textColor,
            width = "auto",
            height = "auto",
            halign = "center",
            vmargin = 8,
        },
        gui.Label{
            text = "Community modules published Public as Encounter of the Week. A pulled module's encounters are not offered at the Town Gate; games already formed keep playing it.",
            fontSize = 15,
            color = "#b8ad96",
            width = "100%",
            height = "auto",
            textAlignment = "center",
            textWrap = true,
            vmargin = 4,
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            maxHeight = 520,
            vscroll = true,
            flow = "vertical",
            vmargin = 8,
            create = function(element)
                listPanel = element
            end,
        },
        gui.Label{
            text = "Loading the pool...",
            fontSize = 16,
            color = Styles.textColor,
            width = "100%",
            height = "auto",
            minHeight = 22,
            textAlignment = "center",
            create = function(element)
                statusLabel = element
            end,
        },
        gui.Button{
            text = "Close",
            fontSize = 20,
            width = 140,
            height = 42,
            halign = "center",
            vmargin = 8,
            click = function(element)
                dlg:DestroySelf()
            end,
        },
    }

    m_screen:AddChild(dlg)
    EncounterOfTheWeek.RefreshPool(function()
        SetStatus("")
        Rebuild()
    end)
end

--Builds the full-screen EotW panel: overview text, the games list driven by
--the lobby's /state/games roster, and the lobby chat + presence column.
CreateScreen = function(args)
    local dialog = args.titlescreen.data.dialog

    --Author at 1920x1080 logical resolution, using the shop screen's scale
    --math: on wider-than-16:9 screens scale by height instead, keeping 1080
    --logical height with the content centering in the extra logical width.
    local uiscale = dialog.width / 1920
    local panelHeight = 1920 * (dialog.height / dialog.width)
    local panelWidth = 1920
    if panelHeight < 1080 then
        uiscale = dialog.height / 1080
        panelHeight = 1080
        panelWidth = dialog.width / uiscale
    end

    --The lobby connection. nil when the running engine predates the
    --lobbies bridge; the screen then shows a needs-update note instead.
    local lobbiesApi = rawget(_G, "lobbies")
    local m_conn = nil
    if lobbiesApi ~= nil then
        m_conn = lobbiesApi:Connect(LOBBY_ID, LOBBY_OPTIONS)
        EotwRoster.Attach(m_conn)
    end

    local areaStyles = {
        {
            selectors = { "eotw-area" },
            --opaque, matching the guild dialogs: these float over the town map.
            bgcolor = "#14110dff",
            borderWidth = 2,
            borderColor = "#8c7a55",
            cornerRadius = 10,
        },
    }

    --forward-declared refresh targets (assigned when the panels are built).
    local gamesListPanel = nil
    local chatMessagesPanel = nil
    local presenceLabel = nil
    local statusLabel = nil
    local chatErrorLabel = nil
    local gamesErrorLabel = nil
    local gamesTitleLabel = nil
    local chatTitleLabel = nil
    local createGameButton = nil

    local resultPanel = nil
    local ShowCreateDialog = nil

    --When set, the games area shows this game's lobby view (slots + your
    --heroes) instead of the games list, and the chat column switches to
    --the game's private chat channel.
    local m_viewGameid = nil

    --The hero-card keys ("userid|kind|id") rendered by the last game-view
    --build. nil right after opening a view, so the first build renders
    --without animation; afterwards any hero not in this set is NEW and its
    --card plays the grow + fade-in entrance.
    local m_knownHeroCards = nil

    --Other players' roster heroes, read from the City for their cards, keyed
    --"userid|heroid": a detached token once loaded, false while the request
    --is out or after it failed (so each hero is asked for once per screen).
    ---@type table<string, CharacterToken|false>
    local m_remoteHeroTokens = {}

    --forward decls (assigned below; captured by earlier click handlers).
    --OpenGameView is assigned during setup, before any handler can run.
    ---@type fun()
    local RefreshGames = nil
    ---@type fun(gameid: string)
    local OpenGameView = nil
    local CloseGameView = nil
    local BuildGameView = nil
    local ShowAddHeroDialog = nil
    ---@type fun()
    local RefreshChat = nil
    local AttachMonitors = nil

    --the one modal dialog (create-game or add-hero) open over the screen;
    --guards against stacking a second copy from a double click.
    local m_modalDialog = nil

    local ShowGamesError = function(message)
        if gamesErrorLabel ~= nil and gamesErrorLabel.valid then
            gamesErrorLabel:FireEvent("showError", message)
        end
    end

    local AreaTitle = function(text, createfn)
        return gui.Label{
            text = text,
            fontSize = 30,
            bold = true,
            color = Styles.textColor,
            width = "auto",
            height = "auto",
            halign = "center",
            vmargin = 16,
            create = createfn,
        }
    end

    --The Gate scene's card is narrow over the parties list, so the art (the
    --tower) stays clear, and wide in a party view, where a full party's six
    --hero cards need one row. The list panel sits in the Gate's body, which
    --sits in the card.
    local GATE_CARD_WIDTH_LIST = 1000
    local GATE_CARD_WIDTH_PARTY = 1240
    local m_gateCardWidth = nil
    local SetGateCardWidth = function(width)
        if width == m_gateCardWidth or gamesListPanel == nil or not gamesListPanel.valid then
            return
        end
        local body = gamesListPanel.parent
        local card = body ~= nil and body.parent or nil
        if card ~= nil then
            m_gateCardWidth = width
            card.selfStyle.width = width
        end
    end

    --A small gold heading over a group of rows in a location's card.
    local ListSectionTitle = function(text)
        return gui.Label{
            text = string.upper(text),
            fontSize = 17,
            bold = true,
            color = "#d9b56a",
            width = "100%",
            height = "auto",
            tmargin = 14,
            bmargin = 6,
        }
    end

    local EmptyNote = function(text)
        return gui.Label{
            text = text,
            fontSize = 20,
            color = Styles.textColor,
            opacity = 0.6,
            width = "90%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            vmargin = 24,
        }
    end

    --── refreshers: rebuild each region from the lobby document ─────────

    --One action button on a game row.
    local RowButton = function(text, clickfn)
        return gui.Button{
            text = text,
            fontSize = 20,
            width = 130,
            height = 40,
            halign = "right",
            valign = "center",
            hmargin = 4,
            click = clickfn,
        }
    end

    --The latest roster record for a game (nil if it vanished).
    local GetGameRecord = function(gameid)
        if m_conn == nil or gameid == nil then
            return nil
        end
        local games = m_conn:GetPath("/state/games")
        return games ~= nil and games[gameid] or nil
    end

    --A mutable copy of our own hero-slot claim in a record.
    local MyHeroesCopy = function(record)
        local result = {}
        local player = record.players ~= nil and record.players[dmhub.loginUserid] or nil
        if player ~= nil and player.heroes ~= nil then
            for _,h in ipairs(player.heroes) do
                result[#result+1] = {
                    kind = h.kind,
                    id = h.id,
                    name = h.name,
                    className = h.className,
                    ancestry = h.ancestry,
                    level = h.level,
                    --the city marks a hero who already won this party's
                    --encounter; the game side skips their Victory.
                    completed = h.completed,
                }
            end
        end
        return result
    end

    --Replace our hero claim server-side; the roster broadcast refreshes
    --the view.
    local SetHeroes = function(gameid, heroes)
        if m_conn == nil then
            return
        end
        m_conn:Request{
            action = "set-heroes",
            args = { gameid = gameid, heroes = heroes },
            error = ShowGamesError,
        }
    end

    --The set-heroes entry for one of our roster heroes (a list-heroes view).
    --The city rewrites the display fields from its stored summary anyway;
    --live working-copy values just keep our own view current until it does.
    local RosterHeroSpec = function(hero)
        local summary = hero.summary or {}
        local spec = {
            kind = "roster",
            id = hero.heroid,
            name = summary.name or "Hero",
            className = summary.className or "",
            ancestry = summary.ancestry,
            level = summary.level,
        }
        local tok = dmhub.GetCharacterById(hero.heroid)
        if tok ~= nil then
            spec.className, spec.ancestry, spec.level = EotwRoster.HeroDetails(tok)
        end
        return spec, tok
    end

    --Bring our active heroes into a party we just formed or joined (user
    --direction 2026-10-03): as many as fit the open slots and our per-player
    --cap of 4, in roster order. Runs only while we hold no heroes there, so
    --it never undoes a pick. Heroes in another party are skipped, except in
    --leavingGameid, the party we are walking out of (its leave-game was sent
    --first, and the city handles requests in order).
    local ClaimActiveHeroes = function(gameid, leavingGameid)
        if m_conn == nil then
            return
        end
        local record = GetGameRecord(gameid)
        local slotsTotal = MAX_HEROES
        local slotsFilled = 0
        if record ~= nil then
            if #MyHeroesCopy(record) > 0 then
                return
            end
            slotsTotal = math.min(record.slotsTotal or MAX_HEROES, MAX_HEROES)
            slotsFilled = record.slotsFilled or 0
        end
        local space = math.min(4, slotsTotal - slotsFilled)

        local busy = {}
        for otherid,other in pairs(m_conn:GetPath("/state/games") or {}) do
            local player = other.players ~= nil and other.players[dmhub.loginUserid] or nil
            if otherid ~= gameid and otherid ~= leavingGameid and player ~= nil then
                for _,h in ipairs(player.heroes or {}) do
                    busy[h.id] = true
                end
            end
        end

        local heroes = {}
        for _,hero in ipairs(EotwRoster.ActiveHeroes()) do
            if #heroes >= space then
                break
            end
            if hero.status ~= "fallen" and not busy[hero.heroid] then
                heroes[#heroes+1] = (RosterHeroSpec(hero))
            end
        end
        if #heroes == 0 then
            return
        end
        m_conn:Request{
            action = "set-heroes",
            args = { gameid = gameid, heroes = heroes },
            --automatic, so a refusal (a slot taken meanwhile) is not an
            --error to the player: the party is joined either way and the
            --heroes can still be added by hand.
            error = function(message)
                printf("EotW: could not bring in active heroes: %s", tostring(message))
            end,
        }
    end

    ---- one-EotW-game-per-account support --------------------------------
    --Each account keeps at most one EotW game, held in a dedicated account
    --slot (lobby.eotwGameid) rather than the campaigns list. Entering a NEW
    --game destroys the previous one: the host's copy is deleted outright
    --(lobby record marked deleted + the game's Durable Object released);
    --a game someone else hosts is just left. Reads of the new engine APIs
    --are guarded so builds that predate them degrade to the old behavior
    --(unknown members on userdata read as nil, not an error).

    --The slot's gameid, or nil (also nil on engine builds without the slot).
    local EotwSlotGameid = function()
        return lobby.eotwGameid
    end

    --resume-row state, maintained by RefreshResumeState (defined after
    --RefreshGames, which it triggers when the async lookup lands).
    local m_resumeGameid = nil
    local m_resumeInfo = nil
    local RefreshResumeState = nil

    --Destroy/leave the EotW game we had before entering a new one, and
    --drop any lobby roster record we still hold for it.
    local DestroyPreviousGame = function(prevGameid)
        if prevGameid == nil then
            return
        end
        m_resumeGameid = nil
        m_resumeInfo = nil
        if m_conn ~= nil then
            --host leaving drops the roster record and its game chat.
            m_conn:Request{
                action = "leave-game",
                args = { gameid = prevGameid },
                error = function() end,
            }
        end
        lobby:LookupGame(prevGameid, function(gameinfo)
            if gameinfo == nil then
                --the lobby record is gone entirely; just clear the slot.
                if lobby.ClearEotwGame ~= nil then
                    lobby:ClearEotwGame(prevGameid)
                end
                return
            end
            if gameinfo.DeleteAndReleaseStorage ~= nil then
                gameinfo:DeleteAndReleaseStorage{
                    complete = function(success, err)
                        if not success then
                            printf("EotW: could not release old game %s storage: %s", prevGameid, tostring(err))
                        end
                    end,
                }
            else
                --engine build without the destroy API: mark it deleted /
                --walk away so it at least stops being offered.
                if gameinfo:IsOwner(nil) then
                    gameinfo:Delete()
                else
                    gameinfo:Leave()
                end
            end
        end)
    end

    --Engine-side join that records the game in the EotW account slot when
    --the engine supports it (falling back to the campaigns list otherwise).
    local EngineJoinEotw = function(gameid)
        if lobby.JoinGameEotw ~= nil then
            lobby:JoinGameEotw(gameid)
        else
            lobby:JoinGame(gameid)
        end
    end

    --Join a listed game: the lobby grants membership first (public + open
    --arbitrated server-side), then the engine-side join adds us to the
    --game's real player list, and we land in the game's lobby view to
    --pick heroes. Joining a game other than our current EotW game destroys
    --the previous one (one EotW game per account).
    local JoinGame = function(gameid)
        if m_conn == nil then
            return
        end
        m_conn:Request{
            action = "join-game",
            args = { gameid = gameid },
            success = function()
                local prev = EotwSlotGameid()
                EngineJoinEotw(gameid)
                if prev ~= nil and prev ~= gameid then
                    DestroyPreviousGame(prev)
                end
                ClaimActiveHeroes(gameid, prev)
                if OpenGameView ~= nil then
                    OpenGameView(gameid)
                end
            end,
            error = ShowGamesError,
        }
    end

    --" -- Encounter: <title>" for a roster record whose host chose an
    --encounter; "" when the record has no choice (the module's default map).
    local EncounterSuffix = function(record)
        if record ~= nil and type(record.encounter) == "string" and record.encounter ~= "" then
            return " -- " .. EncounterOfTheWeek.EncounterDisplayName(record.encounter)
        end
        return ""
    end

    --Enter the actual game world. Lobby heroes exist only in the local lobby
    --game, so they are copied to the token clipboard BEFORE entering (the
    --clipboard is engine state that survives the game switch); on arrival the
    --game-side EotW codemod pastes them into the Start zone, and on the host
    --it also spawns the weekly encounter scaled to the filled slots. The
    --arrival callback outlives this codemod's unload during the game switch,
    --so it captures only plain data and resolves the game-side global late.
    local EnterWorld = function(gameid)
        local record = GetGameRecord(gameid)
        local myHeroes = {}
        --nil when there is no lobby record (resuming an in-progress game):
        --SetupOnArrival then keeps the game's existing Number of Heroes
        --setting instead of clobbering it with a fresh clamp.
        local slotsFilled = nil
        --userids of every player with claimed heroes: the game-side host
        --setup records these as the players the encounter waits for before
        --entering combat. nil on a resume (no record) so the game keeps its
        --previously recorded roster.
        local members = nil
        --the encounter the host chose at create time: an encounter KEY (see
        --EncounterOfTheWeek.EncounterKey; "" or nil = the default map). nil on
        --a resume: the game-side setup then uses what the host stamped into
        --the game.
        local encounterMap = nil
        if record ~= nil then
            myHeroes = MyHeroesCopy(record)
            slotsFilled = record.slotsFilled or 0
            if type(record.encounter) == "string" and record.encounter ~= "" then
                encounterMap = record.encounter
            end
            members = {}
            for userid,player in pairs(record.players or {}) do
                local heroCount = 0
                if player.heroes ~= nil then
                    for _,_h in ipairs(player.heroes) do
                        heroCount = heroCount + 1
                    end
                end
                if heroCount > 0 then
                    members[#members+1] = userid
                end
            end
        end

        local clipboardIds = {}
        local lobbyTokens = {}
        for _,h in ipairs(myHeroes) do
            --town roster heroes travel exactly like lobby heroes: the id is
            --the lobby working copy's charid (see EotwRoster.lua).
            if h.kind == "lobby" or h.kind == "roster" then
                local tok = dmhub.GetCharacterById(h.id)
                if tok ~= nil then
                    lobbyTokens[#lobbyTokens+1] = tok
                    clipboardIds[#clipboardIds+1] = h.id
                else
                    printf("EotW: claimed hero %s is not in the local lobby; it will not be placed", tostring(h.id))
                end
            end
        end

        if #lobbyTokens > 0 then
            local multiCopy = nil
            pcall(function() multiCopy = dmhub.CopyTokensToClipboard end)
            if multiCopy ~= nil then
                dmhub.CopyTokensToClipboard(lobbyTokens)
            else
                --engine build without the batch clipboard API: carry the
                --first hero only rather than none.
                dmhub.CopyTokenToClipboard(lobbyTokens[1])
                clipboardIds = { clipboardIds[1] }
            end
        end

        --Arm the titlescreen's standard loading screen (art + quote + progress
        --dice, with the usual fade-in/out transition). The engine fires
        --beginLoading/endLoading around the game switch, and the titlescreen
        --only builds the screen when art was supplied -- without this, EotW
        --entry cut straight to the map. Every entry path (host on Begin,
        --members on ready, resume) funnels through EnterWorld, so all players
        --get the same loading screen, cleared when their client fully loads.
        local titlescreenRoot = rawget(_G, "CodexTitlescreenRoot")
        if titlescreenRoot ~= nil and titlescreenRoot.valid then
            titlescreenRoot:FireEventTree("overrideLoadingScreenArt", LOADING_SCREEN_ART, gameid)
        end

        --The arrival args are ALSO parked in a plain global, not just
        --captured by the callback below. The engine fires that callback the
        --instant the loading screen clears, which can be before the game's
        --own codemods have loaded: the game-side EotW codemod's id rides in
        --on the /games record, and a member whose record update lands a beat
        --late found EncounterOfTheWeekGame still nil and silently skipped
        --setup -- leaving them on the engine's default map choice with no
        --heroes placed, and so with no vision at all: a black screen showing
        --nothing but the Start zone outline (bug 32UW4UQB). A global outlives
        --every codemod load/unload, so the game side can pick the handoff up
        --itself whenever it does load. Keyed by gameid, so a leftover entry
        --can never fire in some other game.
        local arrival = {
            gameid = gameid,
            heroes = myHeroes,
            clipboardIds = clipboardIds,
            numHeroes = slotsFilled,
            members = members,
            encounterMap = encounterMap,
        }
        _G.EotwPendingArrival = arrival

        --Hold the loading screen through arrival setup: the engine then runs
        --the callback below BEHIND the loading screen and keeps it up until
        --the game side releases it -- once the opening montage stage is on
        --screen, or right after hero placement when the week has no
        --montage -- so nobody watches the map travel and the tokens pop in.
        --A 20s engine timeout backstops a game side that never releases.
        --Older engines lack the call and simply show the map as before.
        pcall(function() dmhub.HoldLoadingScreen() end)

        lobby:EnterGame(gameid, function()
            --the engine fires this only once the game has finished loading,
            --so the stamp doubles as the game side's guarantee that running
            --setup -- travelling maps, pasting tokens -- is safe now.
            arrival.ready = true

            local eotwGame = rawget(_G, "EncounterOfTheWeekGame")
            if eotwGame == nil then
                --not loaded yet; it consumes the parked args on load.
                return
            end

            if eotwGame.ConsumePendingArrival ~= nil then
                eotwGame.ConsumePendingArrival()
            elseif eotwGame.SetupOnArrival ~= nil then
                --a published module older than this handoff.
                _G.EotwPendingArrival = nil
                eotwGame.SetupOnArrival(arrival)
            end
        end)
    end

    --The host's Begin marks the roster record "launched" server-side. The
    --HOST alone reacts by entering the world; in-game setup (starting-module
    --install, hero placement, encounter spawn) runs there, and the game-side
    --codemod then sends "ready-game", flipping the record to "ready". Other
    --members enter only when they see "ready", so nobody ever loads a
    --half-initialized game (or races the host's module install). Also pulls
    --in a member who reopens this screen while their game is already
    --launched/ready (possible within the record's 5-minute TTL). Checked
    --from RefreshGames, which runs on every roster change and reconnect.
    local m_enteringWorld = false
    --Record statuses as of the first roster snapshot this screen saw.
    --Auto-entry only fires on a status TRANSITION observed by this screen:
    --a record already launched/ready when the screen opened is a game the
    --player deliberately stepped out of (or is choosing whether to rejoin),
    --so pulling them straight back in would make leaving impossible.
    --Re-entering those goes through the explicit Re-join/Resume buttons.
    local m_initialGameStatus = nil
    local CheckLaunchedGames = function()
        if m_enteringWorld or m_conn == nil then
            return
        end
        local games = m_conn:GetPath("/state/games")
        if games == nil then
            return
        end
        if m_initialGameStatus == nil then
            m_initialGameStatus = {}
            for gameid,record in pairs(games) do
                m_initialGameStatus[gameid] = record.status
            end
        end
        local myUserid = dmhub.loginUserid
        for gameid,record in pairs(games) do
            local isHost = record.hostUserid == myUserid
            local isMember = isHost or (record.players ~= nil and record.players[myUserid] ~= nil)
            if isMember and (record.status == "ready" or (record.status == "launched" and isHost))
                    and m_initialGameStatus[gameid] ~= record.status then
                m_enteringWorld = true
                EnterWorld(gameid)
                return
            end
        end
    end

    local MakeGameRow = function(gameid, record)
        local myUserid = dmhub.loginUserid
        local isHost = record.hostUserid == myUserid
        local isMember = isHost or (record.players ~= nil and record.players[myUserid] ~= nil)
        local slotsFilled = record.slotsFilled or 0
        local slotsTotal = math.min(record.slotsTotal or MAX_HEROES, MAX_HEROES)
        local isOpen = record.status == "open"

        local buttons = {}
        if isMember then
            --into the game's lobby view: slots, heroes, private chat.
            buttons[#buttons+1] = RowButton("Open", function()
                if OpenGameView ~= nil then
                    OpenGameView(gameid)
                end
            end)
        elseif isOpen and record.public == true then
            buttons[#buttons+1] = RowButton("Join", function()
                JoinGame(gameid)
            end)
        end

        local tagText = ""
        if record.public ~= true then
            tagText = "  (private)"
        end
        if not isOpen then
            tagText = tagText .. "  (launched)"
        end

        return gui.Panel{
            width = "100%",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "#ffffff0e",
            cornerRadius = 8,
            pad = 10,
            borderBox = true,
            vmargin = 4,

            gui.Panel{
                width = "100%-300",
                height = "auto",
                halign = "left",
                valign = "center",
                flow = "vertical",

                gui.Label{
                    text = string.format("%s%s", record.name or gameid, tagText),
                    fontSize = 24,
                    bold = true,
                    color = Styles.textColor,
                    width = "100%",
                    height = "auto",
                },
                gui.Label{
                    text = string.format("Hosted by %s -- %d/%d heroes%s", record.hostName or "?", slotsFilled, slotsTotal, EncounterSuffix(record)),
                    fontSize = 18,
                    color = Styles.textColor,
                    opacity = 0.8,
                    width = "100%",
                    height = "auto",
                },
            },

            gui.Panel{
                width = 290,
                height = "auto",
                halign = "right",
                valign = "center",
                flow = "horizontal",
                children = buttons,
            },
        }
    end

    --── the game lobby view: slots, heroes, membership controls ─────────

    --One filled slot row. myIndex is this hero's position in OUR claim
    --list (nil for other players' heroes); it drives the Remove button.
    --kickUserid is set (to the hero owner's userid) only when the viewer
    --is the host looking at another player's hero; it drives Kick, which
    --removes that whole player (and all their heroes) from the roster.
    --The token behind a hero record, when this machine can resolve one:
    --pregens come from the module snapshot cache, and MY roster heroes live
    --in the local lobby game. Another player's roster hero exists only on
    --their machine, so the first ask fetches it from the City (get-hero
    --carries its image records) as a detached token and rebuilds the view
    --when it lands; until then the card shows a silhouette.
    local ResolveHeroToken = function(heroEntry, mine, ownerUserid)
        if heroEntry.kind == "pregen" then
            return EncounterOfTheWeek.GetPregenToken(heroEntry.id)
        end
        --a roster hero's id IS its lobby working copy's charid (EotwRoster).
        if mine then
            return dmhub.GetCharacterById(heroEntry.id)
        end
        if heroEntry.kind ~= "roster" or ownerUserid == nil or heroEntry.id == nil then
            return nil
        end
        local key = string.format("%s|%s", ownerUserid, heroEntry.id)
        local cached = m_remoteHeroTokens[key]
        if cached ~= nil then
            return cached or nil
        end
        if m_conn == nil then
            return nil
        end
        m_remoteHeroTokens[key] = false
        m_conn:Request{
            action = "get-hero",
            args = { userid = ownerUserid, heroid = heroEntry.id, asJson = true },
            success = function(result)
                if mod.unloaded then
                    return
                end
                local tok = dmhub.CreateDetachedCharacter{
                    record = result.record,
                    assets = result.assets,
                }
                if tok == nil then
                    printf("EotW: could not read %s's hero %s from the city", ownerUserid, heroEntry.id)
                    return
                end
                m_remoteHeroTokens[key] = tok
                if m_viewGameid ~= nil then
                    RefreshGames()
                end
            end,
            error = function(message)
                printf("EotW: could not load %s's hero %s: %s", ownerUserid, heroEntry.id, tostring(message))
            end,
        }
        return nil
    end

    local heroCardStyles = {
        {
            selectors = { "heroCard" },
            borderWidth = 2,
            borderColor = "#88775faa",
            cornerRadius = 8,
            transitionTime = 0.15,
        },
        {
            selectors = { "heroCard", "hover" },
            borderColor = Styles.textColor,
            brightness = 1.08,
            transitionTime = 0.15,
        },
        --entrance: cards are created with "born", which is shed a beat
        --later; this rule then ramps out over its transitionTime, fading
        --and zooming the card in while the width tween opens its space.
        {
            selectors = { "heroCard", "born" },
            opacity = 0,
            scale = 0.85,
            transitionTime = 0.35,
        },
        --hover actions (trash/kick) only appear while the card is hovered.
        {
            selectors = { "heroCardAction" },
            opacity = 0,
        },
        {
            selectors = { "heroCardAction", "parent:hover" },
            opacity = 1,
            transitionTime = 0.15,
        },
        {
            selectors = { "heroCardAction", "hover" },
            brightness = 1.5,
            scale = 1.15,
            transitionTime = 0.1,
        },
    }

    --Shared card body: frame + portrait (or silhouette) + bottom identity
    --plate. params: tok (nil ok), name, details, ownerText, chipText, born,
    --click, and extras (floating overlay children like action buttons).
    local MakeCardPanel = function(params)
        local tok = params.tok

        --portrait art + the character's chosen frame background, when a
        --token is resolvable. All reads pcall'd: detached snapshot tokens
        --and lobby tokens vary in shape.
        local portrait = nil
        local portraitRect = nil
        local frameBg = nil
        if tok ~= nil then
            pcall(function()
                local p = tok.offTokenPortrait
                if p ~= nil then
                    portrait = p
                    if not p.hasSpineAnimation then
                        portraitRect = tok:GetPortraitRectForAspect(HERO_CARD_ASPECT, p)
                    end
                end
            end)
            pcall(function()
                local bg = tok.portraitBackground
                if bg ~= nil and bg ~= "" then
                    frameBg = bg
                end
            end)
            --a cloud-asset GUID whose record is not loaded cannot render
            --(e.g. pregen art on an engine build that does not register the
            --module's streamed images); drop it so the silhouette shows
            --instead of an empty frame. A remote hero's art is registered
            --as session extras, which assets.allAssets does not list, so
            --artRegistered skips the check.
            if not params.artRegistered then
                if IsUnresolvableAssetId(portrait) then
                    portrait = nil
                    portraitRect = nil
                end
                if IsUnresolvableAssetId(frameBg) then
                    frameBg = nil
                end
            end
        end

        local children = {}

        --the portrait itself, inset so the frame border + corners read.
        if portrait ~= nil then
            children[#children+1] = gui.Panel{
                interactable = false,
                width = "100%-4",
                height = "100%-4",
                halign = "center",
                valign = "center",
                bgimage = portrait,
                bgcolor = "white",
                cornerRadius = 7,
                create = function(element)
                    element.selfStyle.imageRect = portraitRect
                end,
            }
        else
            --silhouette placeholder (a hero another player controls, or a
            --portrait that has not loaded).
            children[#children+1] = gui.Panel{
                interactable = false,
                width = "50%",
                height = "100% width",
                halign = "center",
                valign = "center",
                bgimage = "phosphor/user-fill.png",
                bgcolor = "#ffffff2a",
            }
        end

        if params.chipText ~= nil then
            children[#children+1] = gui.Label{
                interactable = false,
                floating = true,
                halign = "left",
                valign = "top",
                hmargin = 6,
                vmargin = 6,
                width = "auto",
                height = "auto",
                pad = 3,
                bgimage = "panels/square.png",
                bgcolor = "#000000b0",
                cornerRadius = 4,
                text = params.chipText,
                fontSize = 10,
                uppercase = true,
                color = Styles.textColor,
                opacity = 0.9,
            }
        end

        --the identity plate: name / level+ancestry+class / controlled-by,
        --over a translucent backing so the art stays visible behind it.
        local plateLines = {
            gui.Label{
                interactable = false,
                text = params.name or "Hero",
                fontSize = 15,
                bold = true,
                color = Styles.textColor,
                width = "100%",
                height = "auto",
                minFontSize = 9,
                textWrap = false,
                textAlignment = "center",
            },
        }
        if params.details ~= nil and params.details ~= "" then
            plateLines[#plateLines+1] = gui.Label{
                interactable = false,
                text = params.details,
                fontSize = 12,
                color = Styles.textColor,
                opacity = 0.9,
                width = "100%",
                height = "auto",
                minFontSize = 8,
                textWrap = false,
                textAlignment = "center",
                vmargin = 1,
            }
        end
        if params.noteText ~= nil then
            --e.g. "Already Completed": this hero won the encounter before,
            --so it earns no Victory this time.
            plateLines[#plateLines+1] = gui.Label{
                interactable = false,
                text = params.noteText,
                fontSize = 12,
                italics = true,
                color = "#9a9a9a",
                width = "100%",
                height = "auto",
                minFontSize = 8,
                textWrap = false,
                textAlignment = "center",
                vmargin = 1,
            }
        end
        if params.ownerText ~= nil then
            plateLines[#plateLines+1] = gui.Label{
                interactable = false,
                text = params.ownerText,
                fontSize = 11,
                color = Styles.textColor,
                opacity = 0.65,
                width = "100%",
                height = "auto",
                minFontSize = 8,
                textWrap = false,
                textAlignment = "center",
                vmargin = 1,
            }
        end
        children[#children+1] = gui.Panel{
            interactable = false,
            width = "100%-4",
            height = "auto",
            halign = "center",
            valign = "bottom",
            bmargin = 2,
            flow = "vertical",
            bgimage = "panels/square.png",
            bgcolor = "#000000c0",
            cornerRadius = 6,
            pad = 5,
            borderBox = true,
            children = plateLines,
        }

        for _,extra in ipairs(params.extras or {}) do
            children[#children+1] = extra
        end

        local frameImage = "panels/square.png"
        local frameColor = "#191921f0"
        if frameBg ~= nil then
            frameImage = frameBg
            frameColor = "white"
        end

        return gui.Panel{
            classes = { "heroCard", cond(params.born, "born", nil) },
            width = HERO_CARD_WIDTH,
            height = HERO_CARD_HEIGHT,
            hmargin = 5,
            vmargin = 5,
            flow = "none",
            bgimage = frameImage,
            bgcolor = frameColor,
            styles = heroCardStyles,
            data = { bornTime = 0 },
            hoverCursor = cond(params.click ~= nil, "pressbutton", nil),

            hover = function(element)
                audio.FireSoundEvent("Mouse.Hover")
            end,
            click = params.click,

            --entrance: fade/zoom via the "born" style rule, while a width
            --tween grows the card's footprint so neighbors slide apart to
            --make room (width is not style-animatable, so it is scripted).
            create = function(element)
                if not element:HasClass("born") then
                    return
                end
                element.data.bornTime = dmhub.Time()
                element.selfStyle.width = 16
                element:ScheduleEvent("growCard", 0.01)
                element:ScheduleEvent("shedBorn", 0.05)
            end,
            growCard = function(element)
                local t = (dmhub.Time() - element.data.bornTime) / HERO_CARD_GROW_TIME
                if t >= 1 then
                    element.selfStyle.width = HERO_CARD_WIDTH
                    return
                end
                local ease = 1 - (1 - t) * (1 - t)
                element.selfStyle.width = math.max(16, math.floor(HERO_CARD_WIDTH * ease))
                element:ScheduleEvent("growCard", 0.016)
            end,
            shedBorn = function(element)
                element:SetClass("born", false)
            end,

            children = children,
        }
    end

    --An encounter's backstory: the read-aloud paragraph from its script's
    --"# Town Gate" section, shown wherever a party is formed.
    local BackstoryLabel = function(text, width)
        return gui.Label{
            text = text,
            fontSize = 18,
            italics = true,
            color = "#efe4cc",
            width = width,
            height = "auto",
            halign = "center",
            textAlignment = "center",
            textWrap = true,
            vmargin = 8,
        }
    end

    --A claimed hero's card in the game lobby view. myIndex is this hero's
    --position in OUR claim list (nil for other players' heroes); it drives
    --the trash action. kickUserid is set only when the viewer is the host
    --looking at another player's hero; its action kicks that whole player
    --(and all their heroes) from the roster.
    local MakeHeroCard = function(params)
        local heroEntry = params.heroEntry
        local gameid = params.gameid
        local myIndex = params.myIndex
        local kickUserid = params.kickUserid
        local mine = myIndex ~= nil

        local tok = ResolveHeroToken(heroEntry, mine, params.ownerUserid)

        --prefer live token data; the roster record's display copies are the
        --fallback (all another player's lobby hero can offer).
        local className = heroEntry.className
        local ancestry = heroEntry.ancestry
        local level = heroEntry.level
        if tok ~= nil then
            local s = GetHeroClassName(tok)
            if s ~= "" then
                className = s
            end
            s = GetHeroAncestry(tok)
            if s ~= "" then
                ancestry = s
            end
            level = GetHeroLevel(tok) or level
        end

        local ownerText = nil
        if params.ownerName ~= nil then
            ownerText = string.format("Controlled by %s", params.ownerName)
        end

        local chipText = nil
        if heroEntry.kind == "pregen" then
            chipText = "Pregen"
        end

        local extras = {}
        if mine then
            extras[#extras+1] = gui.Panel{
                classes = { "heroCardAction" },
                floating = true,
                halign = "right",
                valign = "top",
                hmargin = 6,
                vmargin = 6,
                width = 26,
                height = 26,
                bgimage = "phosphor/trash-fill.png",
                bgcolor = "#ff9999",
                hoverCursor = "pressbutton",
                linger = function(element)
                    gui.Tooltip("Remove from the lineup")(element)
                end,
                click = function(element)
                    audio.FireSoundEvent("Mouse.Click")
                    local record = GetGameRecord(gameid)
                    if record == nil then
                        return
                    end
                    local heroes = MyHeroesCopy(record)
                    table.remove(heroes, myIndex)
                    SetHeroes(gameid, heroes)
                end,
            }
        elseif kickUserid ~= nil then
            extras[#extras+1] = gui.Panel{
                classes = { "heroCardAction" },
                floating = true,
                halign = "right",
                valign = "top",
                hmargin = 6,
                vmargin = 6,
                width = 26,
                height = 26,
                bgimage = "phosphor/user-minus-fill.png",
                bgcolor = "#ff9999",
                hoverCursor = "pressbutton",
                linger = function(element)
                    gui.Tooltip(string.format("Kick %s from the game (removes all their heroes)", params.ownerName or "this player"))(element)
                end,
                click = function(element)
                    audio.FireSoundEvent("Mouse.Click")
                    if m_conn == nil then
                        return
                    end
                    m_conn:Request{
                        action = "kick-player",
                        args = { gameid = gameid, userid = kickUserid },
                        error = ShowGamesError,
                    }
                end,
            }
        end

        return MakeCardPanel{
            tok = tok,
            name = heroEntry.name,
            details = FormatHeroDetails(level, ancestry, className),
            noteText = cond(heroEntry.completed == true, "Already Completed", nil),
            ownerText = ownerText,
            chipText = chipText,
            born = params.born,
            extras = extras,
            --another player's roster hero: CreateDetachedCharacter registered its art.
            artRegistered = not mine and heroEntry.kind == "roster",
        }
    end

    --The "+" card at the end of the lineup. Hidden entirely once the game
    --is full (MAX_HEROES); shown dimmed when only OUR per-player cap (4) is
    --the blocker, so the affordance stays discoverable.
    local MakeAddHeroCard = function(gameid, enabled)
        return gui.Panel{
            classes = { "heroCard" },
            width = HERO_CARD_WIDTH,
            height = HERO_CARD_HEIGHT,
            hmargin = 5,
            vmargin = 5,
            flow = "vertical",
            bgimage = "panels/square.png",
            bgcolor = "#ffffff08",
            styles = heroCardStyles,
            hoverCursor = "pressbutton",

            hover = function(element)
                audio.FireSoundEvent("Mouse.Hover")
            end,
            linger = function(element)
                if not enabled then
                    gui.Tooltip("You can claim up to 4 heroes. Other players can add more.")(element)
                end
            end,
            click = function(element)
                audio.FireSoundEvent("Mouse.Click")
                if not enabled then
                    ShowGamesError("You can claim at most 4 heroes. Other players can add more.")
                    return
                end
                if ShowAddHeroDialog ~= nil then
                    ShowAddHeroDialog(gameid)
                end
            end,

            gui.Panel{
                interactable = false,
                bgimage = "ui-icons/Plus.png",
                bgcolor = "white",
                width = 72,
                height = 72,
                halign = "center",
                valign = "center",
                vmargin = 54,
                opacity = cond(enabled, 1, 0.4),
                styles = {
                    {
                        brightness = 0.8,
                    },
                    {
                        selectors = { "parent:hover" },
                        scale = 1.1,
                        brightness = 1,
                        transitionTime = 0.1,
                    },
                },
            },
            gui.Label{
                interactable = false,
                text = "Add Hero",
                fontSize = 17,
                color = Styles.textColor,
                opacity = cond(enabled, 0.8, 0.4),
                width = "100%",
                height = "auto",
                halign = "center",
                textAlignment = "center",
            },
        }
    end

    --The whole game lobby view, as a child list for gamesListPanel.
    BuildGameView = function(gameid, record)
        local myUserid = dmhub.loginUserid
        local isHost = record.hostUserid == myUserid
        local isMember = isHost or (record.players ~= nil and record.players[myUserid] ~= nil)
        local isOpen = record.status == "open"
        local slotsTotal = math.min(record.slotsTotal or MAX_HEROES, MAX_HEROES)
        local slotsFilled = record.slotsFilled or 0
        local myHeroes = MyHeroesCopy(record)

        local children = {}

        --header: game name, host, privacy, membership summary.
        local tagText = ""
        if record.public ~= true then
            tagText = "  (private)"
        end
        if not isOpen then
            tagText = tagText .. "  (launched)"
        end
        children[#children+1] = gui.Label{
            text = string.format("%s%s", record.name or gameid, tagText),
            fontSize = 28,
            bold = true,
            color = Styles.textColor,
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
        }

        local memberNames = {}
        if record.players ~= nil then
            for _,player in pairs(record.players) do
                memberNames[#memberNames+1] = player.name or "?"
            end
        end
        table.sort(memberNames)
        children[#children+1] = gui.Label{
            text = string.format("Hosted by %s -- players: %s%s", record.hostName or "?", cond(#memberNames > 0, table.concat(memberNames, ", "), "none yet"), EncounterSuffix(record)),
            fontSize = 18,
            color = Styles.textColor,
            opacity = 0.8,
            width = "96%",
            height = "auto",
            halign = "center",
        }

        --what the heroes are setting out to do (the script's "# Town Gate").
        local backstory = EncounterOfTheWeek.GetTownGateText(record.encounter)
        if backstory ~= nil then
            children[#children+1] = BackstoryLabel(backstory, "86%")
        end

        --slot list: every claimed hero (host's first), then open slots.
        children[#children+1] = gui.Label{
            text = string.format("Hero Slots (%d/%d filled; %d needed to begin)", slotsFilled, slotsTotal, MIN_HEROES),
            fontSize = 22,
            bold = true,
            color = Styles.textColor,
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 8,
        }

        local playerIds = {}
        if record.players ~= nil then
            for userid,_ in pairs(record.players) do
                if userid ~= record.hostUserid then
                    playerIds[#playerIds+1] = userid
                end
            end
            table.sort(playerIds)
            if record.players[record.hostUserid] ~= nil then
                table.insert(playerIds, 1, record.hostUserid)
            end
        end

        --the card lineup: every claimed hero (host's players first), then
        --the "+" card. Heroes not present in the previous build of this
        --view are NEW and play the entrance animation; the tracker is nil
        --right after the view opens so the initial roster renders quietly.
        local knownBefore = m_knownHeroCards
        local knownNow = {}
        local cards = {}
        local myIndexCounter = 0
        for _,userid in ipairs(playerIds) do
            local player = record.players[userid]
            local mine = userid == myUserid
            --the host may kick any OTHER player (removing all their heroes).
            local kickUserid = nil
            if isHost and not mine then
                kickUserid = userid
            end
            for _,heroEntry in ipairs(player.heroes or {}) do
                local myIndex = nil
                if mine then
                    myIndexCounter = myIndexCounter + 1
                    myIndex = myIndexCounter
                end
                local key = string.format("%s|%s|%s", userid, heroEntry.kind or "", heroEntry.id or "")
                knownNow[key] = true
                cards[#cards+1] = MakeHeroCard{
                    gameid = gameid,
                    heroEntry = heroEntry,
                    ownerName = player.name,
                    ownerUserid = userid,
                    myIndex = myIndex,
                    kickUserid = kickUserid,
                    born = knownBefore ~= nil and not knownBefore[key],
                }
            end
        end
        m_knownHeroCards = knownNow

        --the "+" card: only while more heroes can join the game at all (it
        --disappears at 7/7); dimmed when only our per-player cap blocks us.
        if isMember and isOpen and slotsFilled < slotsTotal then
            cards[#cards+1] = MakeAddHeroCard(gameid, #myHeroes < 4)
        end

        children[#children+1] = gui.Panel{
            width = "96%",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            wrap = true,
            vmargin = 6,
            children = cards,
        }

        --members who joined but claimed no heroes yet fill no slot row,
        --so list them separately -- the host must still be able to see
        --and kick them.
        for _,userid in ipairs(playerIds) do
            local player = record.players[userid]
            if #(player.heroes or {}) == 0 then
                local kickButton = nil
                if isHost and userid ~= myUserid then
                    kickButton = gui.Button{
                        text = "Kick",
                        fontSize = 16,
                        width = 100,
                        height = 32,
                        halign = "right",
                        valign = "center",
                        click = function()
                            if m_conn == nil then
                                return
                            end
                            m_conn:Request{
                                action = "kick-player",
                                args = { gameid = gameid, userid = userid },
                                error = ShowGamesError,
                            }
                        end,
                    }
                end
                children[#children+1] = gui.Panel{
                    width = "96%",
                    height = 44,
                    halign = "center",
                    flow = "horizontal",
                    bgimage = "panels/square.png",
                    bgcolor = "#ffffff08",
                    hpad = 8,
                    borderBox = true,
                    vmargin = 2,

                    gui.Label{
                        text = string.format("%s -- no heroes yet", player.name or "?"),
                        fontSize = 18,
                        color = Styles.textColor,
                        opacity = 0.6,
                        width = "60%",
                        height = "auto",
                        halign = "left",
                        valign = "center",
                    },
                    kickButton,
                }
            end
        end

        --while the host is inside the game running setup (module install,
        --hero placement, encounter spawn), waiting members see why nothing
        --is happening yet; they enter automatically once the record flips
        --to "ready" (CheckLaunchedGames).
        if record.status == "launched" and not isHost then
            children[#children+1] = gui.Label{
                text = "The game is starting: the host is setting up the encounter. You will enter automatically when it is ready...",
                fontSize = 18,
                color = Styles.textColor,
                width = "90%",
                height = "auto",
                halign = "center",
                textAlignment = "center",
                vmargin = 10,
            }
        elseif record.status == "ready" and isMember and m_enteringWorld then
            children[#children+1] = gui.Label{
                text = "Entering the game...",
                fontSize = 18,
                color = Styles.textColor,
                width = "90%",
                height = "auto",
                halign = "center",
                textAlignment = "center",
                vmargin = 10,
            }
        end

        --controls. (Adding heroes is the "+" card in the lineup above.)
        local buttons = {}
        if not isMember and isOpen and (record.public == true or isHost) then
            buttons[#buttons+1] = gui.Button{
                text = "Join Game",
                fontSize = 20,
                width = 160,
                height = 44,
                hmargin = 6,
                click = function()
                    JoinGame(gameid)
                end,
            }
        end
        --Begin: host-only. Enabled at MIN_HEROES..slotsTotal filled slots
        --(the server re-checks both bounds).
        --A granted launch flips the roster record to "launched": the HOST
        --enters via CheckLaunchedGames and runs setup in-game; members
        --wait for the game-side "ready-game" signal to flip the record to
        --"ready" before entering (see CheckLaunchedGames).
        if isHost and isOpen then
            local canBegin = slotsFilled >= MIN_HEROES and slotsFilled <= slotsTotal
            buttons[#buttons+1] = gui.Button{
                text = "Begin",
                fontSize = 20,
                width = 160,
                height = 44,
                hmargin = 6,
                opacity = cond(canBegin, 1, 0.45),
                click = function()
                    if not canBegin then
                        if slotsFilled > slotsTotal then
                            ShowGamesError(string.format("At most %d heroes can begin (%d filled).", slotsTotal, slotsFilled))
                        else
                            ShowGamesError(string.format("Need at least %d heroes to begin (%d/%d filled).", MIN_HEROES, slotsFilled, slotsTotal))
                        end
                        return
                    end
                    if m_conn == nil then
                        return
                    end
                    m_conn:Request{
                        action = "launch-game",
                        args = { gameid = gameid },
                        error = ShowGamesError,
                    }
                end,
            }
        end
        --Re-join a game already in progress: any member once it is "ready",
        --or the host while it is still "launched" (their re-entry re-runs
        --the setup, which is re-entry safe). This is the manual path back
        --in -- auto-entry only fires on status transitions this screen saw.
        if isMember and (record.status == "ready" or (record.status == "launched" and isHost)) then
            buttons[#buttons+1] = gui.Button{
                text = "Re-join",
                fontSize = 20,
                width = 160,
                height = 44,
                hmargin = 6,
                click = function()
                    if not m_enteringWorld then
                        m_enteringWorld = true
                        EnterWorld(gameid)
                    end
                end,
            }
        end
        if isMember then
            --The host's Abandon destroys the game outright (roster record
            --dropped, engine game deleted + storage released, account slot
            --cleared), so it asks for a second click to confirm. A
            --non-host's Leave just gives up their membership.
            buttons[#buttons+1] = gui.Button{
                text = cond(isHost, "Abandon", "Leave"),
                fontSize = 20,
                width = 160,
                height = 44,
                hmargin = 6,
                data = { confirming = false },
                resetConfirm = function(element)
                    element.data.confirming = false
                    element.text = "Abandon"
                end,
                click = function(element)
                    if isHost then
                        if not element.data.confirming then
                            element.data.confirming = true
                            element.text = "Really?"
                            element:ScheduleEvent("resetConfirm", 4)
                            return
                        end
                        DestroyPreviousGame(gameid)
                        if CloseGameView ~= nil then
                            CloseGameView()
                        end
                        return
                    end
                    if m_conn ~= nil then
                        m_conn:Request{
                            action = "leave-game",
                            args = { gameid = gameid },
                            success = function()
                                if CloseGameView ~= nil then
                                    CloseGameView()
                                end
                            end,
                            error = ShowGamesError,
                        }
                    end
                end,
            }
        end

        --Pinned to the bottom of the list panel: a trailing run of
        --valign="bottom" children is packed against the bottom edge, so
        --the control row sits in a fixed place no matter how many slot
        --rows are above it. If the roster ever overflows the panel the
        --engine falls back to normal flow and the row scrolls with it.
        children[#children+1] = gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "bottom",
            flow = "horizontal",
            vmargin = 12,
            children = buttons,
        }

        return children
    end

    --Row offering to resume the account's in-progress EotW game (shown at
    --the top of the games list when the slot's game still exists and has
    --no live roster record of its own).
    local MakeResumeRow = function()
        local name = "Your game"
        if m_resumeInfo ~= nil and m_resumeInfo.description ~= nil then
            name = m_resumeInfo.description
        end
        local resumeGameid = m_resumeGameid
        --forward-declared so the Abandon click can remove the row itself
        --(RefreshGames is declared later in the file and not in scope here).
        local rowPanel
        rowPanel = gui.Panel{
            width = "100%",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "#334422aa",
            cornerRadius = 8,
            pad = 10,
            borderBox = true,
            vmargin = 4,

            gui.Panel{
                width = "100%-300",
                height = "auto",
                halign = "left",
                valign = "center",
                flow = "vertical",
                gui.Label{
                    text = "Your game in progress",
                    fontSize = 16,
                    color = Styles.textColor,
                    opacity = 0.7,
                    width = "100%",
                    height = "auto",
                },
                gui.Label{
                    text = name,
                    fontSize = 22,
                    bold = true,
                    color = Styles.textColor,
                    width = "100%",
                    height = "auto",
                },
            },

            RowButton("Resume", function()
                EnterWorld(resumeGameid)
            end),

            --Abandon destroys the in-progress game (engine game deleted,
            --storage released, account slot cleared); second click confirms.
            gui.Button{
                text = "Abandon",
                fontSize = 20,
                width = 130,
                height = 40,
                halign = "right",
                valign = "center",
                hmargin = 4,
                data = { confirming = false },
                resetConfirm = function(element)
                    element.data.confirming = false
                    element.text = "Abandon"
                end,
                click = function(element)
                    if not element.data.confirming then
                        element.data.confirming = true
                        element.text = "Really?"
                        element:ScheduleEvent("resetConfirm", 4)
                        return
                    end
                    DestroyPreviousGame(resumeGameid)
                    if rowPanel ~= nil and rowPanel.valid then
                        rowPanel:DestroySelf()
                    end
                end,
            },
        }
        return rowPanel
    end

    RefreshGames = function()
        if gamesListPanel == nil or not gamesListPanel.valid then
            return
        end
        if m_conn == nil then
            gamesListPanel.children = { EmptyNote("This build of the Codex does not include the lobby engine update.") }
            return
        end

        --a launched game we belong to pulls us into the world; the list
        --still re-renders below while the game switch spins up.
        CheckLaunchedGames()

        --game lobby view mode: render the viewed game, falling back to
        --the list if it vanished (abandoned, expired, or we left it).
        if m_viewGameid ~= nil then
            local record = GetGameRecord(m_viewGameid)
            if record == nil then
                m_viewGameid = nil
                ShowGamesError("That game is no longer available.")
                RefreshChat()
            else
                SetGateCardWidth(GATE_CARD_WIDTH_PARTY)
                gamesListPanel.children = BuildGameView(m_viewGameid, record)
                if gamesTitleLabel ~= nil and gamesTitleLabel.valid then
                    gamesTitleLabel.text = "Your Party"
                end
                --no back button here: leaving the game (Abandon/Leave) is
                --the only way back to the games list. The collapsed button
                --frees its space to the list so a full 6-slot roster plus
                --the control row fits without a scrollbar.
                if createGameButton ~= nil and createGameButton.valid then
                    createGameButton:SetClass("collapsed", true)
                end
                return
            end
        end

        SetGateCardWidth(GATE_CARD_WIDTH_LIST)
        if gamesTitleLabel ~= nil and gamesTitleLabel.valid then
            gamesTitleLabel.text = "Adventuring Parties"
        end
        if createGameButton ~= nil and createGameButton.valid then
            createGameButton:SetClass("collapsed", false)
        end

        local games = m_conn:GetPath("/state/games")
        local ids = {}
        if games ~= nil then
            for gameid,_ in pairs(games) do
                ids[#ids+1] = gameid
            end
        end
        table.sort(ids)

        local children = {}
        --the account's in-progress game first, unless it also has a live
        --roster record below (then the richer roster row covers it).
        if m_resumeGameid ~= nil and (games == nil or games[m_resumeGameid] == nil) then
            children[#children+1] = MakeResumeRow()
        end
        --parties still forming up (joinable) first, then the encounters
        --already underway (shown for information).
        local forming = {}
        local underway = {}
        for _,gameid in ipairs(ids) do
            --ids is empty unless games is non-nil.
            ---@cast games -nil
            local record = games[gameid]
            --private games are never listed for anyone but their host.
            if record.public == true or record.hostUserid == dmhub.loginUserid then
                if record.status == "open" then
                    forming[#forming+1] = MakeGameRow(gameid, record)
                else
                    underway[#underway+1] = MakeGameRow(gameid, record)
                end
            end
        end

        children[#children+1] = ListSectionTitle("Parties Forming")
        if #forming == 0 then
            children[#children+1] = EmptyNote("No parties are forming right now. Form one and others can join you!")
        end
        for _,row in ipairs(forming) do
            children[#children+1] = row
        end
        if #underway > 0 then
            children[#children+1] = ListSectionTitle("Encounters Underway")
            for _,row in ipairs(underway) do
                children[#children+1] = row
            end
        end
        gamesListPanel.children = children
    end

    --Look up the account's EotW slot: a still-existing game becomes the
    --resume row; a deleted/missing one clears the slot. Async -- the games
    --list re-renders when the lookup lands.
    RefreshResumeState = function()
        --a game the game-side codemod marked finished (encounter decided,
        --players auto-exited) gets destroyed instead of offered for resume:
        --the host's machine deletes it and releases its storage, a member's
        --machine leaves it -- both clear the account slot and drop any
        --lingering lobby roster record.
        local concluded = dmhub.GetSettingValue("eotw:concludedgame")
        if concluded ~= nil and concluded ~= "" then
            dmhub.SetSettingValue("eotw:concludedgame", "")
            printf("EotW: cleaning up finished game %s", concluded)
            DestroyPreviousGame(concluded)
            if EotwSlotGameid() == concluded then
                m_resumeGameid = nil
                m_resumeInfo = nil
                return
            end
        end

        local gameid = EotwSlotGameid()
        if gameid == nil then
            m_resumeGameid = nil
            m_resumeInfo = nil
            return
        end
        lobby:LookupGame(gameid, function(gameinfo)
            if gameinfo == nil or gameinfo.deleted then
                if lobby.ClearEotwGame ~= nil then
                    lobby:ClearEotwGame(gameid)
                end
                m_resumeGameid = nil
                m_resumeInfo = nil
            else
                m_resumeGameid = gameid
                m_resumeInfo = gameinfo
            end
            RefreshGames()
        end)
    end

    local RefreshPresence = function()
        if presenceLabel == nil or not presenceLabel.valid or m_conn == nil then
            return
        end
        local presence = m_conn:GetPath("/presence")
        local names = {}
        if presence ~= nil then
            for _,entry in pairs(presence) do
                names[#names+1] = entry.name or "?"
            end
        end
        table.sort(names)
        if #names == 0 then
            presenceLabel.text = "Nobody is here yet."
        else
            presenceLabel.text = string.format("Here now (%d): %s", #names, table.concat(names, ", "))
        end
    end

    RefreshChat = function()
        if chatMessagesPanel == nil or not chatMessagesPanel.valid then
            return
        end
        if m_conn == nil then
            chatMessagesPanel.children = { EmptyNote("Chat requires the lobby engine update.") }
            return
        end

        --in a game lobby view the chat column shows that game's private
        --channel; otherwise the lobby-wide chat.
        local chat
        if m_viewGameid ~= nil then
            chat = m_conn:GetPath("/gamechat/" .. m_viewGameid)
            if chatTitleLabel ~= nil and chatTitleLabel.valid then
                chatTitleLabel.text = "Game Chat"
            end
        else
            chat = m_conn:GetPath("/chat")
            if chatTitleLabel ~= nil and chatTitleLabel.valid then
                chatTitleLabel.text = "Lobby Chat"
            end
        end
        local ids = {}
        if chat ~= nil then
            for msgid,_ in pairs(chat) do
                ids[#ids+1] = msgid
            end
        end
        --msgids sort chronologically; show newest first so the latest
        --message is always visible without scroll-position management.
        table.sort(ids, function(a,b) return a > b end)

        local children = {}
        for _,msgid in ipairs(ids) do
            --ids is empty unless chat is non-nil.
            ---@cast chat -nil
            local msg = chat[msgid]
            children[#children+1] = gui.Label{
                text = string.format("<b>%s:</b> %s", msg.name or "?", msg.text or ""),
                fontSize = 18,
                color = Styles.textColor,
                width = "96%",
                height = "auto",
                halign = "left",
                vmargin = 2,
            }
        end
        chatMessagesPanel.children = children
    end

    local RefreshStatus = function()
        if statusLabel == nil or not statusLabel.valid then
            return
        end
        if m_conn == nil then
            statusLabel.text = "Engine update required"
            return
        end
        local status = m_conn.status
        if status == "connected" then
            statusLabel.text = ""
        elseif status == "closed" then
            statusLabel.text = "Disconnected from the lobby."
        else
            statusLabel.text = "Connecting to the lobby..."
        end
    end

    local RefreshAll = function()
        RefreshGames()
        RefreshPresence()
        RefreshChat()
        RefreshStatus()
    end

    OpenGameView = function(gameid)
        m_viewGameid = gameid
        m_knownHeroCards = nil
        RefreshGames()
        RefreshChat()
    end

    CloseGameView = function()
        m_viewGameid = nil
        m_knownHeroCards = nil
        RefreshGames()
        RefreshChat()
    end

    --── add-hero picker ─────────────────────────────────────────────────
    --Fills one of our (up to 4) slots with a hero: either one of the
    --local titlescreen heroes, or a pregen from the weekly module.

    ShowAddHeroDialog = function(gameid)
        if m_conn == nil or resultPanel == nil or not resultPanel.valid then
            return
        end
        if m_modalDialog ~= nil and m_modalDialog.valid then
            return
        end
        local record = GetGameRecord(gameid)
        if record == nil then
            return
        end

        --assigned below, before any of its click handlers can fire.
        ---@type Panel
        local dlg = nil

        --ids we have already claimed, so the lists offer each hero once.
        local claimed = {}
        for _,h in ipairs(MyHeroesCopy(record)) do
            claimed[h.id] = true
        end

        local AddHero = function(spec)
            local freshRecord = GetGameRecord(gameid)
            if freshRecord == nil then
                return
            end
            local heroes = MyHeroesCopy(freshRecord)
            if #heroes >= 4 then
                return
            end
            heroes[#heroes+1] = spec
            SetHeroes(gameid, heroes)
            if dlg ~= nil and dlg.valid then
                dlg:DestroySelf()
            end
        end

        local SectionTitle = function(text)
            return gui.Label{
                text = text,
                fontSize = 24,
                bold = true,
                color = Styles.textColor,
                width = "94%",
                height = "auto",
                halign = "center",
                vmargin = 8,
            }
        end

        --One selectable hero card in the grid: the shared card body with a
        --click that claims the hero. spec carries the display copies that
        --ride to the server in set-heroes; tok drives the portrait art.
        local PickerCard = function(spec, tok, noteText)
            local chipText = nil
            if spec.kind == "pregen" then
                chipText = "Pregen"
            end
            return MakeCardPanel{
                tok = tok,
                name = spec.name,
                details = FormatHeroDetails(spec.level, spec.ancestry, spec.className),
                noteText = noteText,
                chipText = chipText,
                click = function()
                    audio.FireSoundEvent("Mouse.Click")
                    AddHero(spec)
                end,
            }
        end

        --a wrapping grid holding one section's cards.
        local CardGrid = function(cards)
            return gui.Panel{
                width = "98%",
                height = "auto",
                halign = "center",
                flow = "horizontal",
                wrap = true,
                children = cards,
            }
        end

        local rows = {}

        --the heroes of our town roster (EotwRoster): every living hero not
        --already in this party or away with another one. The city checks
        --the same rules when the party changes.
        rows[#rows+1] = SectionTitle("Your Heroes")
        local away = EotwRoster.AwayHeroes()
        local active = {}
        for _,hero in ipairs(EotwRoster.ActiveHeroes()) do
            active[hero.heroid] = true
        end
        local heroes = {}
        for _,hero in ipairs(EotwRoster.GetHeroes() or {}) do
            if not claimed[hero.heroid] and away[hero.heroid] == nil then
                heroes[#heroes+1] = hero
            end
        end
        --active heroes first: they are the ones adventuring in town.
        table.sort(heroes, function(x, y)
            if (active[x.heroid] == true) ~= (active[y.heroid] == true) then
                return active[x.heroid] == true
            end
            return (x.summary.name or "") < (y.summary.name or "")
        end)
        local myCards = {}
        for _,hero in ipairs(heroes) do
            local spec, tok = RosterHeroSpec(hero)
            local noteText = nil
            if EotwRoster.HasCompleted(hero, record.encounter ~= "" and record.encounter or ENCOUNTER_MAP_NAME) then
                noteText = "Already Completed"
            end
            myCards[#myCards+1] = PickerCard(spec, tok, noteText)
        end
        if #myCards == 0 then
            rows[#rows+1] = EmptyNote("No heroes are free to join. Visit the Hero's Guild to create or recruit one.")
        else
            rows[#rows+1] = CardGrid(myCards)
        end

        dlg = gui.Panel{
            floating = true,
            width = 1040,
            height = 740,
            halign = "center",
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = "#111111ff",
            borderWidth = 2,
            borderColor = Styles.textColor,
            flow = "vertical",
            styles = { Styles.Default },

            captureEscape = true,
            --above the town's own escape (see the screen below).
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            escape = function(element)
                element:DestroySelf()
            end,

            gui.Label{
                text = "Add a Hero",
                fontSize = 32,
                bold = true,
                color = Styles.textColor,
                width = "auto",
                height = "auto",
                halign = "center",
                vmargin = 12,
            },

            gui.Panel{
                width = "94%",
                height = "100%-140",
                halign = "center",
                flow = "vertical",
                vscroll = true,
                rpad = 12,
                borderBox = true,
                children = rows,
            },

            gui.Button{
                text = "Cancel",
                fontSize = 20,
                width = 160,
                height = 44,
                halign = "center",
                valign = "bottom",
                vmargin = 12,
                click = function()
                    dlg:DestroySelf()
                end,
            },
        }

        m_modalDialog = dlg
        resultPanel:AddChild(dlg)
    end

    --── create-game dialog ──────────────────────────────────────────────
    --The two-layer create flow: reserve with the lobby (one hosted game per
    --user, arbitrated server-side), create the real DMHub game through the
    --engine, then confirm the gameid so the lobby publishes the roster
    --record, and claim the host's first hero slot.

    ShowCreateDialog = function()
        if m_conn == nil or resultPanel == nil or not resultPanel.valid then
            return
        end
        if m_modalDialog ~= nil and m_modalDialog.valid then
            return
        end

        local m_public = true
        local m_busy = false
        ---@type Input
        local nameInput = nil
        local dialogStatusLabel = nil
        --assigned below, before any of its click handlers can fire.
        ---@type Panel
        local dlg = nil

        --the encounter pool (see "the encounter pool" above). With more than
        --one encounter the dialog shows a dropdown, defaulting to the official
        --module's bare "Encounter" map when it exists (else the first). With
        --just one there is nothing to choose, but the party still records its
        --key (the town keys who has already won an encounter by it). With none
        --(or the pool not loaded yet) the game plays the official default map.
        --m_encounter is an encounter KEY.
        local encounters = EncounterOfTheWeek.GetEncounters() or {}
        local m_encounter = nil
        local showEncounterChoice = #encounters > 1
        if #encounters > 0 then
            m_encounter = encounters[1].key
            for _,entry in ipairs(encounters) do
                if entry.official and entry.mapName == ENCOUNTER_MAP_NAME then
                    m_encounter = entry.key
                end
            end
        end

        --the chosen encounter's backstory, under the choice, and for a
        --community encounter the module it comes from and its author.
        local backstoryLabel = BackstoryLabel("", 480)
        local creditLabel = gui.Label{
            text = "",
            fontSize = 15,
            color = "#b8ad96",
            width = 480,
            height = "auto",
            halign = "center",
            textAlignment = "center",
            textWrap = true,
            vmargin = 2,
        }
        local ShowBackstory = function()
            local text = EncounterOfTheWeek.GetTownGateText(m_encounter)
            backstoryLabel.text = text or ""
            backstoryLabel:SetClass("collapsed", text == nil)

            local entry = EncounterOfTheWeek.GetEncounter(m_encounter)
            local credit = nil
            if entry ~= nil and not entry.official then
                credit = string.format("From the module %s", entry.moduleName or entry.moduleid)
                if entry.author ~= nil and entry.author ~= "" then
                    credit = credit .. " by " .. entry.author
                end
            end
            creditLabel.text = credit or ""
            creditLabel:SetClass("collapsed", credit == nil)
        end
        ShowBackstory()

        --default the game name to the creator's name ("David's Game"),
        --prefilled so it can be edited or cleared.
        local defaultName = "Encounter of the Week"
        local myName = dmhub.GetDisplayName(dmhub.loginUserid)
        if myName ~= nil and myName ~= "" then
            defaultName = myName .. "'s Party"
        end

        local SetDialogStatus = function(message, isError)
            if dialogStatusLabel ~= nil and dialogStatusLabel.valid then
                dialogStatusLabel.text = message or ""
                dialogStatusLabel.selfStyle.color = cond(isError, "#ff8888", Styles.textColor)
            end
        end

        local DoCreate = function()
            if m_busy or m_conn == nil then
                return
            end
            local name = (nameInput.text or ""):match("^%s*(.-)%s*$")
            if name == "" then
                name = defaultName
            end
            m_busy = true
            SetDialogStatus("Reserving your game...")

            m_conn:Request{
                action = "create-game",
                args = { name = name, public = m_public, encounter = m_encounter },
                success = function()
                    SetDialogStatus("Creating the game...")
                    --one EotW game per account: capture the current slot
                    --value now -- creating the new game overwrites it --
                    --and destroy that game once the new one exists.
                    local prev = EotwSlotGameid()
                    lobby:CreateGame{
                        description = name,
                        coverart = LOADING_SCREEN_ART,
                        startingModule = STARTING_MODULE,
                        backend = GAME_BACKEND,
                        accountSlot = "eotw",
                        --Every EotW game is directorless: the host's machine
                        --hosts, but the host plays as a player. Recorded on the
                        --game itself, so every client agrees and every entry
                        --(create, join, resume) is already in the mode -- no
                        --in-session switch and so no reload. Ignored by engine
                        --builds without the flag, which fall back to the
                        --in-game Director-UI filter.
                        directorless = true,
                        create = function(gameid)
                            if prev ~= nil and prev ~= gameid then
                                DestroyPreviousGame(prev)
                            end
                            --Confirm even if the dialog was closed meanwhile:
                            --the engine game now exists, and only a confirm
                            --gets it listed (otherwise the reservation just
                            --expires and the game sits unlisted).
                            if m_conn == nil then
                                return
                            end
                            m_conn:Request{
                                action = "confirm-game",
                                args = { gameid = gameid },
                                success = function()
                                    if m_conn ~= nil then
                                        m_conn:Request{
                                            action = "join-game",
                                            args = { gameid = gameid },
                                            success = function()
                                                ClaimActiveHeroes(gameid, prev)
                                                --straight into the new game's
                                                --lobby view to pick heroes.
                                                if OpenGameView ~= nil then
                                                    OpenGameView(gameid)
                                                end
                                            end,
                                            error = ShowGamesError,
                                        }
                                    end
                                    if dlg ~= nil and dlg.valid then
                                        dlg:DestroySelf()
                                    end
                                end,
                                error = function(message)
                                    m_busy = false
                                    SetDialogStatus("Could not list the game: " .. tostring(message), true)
                                end,
                            }
                        end,
                        error = function(message)
                            m_busy = false
                            if message == nil or message == "" then
                                message = "The game could not be created. Please try again."
                            end
                            SetDialogStatus(message, true)
                        end,
                    }
                end,
                error = function(message)
                    m_busy = false
                    SetDialogStatus(message, true)
                end,
            }
        end

        --official encounters at the top level, then one flyout per community
        --module ("<module> by <author>") holding its encounters. The pool
        --lists each module's entries together, so a change of moduleid
        --starts a new flyout.
        local encounterOptions = {}
        local currentGroup = nil
        for _,entry in ipairs(encounters) do
            if entry.official then
                encounterOptions[#encounterOptions+1] = { id = entry.key, text = entry.mapName }
            else
                if currentGroup == nil or currentGroup.moduleid ~= entry.moduleid then
                    local groupText = entry.moduleName or entry.moduleid
                    if entry.author ~= nil and entry.author ~= "" then
                        groupText = string.format("%s by %s", groupText, entry.author)
                    end
                    currentGroup = { moduleid = entry.moduleid, id = "module:" .. entry.moduleid, text = groupText, submenu = {} }
                    encounterOptions[#encounterOptions+1] = currentGroup
                end
                currentGroup.submenu[#currentGroup.submenu+1] = {
                    id = entry.key,
                    text = entry.title,
                    tooltip = entry.townGate,
                }
            end
        end

        dlg = gui.Panel{
            floating = true,
            width = 560,
            height = "auto",
            halign = "center",
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = "#111111ff",
            borderWidth = 2,
            borderColor = Styles.textColor,
            flow = "vertical",
            styles = { Styles.Default },

            captureEscape = true,
            --above the town's own escape (see the screen below).
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            escape = function(element)
                element:DestroySelf()
            end,

            gui.Label{
                text = "Form a Party",
                fontSize = 32,
                bold = true,
                color = Styles.textColor,
                width = "auto",
                height = "auto",
                halign = "center",
                vmargin = 16,
            },

            gui.Input{
                width = 460,
                height = 36,
                halign = "center",
                vmargin = 8,
                fontSize = 20,
                characterLimit = 80,
                placeholderText = "Name your party...",
                create = function(element)
                    ---@cast element Input
                    nameInput = element
                    element.text = defaultName
                end,
            },

            --which of the week's encounters to play; only when there is a choice.
            gui.Panel{
                classes = { cond(not showEncounterChoice, "collapsed", nil) },
                width = 460,
                height = "auto",
                halign = "center",
                vmargin = 8,
                flow = "horizontal",

                gui.Label{
                    text = "Encounter:",
                    fontSize = 20,
                    color = Styles.textColor,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    hmargin = 8,
                },
                gui.Dropdown{
                    width = 340,
                    height = 36,
                    fontSize = 18,
                    valign = "center",
                    --The open list (dropdownBorder/dropdownMenu/dropdownOption)
                    --carries no styles of its own: it inherits the host's
                    --cascade (popupsInheritStyles), and its rules live only
                    --in the themed sheet. The titlescreen's legacy
                    --Styles.Default styles the closed control but not the
                    --list, so it rendered as bare labels over the dialog.
                    --Same trap as g_CheckboxStyles above; scoped to the
                    --dropdown so the rest of the dialog keeps its look.
                    styles = ThemeEngine.GetStyles(),
                    options = encounterOptions,
                    idChosen = m_encounter or ENCOUNTER_MAP_NAME,
                    change = function(element)
                        ---@cast element Dropdown
                        m_encounter = element.idChosen
                        ShowBackstory()
                    end,
                },
            },

            creditLabel,
            backstoryLabel,

            gui.Check{
                text = "Public party (anyone can join)",
                value = true,
                fontSize = 20,
                styles = g_CheckboxStyles,
                halign = "center",
                vmargin = 8,
                change = function(element)
                    m_public = element.value
                end,
            },

            gui.Label{
                text = "",
                fontSize = 18,
                color = Styles.textColor,
                width = 460,
                height = "auto",
                minHeight = 24,
                halign = "center",
                textAlignment = "center",
                vmargin = 8,
                create = function(element)
                    dialogStatusLabel = element
                    --pre-flight notice: one EotW game per account, so
                    --creating a new one destroys the current one.
                    if EotwSlotGameid() ~= nil then
                        element.text = "Creating a new game will permanently delete your current Encounter of the Week game."
                        element.selfStyle.color = "#ffcc66"
                    end
                end,
            },

            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "bottom",
                vmargin = 16,
                flow = "horizontal",

                gui.Button{
                    text = "Create",
                    fontSize = 22,
                    width = 160,
                    height = 46,
                    hmargin = 8,
                    click = function(element)
                        DoCreate()
                    end,
                },
                gui.Button{
                    text = "Cancel",
                    fontSize = 22,
                    width = 160,
                    height = 46,
                    hmargin = 8,
                    click = function(element)
                        dlg:DestroySelf()
                    end,
                },
            },
        }

        m_modalDialog = dlg
        resultPanel:AddChild(dlg)
    end

    --── the town ──────────────────────────────────────────────────────────

    --The map covers the screen (it is wider than tall but not as wide as
    --16:9) and pans by dragging. Everything on it -- the location nodes --
    --is a child of the map panel, so it moves with it.
    local mapW = math.max(panelWidth, panelHeight * CITY_MAP_ASPECT)
    local mapH = mapW / CITY_MAP_ASPECT
    --start with the town gate and the guild in view.
    local m_panX = (mapW - panelWidth) / 2
    local m_panY = 0
    local m_dragStartX = 0
    local m_dragStartY = 0
    local mapPanel = nil
    local nodeLayer = nil
    --- @type Panel
    local gatePanel = nil
    --- @type Panel
    local chatPanel = nil

    --The location open full screen over the map ("guild", "gate"), or nil
    --on the map. The town's own furniture (map, plaque, hero strip) hides
    --while one is open. The Gate's scene is built once and kept, because its
    --games list must stay live (RefreshGames is what notices a launched
    --game and takes us into it); the Guild's is built on each visit.
    local m_locationId = nil
    local m_guildScene = nil
    local gateScene = nil
    local locationHost = nil
    local townViewport = nil
    local townPlaque = nil
    local chatButton = nil
    ---@type fun(id: string)
    local OpenLocation = nil
    ---@type fun()
    local CloseLocation = nil

    local ApplyPan = function()
        m_panX = math.max(0, math.min(mapW - panelWidth, m_panX))
        m_panY = math.max(0, math.min(mapH - panelHeight, m_panY))
        for _,layer in ipairs({ mapPanel, nodeLayer }) do
            if layer ~= nil and layer.valid then
                layer.selfStyle.x = -m_panX
                layer.selfStyle.y = -m_panY
            end
        end
    end

    local townContext = {
        OpenGuild = function()
            OpenLocation("guild")
        end,
        OpenGate = function()
            OpenLocation("gate")
        end,
        OpenGraveyard = function()
            EotwRoster.ShowGraveyard(resultPanel)
        end,
    }

    --One location on the map: a round icon over a name plaque. A locked
    --location dims and says why instead of opening.
    local LocationNode = function(loc)
        local NODE_WIDTH = 200
        return gui.Panel{
            classes = { "eotwTownNode" },
            floating = true,
            halign = "left",
            valign = "top",
            x = loc.x * mapW - NODE_WIDTH / 2,
            y = loc.y * mapH - 40,
            width = NODE_WIDTH,
            height = "auto",
            flow = "vertical",
            --a panel with no bgimage is not hit-tested.
            bgimage = "panels/square.png",
            bgcolor = "clear",
            swallowPress = true,
            hoverCursor = "pressbutton",
            data = { lockedReason = nil },
            thinkTime = 0.5,
            think = function(element)
                local reason = nil
                if loc.locked ~= nil then
                    reason = loc.locked(townContext)
                end
                element.data.lockedReason = reason
                element:SetClass("locked", reason ~= nil)
            end,
            create = function(element)
                element:FireEvent("think")
            end,
            hover = function(element)
                audio.FireSoundEvent("Mouse.Hover")
            end,
            linger = function(element)
                if element.data.lockedReason ~= nil then
                    gui.Tooltip(element.data.lockedReason)(element)
                end
            end,
            press = function(element)
                if element.data.lockedReason ~= nil then
                    audio.FireSoundEvent("Mouse.Click")
                    return
                end
                audio.FireSoundEvent("Mouse.Click")
                loc.open(townContext)
            end,

            gui.Panel{
                classes = { "eotwTownNodeIcon" },
                interactable = false,
                halign = "center",
                gui.Panel{
                    classes = { "eotwTownNodeGlyph" },
                    interactable = false,
                    bgimage = loc.icon,
                },
            },
            gui.Label{
                classes = { "eotwTownNodeLabel" },
                interactable = false,
                text = loc.label,
            },
        }
    end

    local nodes = {}
    for _,loc in ipairs(CITY_LOCATIONS) do
        nodes[#nodes+1] = LocationNode(loc)
    end

    local townStyles = {
        {
            selectors = { "eotwTownNodeIcon" },
            width = 64,
            height = 64,
            cornerRadius = 32,
            bgimage = "panels/square.png",
            bgcolor = "#1b140cee",
            borderWidth = 3,
            borderColor = "#d9b56a",
            transitionTime = 0.15,
        },
        {
            selectors = { "eotwTownNodeIcon", "parent:hover" },
            scale = 1.12,
            borderColor = "#ffe9b0",
            brightness = 1.2,
        },
        {
            selectors = { "eotwTownNodeGlyph" },
            width = 34,
            height = 34,
            halign = "center",
            valign = "center",
            bgcolor = "#f3dfae",
        },
        {
            selectors = { "eotwTownNodeLabel" },
            fontSize = 20,
            bold = true,
            color = "#f6ead0",
            width = "auto",
            height = "auto",
            halign = "center",
            tmargin = 4,
            hpad = 10,
            vpad = 3,
            bgimage = "panels/square.png",
            bgcolor = "#120d08dd",
            cornerRadius = 6,
            borderBox = true,
        },
        {
            selectors = { "eotwTownNode", "locked" },
            saturation = 0.15,
            brightness = 0.7,
        },
        {
            selectors = { "eotwPlaque" },
            bgimage = "panels/square.png",
            bgcolor = "#120d08e0",
            cornerRadius = 10,
            borderWidth = 2,
            borderColor = "#8c7a55",
            pad = 14,
            borderBox = true,
        },
    }

    ---- locations: full-screen scenes over the map ----

    --The card holding a location's controls sits on the right, clear of the
    --close button above it and the creator credit + chat button below it.
    local SCENE_CARD_TOP = 76
    local SCENE_CARD_BOTTOM = 104
    local SCENE_CARD_MARGIN = 40
    --The chat button moves left of the creator's logo while a scene is up
    --(the badge is 170 wide, 28 in from the edge).
    local SCENE_CHAT_BUTTON_MARGIN = 28 + 170 + 24

    local sceneStyles = {
        {
            selectors = { "eotwSceneCard" },
            bgimage = "panels/square.png",
            --translucent on purpose: the art should read through the card.
            bgcolor = "#0e0b08dc",
            borderWidth = 1,
            borderColor = "#d9b56a55",
            cornerRadius = 12,
        },
        {
            selectors = { "eotwSceneBack" },
            bgimage = "panels/square.png",
            bgcolor = "#0b0907b0",
            borderWidth = 1,
            borderColor = "#d9b56a66",
            cornerRadius = 20,
            transitionTime = 0.12,
        },
        {
            selectors = { "eotwSceneBack", "hover" },
            bgcolor = "#3a2e1ad0",
            borderColor = "#d9b56a",
        },
        {
            selectors = { "eotwSceneBackIcon" },
            bgcolor = "#d9b56a",
        },
        {
            selectors = { "eotwSceneBackIcon", "parent:hover" },
            bgcolor = "#ffe9b0",
        },
    }

    --The top-left of a scene: the way back to the map, then the place's
    --name over a gold rule and a line about it.
    local SceneHeader = function(scene)
        return gui.Panel{
            floating = true,
            halign = "left",
            valign = "top",
            hmargin = 56,
            vmargin = 40,
            width = 620,
            height = "auto",
            flow = "vertical",

            gui.Panel{
                classes = { "eotwSceneBack" },
                width = "auto",
                height = 40,
                hpad = 16,
                borderBox = true,
                flow = "horizontal",
                hoverCursor = "pressbutton",
                hover = function(element)
                    audio.FireSoundEvent("Mouse.Hover")
                end,
                press = function(element)
                    audio.FireSoundEvent("Mouse.Click")
                    CloseLocation()
                end,
                gui.Panel{
                    classes = { "eotwSceneBackIcon" },
                    interactable = false,
                    bgimage = "phosphor/arrow-left-bold.png",
                    width = 18,
                    height = 18,
                    valign = "center",
                    rmargin = 10,
                },
                gui.Label{
                    interactable = false,
                    text = "Back to Town",
                    fontSize = 17,
                    bold = true,
                    color = "#f6ead0",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                },
            },

            gui.Label{
                text = "<cspace=0.3em>BLACKBOTTOM</cspace>",
                fontSize = 15,
                bold = true,
                color = "#d9b56a",
                width = "auto",
                height = "auto",
                tmargin = 34,
            },
            gui.Label{
                text = scene.title,
                fontFace = "display",
                fontSize = 68,
                color = "#f6ead0",
                width = "auto",
                height = "auto",
            },
            --a gold rule, fading out to the right.
            gui.Panel{
                width = 340,
                height = 2,
                tmargin = 6,
                bgimage = "panels/square.png",
                bgcolor = "#d9b56a",
                gradient = gui.Gradient{
                    point_a = { x = 0, y = 0.5 },
                    point_b = { x = 1, y = 0.5 },
                    stops = {
                        { position = 0, color = core.Color{ r = 1, g = 1, b = 1, a = 1 } },
                        { position = 0.5, color = core.Color{ r = 1, g = 1, b = 1, a = 0.8 } },
                        { position = 1, color = core.Color{ r = 1, g = 1, b = 1, a = 0 } },
                    },
                },
            },
            gui.Label{
                text = scene.tagline,
                fontSize = 20,
                italics = true,
                color = "#ece3cf",
                width = 560,
                height = "auto",
                tmargin = 16,
            },
        }
    end

    --A location's full-screen scene: its art (credited to its creator by
    --CreatorCredit.Backdrop), a shade down the left for the header to read
    --on, the header, and a card on the right holding content. The scene is
    --opaque, so the map behind it takes no clicks.
    local LocationScene = function(loc, cardWidth, content)
        local scene = loc.scene
        return CreatorCredit.Backdrop{
            width = panelWidth,
            height = panelHeight,
            image = scene.art,
            aspect = scene.aspect,
            focusX = scene.focusX,
            badge = { hmargin = 28, vmargin = 24 },
            children = {
                gui.Panel{
                    floating = true,
                    halign = "left",
                    valign = "top",
                    width = 1000,
                    height = panelHeight,
                    interactable = false,
                    bgimage = "panels/square.png",
                    bgcolor = "black",
                    gradient = gui.Gradient{
                        point_a = { x = 0, y = 0.5 },
                        point_b = { x = 1, y = 0.5 },
                        stops = {
                            { position = 0, color = core.Color{ r = 1, g = 1, b = 1, a = 0.78 } },
                            { position = 0.4, color = core.Color{ r = 1, g = 1, b = 1, a = 0.45 } },
                            { position = 1, color = core.Color{ r = 1, g = 1, b = 1, a = 0 } },
                        },
                    },
                },
                gui.Panel{
                    styles = sceneStyles,
                    floating = true,
                    width = "100%",
                    height = "100%",
                    flow = "none",
                    SceneHeader(scene),
                    gui.Panel{
                        classes = { "eotwSceneCard" },
                        floating = true,
                        halign = "right",
                        valign = "top",
                        hmargin = SCENE_CARD_MARGIN,
                        tmargin = SCENE_CARD_TOP,
                        width = cardWidth,
                        height = panelHeight - SCENE_CARD_TOP - SCENE_CARD_BOTTOM,
                        pad = 24,
                        borderBox = true,
                        flow = "vertical",
                        content,
                    },
                },
            },
        }
    end

    --The active heroes along the bottom: the hero cards the montage uses
    --(EotwHeroCard), one per active roster hero whose working copy has
    --loaded. Clicking a card opens that hero's sheet.
    local m_stripSignature = nil
    local m_stripRefreshAt = 0
    local heroStrip = gui.Panel{
        floating = true,
        halign = "center",
        valign = "bottom",
        bmargin = 14,
        width = "auto",
        height = "auto",
        flow = "horizontal",
        styles = ThemeEngine.MergeTokens(EotwHeroCard.rules),
        thinkTime = 0.25,
        think = function(element)
            local active = EotwRoster.ActiveHeroes()
            --the listed state and living count pick the placeholder text.
            local parts = { tostring(EotwRoster.GetHeroes() ~= nil), tostring(EotwRoster.LivingCount()) }
            for _,hero in ipairs(active) do
                parts[#parts+1] = string.format("%s:%s", hero.heroid, tostring(dmhub.GetCharacterById(hero.heroid) ~= nil))
            end
            local signature = table.concat(parts, "|")
            if signature ~= m_stripSignature then
                m_stripSignature = signature
                local cards = {}
                for _,hero in ipairs(active) do
                    local heroid = hero.heroid
                    if dmhub.GetCharacterById(heroid) ~= nil then
                        cards[#cards+1] = gui.Panel{
                            width = "auto",
                            height = "auto",
                            hmargin = 10,
                            valign = "bottom",
                            EotwHeroCard.CreateHeroCard({
                                charid = heroid,
                                mine = true,
                                name = (hero.summary or {}).name or "Hero",
                            }, {
                                halign = "center",
                                showStats = true,
                                --in town: characteristics, stamina and
                                --recoveries, but no skills or heroic resource.
                                showSkills = false,
                                showResources = false,
                                subtitle = function(tok)
                                    local className, ancestry, level = EotwRoster.HeroDetails(tok)
                                    return EotwRoster.FormatDetails(level, ancestry, className)
                                end,
                                click = function()
                                    EotwRoster.EditHero(heroid)
                                end,
                            }),
                        }
                    end
                end
                if #cards == 0 and EotwRoster.GetHeroes() ~= nil then
                    cards[1] = gui.Label{
                        classes = { "eotwPlaque" },
                        text = cond(EotwRoster.LivingCount() == 0,
                            "You have no heroes yet. Visit the Hero's Guild to create or recruit one.",
                            "None of your heroes are active. Visit the Hero's Guild to choose up to four."),
                        fontSize = 20,
                        color = "#f6ead0",
                        width = "auto",
                        height = "auto",
                        maxWidth = 900,
                        styles = townStyles,
                    }
                end
                element.children = cards
                m_stripRefreshAt = 0
            end
            --the cards repaint from their characters on refreshCard.
            local now = dmhub.Time()
            if now >= m_stripRefreshAt then
                m_stripRefreshAt = now + 1
                element:FireEventTree("refreshCard")
            end
        end,
    }

    --The Town Gate's controls, the body of its scene: parties forming up and
    --encounters underway (the roster records of the city's games list),
    --forming a party, and a party's own view while you are in it.
    gatePanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",

        gui.Label{
            text = "Adventuring Parties",
            fontSize = 26,
            bold = true,
            color = "#efe4cc",
            width = "100%",
            height = "auto",
            bmargin = 4,
            create = function(element)
                gamesTitleLabel = element
            end,
        },

        gui.Panel{
            width = "100%",
            height = "100%-110",
            flow = "vertical",
            vscroll = true,
            rpad = 12,
            borderBox = true,
            create = function(element)
                gamesListPanel = element
                RefreshGames()
                RefreshResumeState()
            end,
        },

        --error line for rejected roster requests (join on a full game, a
        --hero already in another party, etc).
        gui.Label{
            fontSize = 16,
            color = "#ff8888",
            width = "100%",
            height = 22,
            textAlignment = "center",
            text = "",
            create = function(element)
                gamesErrorLabel = element
            end,
            clearError = function(element)
                element.text = ""
            end,
            showError = function(element, message)
                element.text = tostring(message)
                element:ScheduleEvent("clearError", 5)
            end,
        },

        --hidden while a party view is open (RefreshGames collapses it);
        --leaving the party is the way back to the list.
        gui.Button{
            text = "Form a Party",
            fontSize = 22,
            width = 240,
            height = 48,
            halign = "center",
            valign = "bottom",
            create = function(element)
                createGameButton = element
            end,
            click = function(element)
                ShowCreateDialog()
            end,
        },
    }

    gateScene = LocationScene(CityLocation("gate"), GATE_CARD_WIDTH_LIST, gatePanel)
    gateScene:SetClass("collapsed", true)

    --Hides the town's own furniture while a scene is up, and moves the chat
    --button clear of the scene's creator credit.
    local ApplyLocationMode = function()
        local inLocation = m_locationId ~= nil
        for _,p in ipairs({ townViewport, townPlaque, heroStrip }) do
            if p ~= nil and p.valid then
                p:SetClass("collapsed", inLocation)
            end
        end
        if chatButton ~= nil and chatButton.valid then
            chatButton.selfStyle.hmargin = cond(inLocation, SCENE_CHAT_BUTTON_MARGIN, 20)
        end
    end

    CloseLocation = function()
        if m_locationId == nil then
            return
        end
        if gateScene ~= nil and gateScene.valid then
            gateScene:SetClass("collapsed", true)
        end
        if m_guildScene ~= nil and m_guildScene.valid then
            m_guildScene:DestroySelf()
        end
        m_guildScene = nil
        m_locationId = nil
        ApplyLocationMode()
    end

    OpenLocation = function(id)
        if m_locationId == id or locationHost == nil or not locationHost.valid then
            return
        end
        CloseLocation()
        m_locationId = id
        if id == "gate" then
            gateScene:SetClass("collapsed", false)
            CreatorCredit.ReplayFade(gateScene)
            --re-check the resume row too: the lookup made when the screen
            --was built can come back empty if the lobby was not ready yet.
            RefreshResumeState()
            RefreshGames()
            --pick up encounter modules published since the town opened.
            EncounterOfTheWeek.RefreshPool()
        elseif id == "guild" then
            m_guildScene = LocationScene(CityLocation("guild"), 860, EotwRoster.GuildPanel(resultPanel))
            locationHost:AddChild(m_guildScene)
        end
        ApplyLocationMode()
    end

    --Town chat + who is in town, in a drawer over the bottom-right corner.
    chatPanel = gui.Panel{
        classes = { "eotw-area", "collapsed" },
        floating = true,
        bgimage = "panels/square.png",
        width = 520,
        height = 560,
        halign = "right",
        valign = "bottom",
        hmargin = 20,
        bmargin = 80,
        flow = "vertical",
        styles = areaStyles,
        cornerRadius = 10,

        AreaTitle("Town Chat", function(element)
            chatTitleLabel = element
        end),

        gui.Label{
            fontSize = 16,
            color = Styles.textColor,
            opacity = 0.7,
            width = "94%",
            height = "auto",
            halign = "center",
            text = "",
            create = function(element)
                presenceLabel = element
                RefreshPresence()
            end,
        },

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
                chatMessagesPanel = element
                RefreshChat()
            end,
        },

        --error line for rejected sends (rate limit etc).
        gui.Label{
            fontSize = 15,
            color = "#ff8888",
            width = "94%",
            height = 20,
            halign = "center",
            text = "",
            create = function(element)
                chatErrorLabel = element
            end,
            clearError = function(element)
                element.text = ""
            end,
            showError = function(element, message)
                element.text = message
                element:ScheduleEvent("clearError", 5)
            end,
        },

        gui.Input{
            width = "94%",
            height = 34,
            halign = "center",
            vmargin = 6,
            fontSize = 18,
            placeholderText = "Say something...",
            characterLimit = 400,
            change = function(element)
                local text = (element.text or ""):match("^%s*(.-)%s*$")
                if text == "" or m_conn == nil then
                    return
                end
                element.text = ""
                --inside a party view the send targets that party's channel.
                local args = { text = text }
                if m_viewGameid ~= nil then
                    args.gameid = m_viewGameid
                end
                m_conn:Request{
                    action = "chat",
                    args = args,
                    error = function(message)
                        if chatErrorLabel ~= nil and chatErrorLabel.valid then
                            chatErrorLabel:FireEvent("showError", message)
                        end
                    end,
                }
            end,
        },
    }

    resultPanel = gui.Panel{
        id = "encounterOfTheWeekScreen",
        classes = { "framedPanel" },
        floating = true,
        width = panelWidth,
        height = panelHeight,
        uiscale = uiscale,
        halign = "center",
        valign = "center",
        flow = "none",
        bgimage = "panels/square.png",
        bgcolor = "#0b0907",
        styles = {
            Styles.Default,
            Styles.Panel,
            --The opening cross-fade. The screen is BUILT carrying
            --"eotwOpening" (so it starts invisible with no transition to
            --play), and the veil sheds the class once the build has
            --settled; this rule's transitionTime is what the ramp back to
            --full opacity then runs over. See CreateLoadingVeil.
            {
                selectors = { "framedPanel", "eotwOpening" },
                opacity = 0,
                transitionTime = VEIL_CROSSFADE_SECONDS,
            },
        },

        captureEscape = true,
        --Above the titlescreen's own escape (3) and below the hero builder
        --(5, see EotwBuilder.lua), which mounts over this screen. The town's
        --dialogs sit at EXIT_MODAL_DIALOG. The close button does NOT take
        --escape: at its default EXIT_DIALOG it would close the whole town
        --from inside a location, a dialog, or the builder.
        escapePriority = 4,
        escape = function(element)
            --close the topmost town panel first: the chat drawer, then
            --an open location, and the town itself last.
            if chatPanel ~= nil and chatPanel.valid and not chatPanel:HasClass("collapsed") then
                chatPanel:SetClass("collapsed", true)
                return
            end
            if m_locationId ~= nil then
                CloseLocation()
                return
            end
            element:FireEvent("closeEncounterOfTheWeek")
        end,

        closeEncounterOfTheWeek = function(element)
            element:DestroySelf()
        end,

        --Entering a game raises the titlescreen's loading screen, but this
        --screen is a FLOATING sibling of it on the titlescreen root, so it
        --kept drawing on top of the loading art -- and stayed there until
        --C# deactivated the whole titlescreen a second after the load
        --finished. So hide it for the load -- but only once the loading
        --screen has finished dissolving in, otherwise the player watches
        --this screen vanish first and the art fade in over the bare
        --titlescreen. Hidden panels still receive events, so we can come
        --back. And hidden, never destroyed: SweepStaleScreen uses a
        --surviving screen on the root as the record that the player was
        --here when they left, and replaces it with a live one on return.
        data = {
            loadingUp = false,
        },

        beginLoading = function(element)
            element.data.loadingUp = true
            element:ScheduleEvent("hideBehindLoadingScreen", LOADING_SCREEN_FADE_IN_SECONDS)
        end,

        hideBehindLoadingScreen = function(element)
            --a return that completed inside the fade window leaves us
            --visible on purpose; don't hide behind a screen that is gone.
            if not element.data.loadingUp then
                return
            end
            element:SetClass("hidden", true)
        end,

        --Safety net for a return that does NOT reload the titlescreen
        --codemods: the sweep would never run and this screen would stay
        --hidden forever (ShowScreen no-ops while it is alive).
        returnFromGameComplete = function(element)
            element.data.loadingUp = false
            element:SetClass("hidden", false)
        end,

        --Keep our roster records alive: the city expires a game 5 minutes
        --after its last heartbeat, so while this screen is open we beat
        --every game we host or occupy (well inside the 60s cadence the
        --server expects).
        thinkTime = 30,
        think = function(element)
            --Self-heal a terminally closed connection: the C# side never
            --reconnects a Close()d connection, so open a fresh one and
            --rebind our watchers to it. (Transient drops reconnect on
            --their own and never reach the "closed" status.)
            if m_conn ~= nil and lobbiesApi ~= nil and m_conn.status == "closed" then
                m_conn = lobbiesApi:Connect(LOBBY_ID, LOBBY_OPTIONS)
                EotwRoster.Attach(m_conn)
                m_initialGameStatus = nil
                if AttachMonitors ~= nil then
                    AttachMonitors()
                end
                RefreshAll()
            end
            if m_conn == nil or not m_conn.connected then
                return
            end
            local games = m_conn:GetPath("/state/games")
            if games == nil then
                return
            end
            local myUserid = dmhub.loginUserid
            for gameid,record in pairs(games) do
                if record.hostUserid == myUserid or (record.players ~= nil and record.players[myUserid] ~= nil) then
                    m_conn:Request{
                        action = "heartbeat",
                        args = { gameid = gameid },
                    }
                end
            end
        end,

        --fires on DestroySelf and on titlescreen teardown alike; the C#
        --side drops its handler refs and closes the shared connection.
        destroy = function(element)
            if m_conn ~= nil then
                EotwRoster.Detach(m_conn)
                m_conn:Disconnect()
                m_conn = nil
            end
        end,

        --the map, pannable by dragging anywhere that is not a location.
        gui.Panel{
            floating = true,
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "center",
            flow = "none",
            clip = true,
            bgimage = "panels/square.png",
            --must be opaque: a clip panel whose own background is fully
            --transparent hides all of its children.
            bgcolor = "black",
            draggable = true,
            dragMove = false,
            dragThreshold = 4,
            styles = townStyles,
            create = function(element)
                townViewport = element
            end,
            events = {
                press = function(element)
                    m_dragStartX = m_panX
                    m_dragStartY = m_panY
                end,
                dragging = function(element)
                    local dd = element.dragDelta
                    m_panX = m_dragStartX - dd.x
                    m_panY = m_dragStartY - dd.y
                    ApplyPan()
                end,
            },

            gui.Panel{
                floating = true,
                halign = "left",
                valign = "top",
                width = mapW,
                height = mapH,
                flow = "none",
                bgimage = CITY_MAP_IMAGE,
                bgcolor = "white",
                interactable = false,
                create = function(element)
                    mapPanel = element
                    ApplyPan()
                end,
            },
            --the nodes ride on their own layer over the map, moved with it
            --(the map image panel is not interactable, so its children
            --would not be either).
            gui.Panel{
                floating = true,
                halign = "left",
                valign = "top",
                width = mapW,
                height = mapH,
                flow = "none",
                create = function(element)
                    nodeLayer = element
                    ApplyPan()
                end,
                children = nodes,
            },
        },

        --the town's name plaque, who is here, and the connection state.
        gui.Panel{
            classes = { "eotwPlaque" },
            floating = true,
            halign = "left",
            valign = "top",
            hmargin = 20,
            vmargin = 20,
            width = 440,
            create = function(element)
                townPlaque = element
            end,
            height = "auto",
            flow = "vertical",
            styles = townStyles,
            gui.Label{
                text = "Blackbottom",
                fontSize = 40,
                bold = true,
                color = "#f6ead0",
                width = "auto",
                height = "auto",
            },
            gui.Label{
                text = "Encounter of the Week",
                fontSize = 18,
                italics = true,
                color = "#c9bfa9",
                width = "auto",
                height = "auto",
            },
            gui.Label{
                fontSize = 16,
                color = "#c9bfa9",
                width = "100%",
                height = "auto",
                tmargin = 6,
                text = "",
                data = { seen = nil },
                thinkTime = 1,
                think = function(element)
                    if m_conn == nil then
                        return
                    end
                    local presence = m_conn:GetPath("/presence")
                    local n = 0
                    for _,_ in pairs(presence or {}) do
                        n = n + 1
                    end
                    element.text = string.format("%d adventurer%s in town", n, cond(n == 1, "", "s"))
                end,
            },
            --connection status line (blank while healthy).
            gui.Label{
                fontSize = 16,
                color = "#ffcc66",
                width = "100%",
                height = "auto",
                create = function(element)
                    statusLabel = element
                    RefreshStatus()
                end,
            },
        },

        heroStrip,

        --the open location's full-screen scene, over the town and under the
        --chat and the close button (see OpenLocation).
        gui.Panel{
            floating = true,
            width = "100%",
            height = "100%",
            flow = "none",
            create = function(element)
                locationHost = element
            end,
            gateScene,
        },

        --chat drawer toggle, bottom-right (left of a scene's creator credit).
        gui.Button{
            text = "Town Chat",
            fontSize = 18,
            floating = true,
            halign = "right",
            valign = "bottom",
            hmargin = 20,
            bmargin = 20,
            width = 160,
            height = 44,
            create = function(element)
                chatButton = element
            end,
            click = function(element)
                chatPanel:SetClass("collapsed", not chatPanel:HasClass("collapsed"))
                RefreshChat()
            end,
        },

        chatPanel,

        gui.CloseButton{
            floating = true,
            halign = "right",
            valign = "top",
            hmargin = 12,
            vmargin = 12,
            escapeActivates = false,
            click = function(element)
                element:FireEventOnParents("closeEncounterOfTheWeek")
            end,
        },
    }

    --Watch the lobby document + connection state. Handlers are dropped by
    --Disconnect (destroy above); guard panel validity anyway since C#
    --dispatches these outside the gui event flow. A function (rather than
    --inline registration) so the think's self-heal can rebind the watchers
    --after replacing a terminally closed connection.
    AttachMonitors = function()
        if m_conn == nil then
            return
        end
        m_conn:MonitorChanges(function(path)
            if mod.unloaded or resultPanel == nil or not resultPanel.valid then
                return
            end
            if path == "/" then
                RefreshAll()
                EotwRoster.Refresh()
            elseif path == "/presence/" .. dmhub.loginUserid then
                --our presence entry carries our roster revision: a change
                --made on this or another machine re-lists the roster.
                RefreshPresence()
                EotwRoster.Refresh()
            elseif string.starts_with(path, "/chat") then
                RefreshChat()
            elseif string.starts_with(path, "/gamechat") then
                RefreshChat()
            elseif string.starts_with(path, "/presence") then
                RefreshPresence()
            elseif string.starts_with(path, "/state") then
                --roster changes can also end a game lobby view (record
                --dropped) or change the slots on show there.
                RefreshGames()
            end
        end)
        m_conn:MonitorStatus(function(status)
            if mod.unloaded or resultPanel == nil or not resultPanel.valid then
                return
            end
            RefreshStatus()
            if status == "connected" then
                RefreshAll()
                EotwRoster.Refresh()
            end
        end)
    end
    AttachMonitors()

    --Start streaming the picker's portraits now, while the player is
    --reading the overview and the games list, so the Add-a-Hero grid is
    --warm by the time they open it.
    resultPanel:AddChild(CreatePortraitWarmer())

    return resultPanel
end

--── stale-screen sweep ──────────────────────────────────────────────────
--Returning from a game reloads the titlescreen codemods but PRESERVES the
--titlescreen's panel tree -- including any EotW screen that was open when
--the game was entered (which is always the case for a game launched from
--this screen). That surviving screen belongs to the previous codemod
--generation: its lobby connection was closed during the game switch and is
--never reopened, so every control on it fails with "Not connected to the
--lobby". Replace it with a freshly built screen, which connects anew and
--renders the current lobby state -- including the Resume/Abandon row for
--the game the player just left.
--
--m_screen is nil in a freshly loaded generation, so any screen found on
--the root here is by definition stale. If the reload happened while inside
--a real game (titlescreen hidden), rebuilding waits until we are actually
--back at the titlescreen, then gives up quietly after a few tries.
local function SweepStaleScreen(retriesLeft)
    if mod.unloaded then
        return
    end
    local root = rawget(_G, "CodexTitlescreenRoot")
    if root == nil or not root.valid then
        return
    end
    if m_screen ~= nil and m_screen.valid then
        --this generation owns a live screen; nothing stale to sweep.
        return
    end
    --A veil from the previous generation is stale by the same argument,
    --and worse than a stale screen: its scheduled build bails on
    --mod.unloaded, so left alone it sits there opaque and inert. Sweep it
    --whether or not a stale screen turned up.
    for _,ch in ipairs(root.children) do
        if ch.id == "eotwLoadingVeil" and ch.valid and ch ~= m_veil then
            ch:DestroySelf()
        end
    end

    local found = false
    for _,ch in ipairs(root.children) do
        if ch.id == "encounterOfTheWeekScreen" and ch.valid then
            found = true
        end
    end
    if not found then
        return
    end
    --"At the titlescreen" must mean the LOBBY game is the active game. The old
    --check also accepted "not in a game", which is true during a real game's
    --LOADING phase -- so the engine's mid-session hard refresh (e.g. arming
    --player-host mode) made this sweep rebuild the screen and SHOW it over the
    --game the player was still in. A real return to the titlescreen re-enters
    --the lobby game and reloads these codemods, so the sweep re-arms there.
    local atTitlescreen = false
    pcall(function() atTitlescreen = (dmhub.isLobbyGame == true) end)
    if not atTitlescreen then
        if retriesLeft > 0 then
            dmhub.Schedule(2, function()
                SweepStaleScreen(retriesLeft - 1)
            end)
        end
        return
    end
    for _,ch in ipairs(root.children) do
        if ch.id == "encounterOfTheWeekScreen" and ch.valid then
            ch:DestroySelf()
        end
    end
    EncounterOfTheWeek.ShowScreen()
end

dmhub.Schedule(1, function()
    SweepStaleScreen(5)
end)
