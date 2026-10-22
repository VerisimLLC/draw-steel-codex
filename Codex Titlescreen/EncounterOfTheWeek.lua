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

--Analytics: the town is open (Codex Titlescreen/EotwAnalytics.lua). Tags
--every event sent while it is up as EotW, and closes any run this player
--left by quitting or crashing that they can no longer resume (the slot game
--is the one they still can).
local function AnalyticsTownOpened()
    pcall(function()
        EotwAnalytics.TownOpened()
        local slot = nil
        pcall(function() slot = lobby.eotwGameid end)
        EotwAnalytics.ReconcileRuns(slot)
    end)
end

--Launch-timing marker: grep Player.log for "[EOTWPROF]". server= is
--dmhub.serverTime, which every client shares, so the host's and the members'
--logs line up on one clock. The game-side codemod logs the same way. Never
--throws: it runs inside the arrival callback, which must not fail.
local function EotwProf(fmt, ...)
    local args = table.pack(...)
    pcall(function()
        printf("[EOTWPROF] server=%.3f app=%.3f " .. fmt, dmhub.serverTimeMilliseconds * 0.001, dmhub.Time(), table.unpack(args, 1, args.n))
    end)
end

--Opt-in gate, shown as "Encounter of the Week Beta" in General Settings
--(chat also works: /toggle dev:encounteroftheweek). The id keeps its old
--dev: name so existing opt-ins carry over. The titlescreen card monitors
--this id, so ticking it at the titlescreen shows the card straight away.
EncounterOfTheWeek.enabledSetting = setting{
    id = "dev:encounteroftheweek",
    description = "Encounter of the Week Beta",
    help = "Opt in to the Encounter of the Week beta: adds the Encounter of the Week card to the title screen.",
    editor = "check",
    section = "general",
    default = false,
    storage = "preference",
    onchange = function()
        --Warm the pregen cache now rather than on the first open.
        if EncounterOfTheWeek.Enabled() then
            EncounterOfTheWeek.CachePregens()
        end
    end,
}

--Fast launch: members enter the game on "launched", loading alongside the
--host, and wait behind the loading screen for the host's setup stamp; every
--client starts directly on the encounter map. Off = the old order (members
--enter on "ready", after the host has loaded and set up). No editor entry;
--kept for timing the two against each other: /toggle eotw:fastlaunch
EncounterOfTheWeek.fastLaunchSetting = setting{
    id = "eotw:fastlaunch",
    default = true,
    storage = "preference",
}

function EncounterOfTheWeek.FastLaunch()
    return dmhub.GetSettingValue("eotw:fastlaunch") ~= false
end

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

--Set by the game-side EotW codemod when the player abandons a game: JSON
--{ gameid }. The resume refresh abandons that game (AbandonGame: deleted
--when nobody else still holds it, otherwise left to the others) and resets
--this. Same setting id as the game codemod's declaration.
setting{
    id = "eotw:abandonedgame",
    default = "",
    storage = "preference",
}

--Set by the game-side EotW codemod after a Proving Pits game: the debrief
--this player owes, { [userid] = {gameid, encounter, result} } as JSON. The
--town asks for it (ShowDebriefDialog) and clears it. Same id as the game
--codemod's declaration.
setting{
    id = "eotw:pendingDebrief",
    default = "",
    storage = "preference",
}

--Set by the game-side EotW codemod after a finished game while EotW is in
--beta: the survey invitation this player has waiting, { [userid] = {gameid,
--encounter, kind, outcome, minutes, players, heroes} } as JSON. The town
--invites them (ShowSurveyDialog) and clears it, answered or declined. Same
--id as the game codemod's declaration.
setting{
    id = "eotw:pendingSurvey",
    default = "",
    storage = "preference",
}

--The accounts on this machine that have seen the town's welcome dialog
--(ShowWelcomeDialog), as JSON text: { [userid] = true }. Machine-local, so a
--player on a second machine sees it once more.
setting{
    id = "eotw:welcomed",
    default = "",
    storage = "preference",
}

--The newest chat message this player has seen in the town's chat drawer,
--per channel ("town", or a party's gameid), in server ms. Drives the
--drawer's New divider.
setting{
    id = "eotw:chatlastviewed",
    default = {},
    storage = "preference",
}

--The town's city (see EotwRoster.lua). Its server is EotwRoster.CityOptions(),
--read at each connect.
local LOBBY_ID = EotwRoster.CITY_ID

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

--The Proving Pits' art: the front cover of Draw Steel: Monsters, rendered
--from the cover PSD with its title text, spine and text shadow hidden, and
--cropped to a 16:9 band (3840x2160) around the beholder. MCDM's own art, so
--no creator credit. Sources in C:/dev/eotw/art/ (danger-rooms-*).
local DANGER_ART = "92f3f806-327b-498c-9705-49972311c3e3"

--The Blue Fish Inn: Czepeku Scenes' "Ages of the Vale Pt. 3" (Original Day),
--a 30s looping 1080p video of a tavern's hearth, over its first frame as the
--still. Sources in C:/dev/eotw/art/ (blue-fish-inn-*).
local INN_VIDEO = "07d3b304-792c-4b5c-8340-814c9da9f864"
local INN_ART = "e9f0c6ae-2041-476b-ba46-e945b374fa6b"
CreatorCredit.RegisterArt(INN_VIDEO, "czepeku")
CreatorCredit.RegisterArt(INN_ART, "czepeku")

--The Arcane Market: Czepeku Scenes' "Black Market Streets" (Original Day), a
--30s looping 1080p video, over its first frame as the still. Sources in
--C:/dev/eotw/art/ (arcane-market-*).
local MARKET_VIDEO = "2d82c3b6-de21-47f0-bfd2-f17708bf4c85"
local MARKET_ART = "a2a30693-a725-48fc-90cd-dfd028e58dc8"
CreatorCredit.RegisterArt(MARKET_VIDEO, "czepeku")
CreatorCredit.RegisterArt(MARKET_ART, "czepeku")

--The Hall of Heroes, which the whole town builds together (the community
--project Build the Hall of Heroes, EotwDowntime.lua). While it is being
--built the location is the Construction, over Czepeku Scenes' "Train Station
--Approach" (the Town Square still); once built, the Hall plays the same
--scene's "Original Day" 30s 1080p loop over its first frame. Core image
--assets uploaded 2026-10-22; sources in C:/dev/eotw/art/ (hall-*).
local CONSTRUCTION_ART = "c9e0c66f-4f10-441d-8acf-3f4bdb17b373" --Town Square still, 3840x2160
local HALL_VIDEO = "7d454b91-a9f0-495a-94e2-8754b33fa619"
local HALL_ART = "e35b71f8-8fb4-4e4d-ae59-0e9fb3814e72" --the video's first frame, 1920x1080
CreatorCredit.RegisterArt(CONSTRUCTION_ART, "czepeku")
CreatorCredit.RegisterArt(HALL_VIDEO, "czepeku")
CreatorCredit.RegisterArt(HALL_ART, "czepeku")

--The two faces of the Hall's location; OpenLocation picks one as its scene.
local CONSTRUCTION_SCENE = {
    art = CONSTRUCTION_ART,
    aspect = 16 / 9,
    focusX = 0.5,
    title = "The Construction",
    tagline = "Join in the construction of the great Hall of Heroes where the works and deeds of heroes shall be recorded!",
}
local HALL_SCENE = {
    art = HALL_ART,
    video = HALL_VIDEO,
    aspect = 16 / 9,
    focusX = 0.5,
    title = "The Hall of Heroes",
    tagline = "Every party that has conquered an Encounter of the Week is remembered here. Choose one to relive their victory.",
}

--The town's locations, as fractions of the map image (so they survive a
--re-export at another size). open(ctx) runs on click; locked(ctx) returns
--the reason the location is closed, or nil; hidden(ctx), if given, takes the
--location off the map entirely while it returns true. A location with a scene opens
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
            tagline = "Parties muster in the market below the old tower before they set out to face the Encounter of the Week. Join one that is forming, or gather your own.",
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
    --Downtime (EotwDowntime.lua): a respite turns Victories into XP and
    --Downtime Activities and heals every hero at home.
    {
        id = "inn",
        label = "Blue Fish Inn",
        icon = "phosphor/beer-stein-fill.png",
        --the canal-side building west of the Guild: level with it, so the
        --hero cards along the bottom of the screen do not cover it (it was
        --at the "Drunken Fool" tavern, (0.335, 0.575), until 2026-10-11).
        x = 0.235,
        y = 0.455,
        scene = {
            art = INN_ART,
            video = INN_VIDEO,
            aspect = 16 / 9,
            focusX = 0.65,
            title = "The Blue Fish Inn",
            tagline = "A warm hearth, a hot meal and a bed that does not sway. Rest here to turn your Victories into experience, or just catch your breath before the next fight.",
        },
        --not on the map at all until heroes first come home from the Town
        --Gate; the town then plays its reveal (PlayInnReveal).
        hidden = function(ctx) return not ctx.InnShown() end,
        locked = function(ctx)
            if EotwRoster.GetHeroes() == nil then
                return "The guild is still checking your roster..."
            end
            if EotwRoster.LivingCount() == 0 then
                return "You need a hero before you can rest. Visit the Hero's Guild."
            end
            return nil
        end,
        open = function(ctx) ctx.OpenInn() end,
    },
    --Consumable treasures (EotwMarket.lua): each hero makes a Presence test
    --to find what is on offer and buys up to their Wealth, once between
    --encounters. Not on the map until the player finds it: a lead heard
    --carousing at the inn, then the Find the Arcane Market project
    --(EotwLeads.lua); RevealFoundLocations shows it the moment it is found.
    {
        id = "market",
        label = "Arcane Market",
        icon = "phosphor/storefront-fill.png",
        --the shop the map's own "Front and Back" label points at.
        x = 0.695,
        y = 0.18,
        scene = {
            art = MARKET_ART,
            video = MARKET_VIDEO,
            aspect = 16 / 9,
            focusX = 0.5,
            title = "The Arcane Market",
            tagline = "Behind the honest shopfronts, carts and back rooms deal in potions, powders and stranger things. Ask the right questions and the right stall finds you.",
        },
        hidden = function(ctx) return not EotwRoster.MarketUnlocked() end,
        locked = function(ctx)
            if EotwRoster.GetHeroes() == nil then
                return "The guild is still checking your roster..."
            end
            if EotwRoster.LivingCount() == 0 then
                return "You need a hero before you can shop. Visit the Hero's Guild."
            end
            return nil
        end,
        open = function(ctx) ctx.OpenMarket() end,
    },
    --Where new, untried encounters made by the town's own players are run:
    --practice, with nothing kept. Opens for good once the account has won an
    --Encounter of the Week (the city decides; see EotwRoster.DangerRoomsUnlocked).
    {
        id = "danger",
        label = "Proving Pits",
        icon = "phosphor/skull-fill.png",
        --level with the Guild: anything much lower sits under the hero
        --cards along the bottom of the screen.
        x = 0.74,
        y = 0.42,
        scene = {
            art = DANGER_ART,
            aspect = 16 / 9,
            focusX = 0.3,
            title = "The Proving Pits",
            tagline = "Untried horrors dreamed up by the town's own, loosed on whoever dares. It is only practice: no Victories, no treasure, nothing kept. Survive, then tell the makers what you thought.",
        },
        locked = function(ctx)
            if EotwRoster.GetHeroes() == nil then
                return "The guild is still checking your roster..."
            end
            if EotwRoster.DangerRoomsUnlocked() ~= true then
                return "Defeat the Encounter of the Week to unlock the Proving Pits."
            end
            if EotwRoster.LivingCount() == 0 then
                return "You need a hero before you can venture out. Visit the Hero's Guild."
            end
            return nil
        end,
        open = function(ctx) ctx.OpenDangerRooms() end,
    },
    {
        id = "graveyard",
        label = "Graveyard",
        icon = "phosphor/hands-praying-fill.png",
        x = 0.31,
        y = 0.86,
        open = function(ctx) ctx.OpenGraveyard() end,
    },
    --The Construction, until the whole town has built the Hall of Heroes
    --(EotwRoster.HallBuilt); then the Hall: every party that won an
    --Encounter of the Week, and the victory screen each saw. Open to all,
    --even with no hero yet. label and icon follow which it is (LocationNode).
    {
        id = "hall",
        label = function(ctx) return cond(EotwRoster.HallBuilt(), "Hall of Heroes", "Construction") end,
        icon = function(ctx) return cond(EotwRoster.HallBuilt(), "phosphor/trophy-fill.png", "phosphor/hammer-fill.png") end,
        x = 0.33,
        y = 0.2,
        --replaced by OpenLocation each time it opens.
        scene = CONSTRUCTION_SCENE,
        open = function(ctx) ctx.OpenHall() end,
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
--playable. Games live on the same server as the town (EotwRoster.GameBackend()).
local STARTING_MODULE = "mcdm-encounteroftheweek"

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
--    or Unlisted (both are in the index) with moduleType == EncounterOfTheWeek.MODULE_TYPE (the publish dialog,
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

--A series part can have its own map: "Encounter: The Crypt (Part 2)". The
--town lists it as "Encounter: The Crypt", never as an encounter of its own.
--The game side and both publishers have copies of these two; keep them the same.
function EncounterOfTheWeek.PartMapName(seriesMapName, part)
    return string.format("%s (Part %d)", seriesMapName, part)
end

--The series map's name and the part, if `name` is a part map's name.
function EncounterOfTheWeek.SplitPartMapName(name)
    local base, number = string.match(name or "", "^(.-) %(Part (%d+)%)$")
    if base == nil or base == "" then
        return nil, nil
    end
    return base, tonumber(number)
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

--A SERIES is one encounter map played as several encounters, unlocked one
--after another ("# Part N" scripts; see "Encounter series" in
--EncounterOfTheWeek.md). Its parts are keyed off the map's key: part 1 is the
--bare key, a later part adds "#<n>" ("Encounter: The Crypt#2"). Map names
--can never hold "#". The bare key also names the whole series: the schedule,
--the Proving Pits rows and votes all use it.
--key -> the series' key (the bare key), part number (1 when none).
function EncounterOfTheWeek.SplitPartKey(key)
    if type(key) ~= "string" then
        return key, 1
    end
    local base, number = key:match("^(.-)#(%d+)$")
    if base == nil then
        return key, 1
    end
    return base, math.max(1, tonumber(number) or 1)
end

--The key of a series' part n.
function EncounterOfTheWeek.PartKey(seriesKey, n)
    if n == nil or n <= 1 then
        return seriesKey
    end
    return string.format("%s#%d", seriesKey, n)
end

--key -> moduleid, map name, part. nil or "" is the official module's default map.
function EncounterOfTheWeek.ParseEncounterKey(key)
    if type(key) ~= "string" or key == "" then
        return STARTING_MODULE, ENCOUNTER_MAP_NAME, 1
    end
    local part
    key, part = EncounterOfTheWeek.SplitPartKey(key)
    local moduleid, mapName = key:match("^([^|]+)|(.+)$")
    if moduleid == nil then
        return STARTING_MODULE, key, part
    end
    return moduleid, mapName, part
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
--A series' part reads "<that> -- Part 2: The Ossuary".
function EncounterOfTheWeek.EncounterDisplayName(key)
    local moduleid, mapName = EncounterOfTheWeek.ParseEncounterKey(key)
    local seriesKey = EncounterOfTheWeek.SplitPartKey(key)
    local partName = EncounterOfTheWeek.PartName(key)
    local suffix = ""
    if partName ~= nil then
        suffix = " -- " .. partName
    end
    if moduleid == STARTING_MODULE then
        return mapName .. suffix
    end
    local entry = m_encounterByKey[seriesKey]
    local moduleName = moduleid
    if entry ~= nil and entry.moduleName ~= nil and entry.moduleName ~= "" then
        moduleName = entry.moduleName
    end
    local title = EncounterOfTheWeek.MapTitle(mapName)
    --a module named after its one encounter would read "X (X)".
    if moduleName == title then
        return title .. suffix
    end
    return string.format("%s (%s)%s", title, moduleName, suffix)
end

--The hover text on a part the author marked "Coming soon" without saying more.
local COMING_SOON_TEXT = "Coming soon."

--The parts of a series map from its module record's eotwEncounters entry:
--{ {number, title, townGate, mapName, comingSoon}, ... } sorted by number, or
--nil when the map is not a series. mapName is set for a part on its own part
--map. Parts listed under comingSoonParts come back as locked placeholders
--whose comingSoon field is the hover text.
--Read leniently: Firebase may hand a list back keyed "0", "1".
local function ReadSeriesParts(story)
    if type(story) ~= "table" then
        return nil
    end
    local parts = {}
    local numbers = {}
    for _, p in pairs(type(story.parts) == "table" and story.parts or {}) do
        if type(p) == "table" and tonumber(p.number) ~= nil then
            local title, townGate = nil, nil
            if type(p.title) == "string" and p.title ~= "" then
                title = p.title
            end
            if type(p.townGate) == "string" and p.townGate ~= "" then
                townGate = p.townGate
            end
            local mapName = nil
            if type(p.map) == "string" and p.map ~= "" then
                mapName = p.map
            end
            local number = math.floor(tonumber(p.number) or 0)
            numbers[number] = true
            parts[#parts+1] = { number = number, title = title, townGate = townGate, mapName = mapName }
        end
    end
    for _, p in pairs(type(story.comingSoonParts) == "table" and story.comingSoonParts or {}) do
        local number = type(p) == "table" and tonumber(p.number) or nil
        if number ~= nil and not numbers[math.floor(number)] then
            local title = nil
            if type(p.title) == "string" and p.title ~= "" then
                title = p.title
            end
            local text = COMING_SOON_TEXT
            if type(p.text) == "string" and p.text ~= "" then
                text = p.text
            end
            parts[#parts+1] = { number = math.floor(number), title = title, comingSoon = text }
        end
    end
    if #parts == 0 then
        return nil
    end
    table.sort(parts, function(a, b) return a.number < b.number end)
    return parts
end

--A series' part n as the pool lists it ({number, title, townGate}), or nil.
--key may name any part of the series; n defaults to the part it names.
function EncounterOfTheWeek.GetPart(key, n)
    local seriesKey, part = EncounterOfTheWeek.SplitPartKey(key)
    local entry = m_encounterByKey[seriesKey or ""]
    if entry == nil or entry.parts == nil then
        return nil
    end
    for _, p in ipairs(entry.parts) do
        if p.number == (n or part) then
            return p
        end
    end
    return nil
end

--"Part 2: The Ossuary" (or "Part 2") for a key naming a series' part --
--part 1 too, which shares the series' bare key -- else nil (not a series,
--or the pool has not loaded).
function EncounterOfTheWeek.PartName(key)
    local p = EncounterOfTheWeek.GetPart(key)
    if p == nil then
        return nil
    end
    if p.title ~= nil then
        return string.format("Part %d: %s", p.number, p.title)
    end
    return string.format("Part %d", p.number)
end

--May this account form a party for this key? Part 1 of a series (and any
--encounter that is not a series) always; part n once the account has won
--part n-1 ON THE SAME BOARD: at the Town Gate any of its heroes' wins
--(EotwRoster.AccountCompleted), in the Proving Pits its practice wins
--(EotwRoster.PracticeWon). A Proving Pits win does not carry over to the Gate.
--A part marked "Coming soon" stays locked for everyone.
--Returns true, or false + the reason to show.
function EncounterOfTheWeek.PartUnlocked(key)
    local seriesKey, part = EncounterOfTheWeek.SplitPartKey(key)
    local entry = EncounterOfTheWeek.GetPart(key)
    if entry ~= nil and entry.comingSoon ~= nil then
        return false, entry.comingSoon
    end
    if part <= 1 then
        return true
    end
    if EncounterOfTheWeek.PartWon(EncounterOfTheWeek.PartKey(seriesKey, part - 1)) then
        return true
    end
    return false, string.format("Win Part %d to unlock this part.", part - 1)
end

--Has this account won this part on the board it is played from?
function EncounterOfTheWeek.PartWon(key)
    local seriesKey = EncounterOfTheWeek.SplitPartKey(key)
    if EncounterOfTheWeek.IsDangerRoomEncounter(seriesKey) then
        return EotwRoster.PracticeWon(key)
    end
    return EotwRoster.AccountCompleted(key)
end

--The part a party for this series should set out for by default: the first
--unlocked part this account has not won yet, else the last unlocked one. key
--may name any part; returns a part key (key itself when not a series).
function EncounterOfTheWeek.NextPartKey(key)
    local seriesKey = EncounterOfTheWeek.SplitPartKey(key)
    local entry = m_encounterByKey[seriesKey or ""]
    if entry == nil or entry.parts == nil then
        return key
    end
    local last = seriesKey
    for _, p in ipairs(entry.parts) do
        local partKey = EncounterOfTheWeek.PartKey(seriesKey, p.number)
        if not EncounterOfTheWeek.PartUnlocked(partKey) then
            break
        end
        last = partKey
        if not EncounterOfTheWeek.PartWon(partKey) then
            return partKey
        end
    end
    return last
end

--Author previews: moduleid -> { maps, eotwEncounters }, shown in town in
--place of what the module has published. Nothing is uploaded, and it is
--gone when the app restarts.
local m_stagedModules = {}

--The pool entries one module record offers, default map first, then by title.
local function ModuleEncounters(info, moduleid)
    local official = moduleid == STARTING_MODULE
    local summary, published, name, author = nil, nil, nil, nil
    pcall(function() summary = info.contentSummary end)
    pcall(function() published = info.publishingProperties.eotwEncounters end)
    local staged = m_stagedModules[moduleid]
    if staged ~= nil then
        summary = { { type = "map", items = staged.maps or {} } }
        published = staged.eotwEncounters
    end
    pcall(function() name = info.name end)
    pcall(function() author = info.authorid end)
    --published from this account: its creator reads the Proving Pits feedback.
    local ours = false
    pcall(function() ours = info.ourModule == true end)

    local result = {}
    local seen = {}
    for _,entry in ipairs(summary or {}) do
        local kind = string.lower(tostring(entry.type or ""))
        if kind == "map" or kind == "maps" then
            for _,mapItem in ipairs(entry.items or {}) do
                --A part map is listed once, under its series' name.
                local item = EncounterOfTheWeek.SplitPartMapName(mapItem) or mapItem
                if EncounterOfTheWeek.IsEncounterMapName(item) and not seen[item] then
                    seen[item] = true
                    local townGate = nil
                    local story = type(published) == "table" and published[item] or nil
                    if type(story) == "table" and type(story.townGate) == "string" and story.townGate ~= "" then
                        townGate = story.townGate
                    end
                    --a series lists its parts (nil otherwise).
                    local parts = ReadSeriesParts(story)
                    result[#result+1] = {
                        key = EncounterOfTheWeek.EncounterKey(moduleid, item),
                        moduleid = moduleid,
                        mapName = item,
                        title = EncounterOfTheWeek.MapTitle(item),
                        official = official,
                        moduleName = name,
                        author = author,
                        townGate = townGate,
                        ours = ours,
                        parts = parts,
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

--Developer tool: show a module in town as it would look after its next
--publish. Pass nil to clear it. Parties still play the published version.
function EncounterOfTheWeek.StagePoolModule(moduleid, staged)
    if not dmhub.GetSettingValue("dev") then
        printf("EotW: staging a module preview needs developer mode")
        return
    end
    m_stagedModules[moduleid] = staged
    EncounterOfTheWeek.RefreshPool()
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

--The pool entry for a key, or nil (not loaded, pulled, or unknown). A
--series' part key gives the series' entry.
function EncounterOfTheWeek.GetEncounter(key)
    if key == nil or key == "" then
        key = ENCOUNTER_MAP_NAME
    end
    return m_encounterByKey[EncounterOfTheWeek.SplitPartKey(key)]
end

--Every community EotW module the last fetch saw, pulled ones included:
--a list of { moduleid, name, author, pulled, count }.
function EncounterOfTheWeek.GetPoolModules()
    return m_poolModules
end

--An encounter's backstory (its script's "# Town Gate" text), or nil. key is
--an encounter key as the party record carries it; "" or nil is the default map.
--A series' part has its own; the bare key is part 1's.
function EncounterOfTheWeek.GetTownGateText(key)
    local part = EncounterOfTheWeek.GetPart(key)
    if part ~= nil then
        return part.townGate
    end
    local entry = EncounterOfTheWeek.GetEncounter(key)
    if entry == nil then
        return nil
    end
    return entry.townGate
end

--- the week's schedule ------------------------------------------------
--One encounter at a time is THE Encounter of the Week. The Town Gate offers
--it, and the past ones, and nothing else. Every other community encounter in
--the pool plays in the Proving Pits, for practice. Official-module maps that
--are not on the schedule (Angry Dwarves) are retired: offered nowhere. The
--schedule lives in the City (/city/week = {week, current, past, since}, keys
--as above); an admin rotates it with EncounterOfTheWeek.SetWeek, from the
--Codex menu's "Encounter of the Week..." dialog, or with the city's
--/admin/city/blackbottom/week route.

--A key as the schedule stores it: "" / nil is the official default map, and
--a series' part is its series (the schedule holds whole series).
local function NormalizeKey(key)
    if key == nil or key == "" then
        return ENCOUNTER_MAP_NAME
    end
    return (EncounterOfTheWeek.SplitPartKey(key))
end

--The schedule, or nil before the city has one (or before the town connected).
function EncounterOfTheWeek.GetWeek()
    local conn = EotwRoster.Connection()
    if conn == nil then
        return nil
    end
    local week = conn:GetPath("/city/week")
    if type(week) ~= "table" or type(week.current) ~= "string" or week.current == "" then
        return nil
    end
    return week
end

--This week's encounter key, or nil.
function EncounterOfTheWeek.CurrentEncounterKey()
    local week = EncounterOfTheWeek.GetWeek()
    if week == nil then
        return nil
    end
    return week.current
end

--The earlier Encounters of the Week, newest first.
function EncounterOfTheWeek.PastEncounterKeys()
    local week = EncounterOfTheWeek.GetWeek()
    local result = {}
    if week ~= nil and type(week.past) == "table" then
        for _,key in ipairs(week.past) do
            if type(key) == "string" and key ~= week.current then
                result[#result+1] = key
            end
        end
    end
    return result
end

--Is this the Encounter of the Week, or a past one?
function EncounterOfTheWeek.IsScheduledEncounter(key)
    key = NormalizeKey(key)
    if key == EncounterOfTheWeek.CurrentEncounterKey() then
        return true
    end
    for _,past in ipairs(EncounterOfTheWeek.PastEncounterKeys()) do
        if past == key then
            return true
        end
    end
    return false
end

--Does this encounter play in the Proving Pits (a community encounter that
--has never been an Encounter of the Week)?
function EncounterOfTheWeek.IsDangerRoomEncounter(key)
    local moduleid = EncounterOfTheWeek.ParseEncounterKey(key)
    return moduleid ~= STARTING_MODULE and not EncounterOfTheWeek.IsScheduledEncounter(key)
end

--The pool's Proving Pits encounters, grouped by module as the pool lists them.
function EncounterOfTheWeek.GetDangerRoomEncounters()
    local result = {}
    for _,entry in ipairs(EncounterOfTheWeek.GetEncounters() or {}) do
        if EncounterOfTheWeek.IsDangerRoomEncounter(entry.key) then
            result[#result+1] = entry
        end
    end
    return result
end

--An encounter's title ("Goblin Ambush"), whether or not the pool lists it.
function EncounterOfTheWeek.EncounterTitle(key)
    local entry = EncounterOfTheWeek.GetEncounter(key)
    if entry ~= nil then
        return entry.title
    end
    local _, mapName = EncounterOfTheWeek.ParseEncounterKey(key)
    return EncounterOfTheWeek.MapTitle(mapName)
end

--"From the module <name> by <author>" for a community encounter, else nil.
function EncounterOfTheWeek.EncounterCredit(key)
    local entry = EncounterOfTheWeek.GetEncounter(key)
    if entry == nil or entry.official then
        return nil
    end
    local credit = string.format("From the module %s", entry.moduleName or entry.moduleid)
    if entry.author ~= nil and entry.author ~= "" then
        credit = credit .. " by " .. entry.author
    end
    return credit
end

--One request to the city: over the town's connection while the town is
--open, otherwise over a short-lived connection of its own (so the admin
--calls below also work from a game, or over MCP from a script or skill).
--callback(ok, resultOrMessage).
local function CityRequest(action, args, callback)
    local conn = EotwRoster.Connection()
    if conn ~= nil and conn.connected then
        conn:Request{
            action = action,
            args = args,
            success = function(result) callback(true, result) end,
            error = function(message) callback(false, message) end,
        }
        return
    end
    local lobbiesApi = rawget(_G, "lobbies")
    if lobbiesApi == nil then
        callback(false, "this build has no lobbies API")
        return
    end
    local own = lobbiesApi:Connect(LOBBY_ID, EotwRoster.CityOptions())
    dmhub.Coroutine(function()
        --requests fail while the connection is still opening; give it ~30s.
        for _ = 1, 300 do
            if mod.unloaded or own.connected then
                break
            end
            coroutine.yield(0.1)
        end
        if mod.unloaded or not own.connected then
            own:Disconnect()
            callback(false, "could not reach the city")
            return
        end
        own:Request{
            action = action,
            args = args,
            success = function(result)
                own:Disconnect()
                callback(true, result)
            end,
            error = function(message)
                own:Disconnect()
                callback(false, message)
            end,
        }
    end)
end

--Admin: make `key` the Encounter of the Week. The current one moves to the
--past and the week's nominations start over (the city's set-week, which
--checks the caller is a city admin). callback(ok, resultOrMessage), optional.
function EncounterOfTheWeek.SetWeek(key, callback)
    CityRequest("set-week", { current = NormalizeKey(key) }, function(ok, result)
        if ok then
            printf("EotW: the Encounter of the Week is now %s", NormalizeKey(key))
        else
            printf("EotW: could not set the Encounter of the Week: %s", tostring(result))
        end
        if callback ~= nil then
            callback(ok, result)
        end
    end)
end

--Admin: the weekly assessment from the city: { week, encounters = {
--{encounter, up, down, plays, feedback = {{name, userid, vote, feedback, at}}} },
--nominations = { {encounter, count, userids} } }. callback(ok, reportOrMessage).
function EncounterOfTheWeek.DangerReport(callback)
    CityRequest("danger-report", nil, callback)
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

--Pregens from the player's Hero modules (see "Hero module pregens" below).
--nil until loaded; then a sorted list of {id, name, className, ancestry, level, source}.
local m_heroPregens = nil
local m_heroPregenTokens = {}
--moduleid -> {token, version}: one of its pregens, to tell when its art needs registering again.
local m_heroPregenArtSample = {}
--the installed Hero modules the cache was built from (InstalledHeroModulesKey).
local m_heroPregensKey = nil
local m_heroPregensFetching = false
local CacheHeroModulePregens

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

--nil while unavailable/loading; otherwise the {id, name, className, ...}
--list: the week's official pregens, then those from the player's Hero
--modules (which carry source = the module's name).
function EncounterOfTheWeek.GetPregens()
    EncounterOfTheWeek.CachePregens()
    CacheHeroModulePregens()
    if m_pregens == nil then
        return nil
    end
    if m_heroPregens == nil or #m_heroPregens == 0 then
        return m_pregens
    end
    local result = {}
    for _, entry in ipairs(m_pregens) do
        result[#result+1] = entry
    end
    for _, entry in ipairs(m_heroPregens) do
        result[#result+1] = entry
    end
    return result
end

--── Hero module pregens ──────────────────────────────────────────────
--Heroes shipped inside the player's Hero modules (classes and ancestries
--from their inventory, see HeroModules.lua) are pregens too. Only modules
--actually installed in the lobby count: that is every switched-on module the
--player may use, and only once its code (if any) is approved -- so a pregen's
--class is always there to recruit it with. Each comes from the snapshot of the
--INSTALLED version (a newer one may still await review), and the list is
--rebuilt whenever that set changes.

--"fullid@version" of every Hero module installed in the lobby, sorted.
local function InstalledHeroModulesKey()
    local parts = {}
    for _, info in ipairs(module.GetLoadedModules()) do
        if info.isHeroModule and info.installedVersion ~= nil then
            parts[#parts+1] = string.format("%s@%s", info.fullid, info.installedVersion)
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

CacheHeroModulePregens = function()
    if not dmhub.isLobbyGame or module.DownloadModuleSnapshot == nil then
        return
    end

    local key = InstalledHeroModulesKey()
    if m_heroPregensFetching or key == m_heroPregensKey then
        --built from this set: just check the art is still registered
        --(entering a game clears module art; the snapshot download redoes it).
        for moduleid, sample in pairs(m_heroPregenArtSample) do
            local portrait = nil
            pcall(function() portrait = sample.token.offTokenPortrait end)
            if IsUnresolvableAssetId(portrait) then
                m_heroPregenArtSample[moduleid] = nil
                module.DownloadModuleSnapshot{ moduleid = moduleid, version = sample.version, success = function() end, failure = function() end }
            end
        end
        return
    end

    m_heroPregensFetching = true
    local result = {}
    local tokens = {}
    local artSamples = {}
    local pending = 0
    local Finish = function()
        if pending > 0 then
            return
        end
        table.sort(result, function(a,b) return a.name < b.name end)
        m_heroPregens = result
        m_heroPregenTokens = tokens
        m_heroPregenArtSample = artSamples
        m_heroPregensKey = key
        m_heroPregensFetching = false
    end

    for _, info in ipairs(module.GetLoadedModules()) do
        if info.isHeroModule and info.installedVersion ~= nil then
            pending = pending + 1
            local fullid = info.fullid
            local version = info.installedVersion
            local source = info.name or fullid
            module.DownloadModuleSnapshot{
                moduleid = fullid,
                version = version,
                success = function(snapshot)
                    for charid, tok in pairs(snapshot.characters or {}) do
                        local isHero = false
                        pcall(function() isHero = tok.properties:IsHero() == true end)
                        if isHero then
                            tokens[charid] = tok
                            artSamples[fullid] = { token = tok, version = version }
                            result[#result+1] = {
                                id = charid,
                                name = tok.name or "Hero",
                                className = GetHeroClassName(tok),
                                ancestry = GetHeroAncestry(tok),
                                level = GetHeroLevel(tok),
                                source = source,
                            }
                        end
                    end
                    pending = pending - 1
                    Finish()
                end,
                failure = function(msg)
                    printf("EotW: could not fetch Hero module %s for its pregens: %s", fullid, tostring(msg))
                    pending = pending - 1
                    Finish()
                end,
            }
        end
    end
    Finish()
end

--The snapshot token for a pregen id, official or from a Hero module (nil
--until its cache is loaded).
function EncounterOfTheWeek.GetPregenToken(id)
    if m_pregenTokens ~= nil and m_pregenTokens[id] ~= nil then
        return m_pregenTokens[id]
    end
    return m_heroPregenTokens[id]
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
    for _,tok in pairs(m_heroPregenTokens) do
        AddToken(tok)
    end

    return result
end

--Town hero portraits that cannot render yet because their asset records
--have not loaded. Town heroes are lobby characters (EotwRoster working
--copies) whose art lives in the lobby's own asset store, so unlike module or
--other players' art these records ARE coming: re-entering the lobby loads
--them a few seconds after the characters. The veil waits for them; any id
--still missing at the veil's deadline is given up on until the codemods
--next reload (i.e. the next return from a game).
local m_abandonedTownPortraits = {}
local function AwaitedTownPortraitIds()
    local result = {}
    for _,tok in ipairs(table.values(dmhub.GetAllCharacters())) do
        pcall(function()
            if rawget(tok.properties, "eotwHero") == true then
                local p = tok.offTokenPortrait
                if IsUnresolvableAssetId(p) and m_abandonedTownPortraits[p] == nil then
                    result[#result+1] = p
                end
            end
        end)
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

    --how long the warmer keeps rescanning for town portrait records (see
    --AwaitedTownPortraitIds): as long as the veil could possibly wait.
    local recordDeadline = dmhub.Time() + VEIL_BUILD_DELAY_SECONDS + VEIL_SETTLE_SECONDS + VEIL_WAIT_MAX_SECONDS

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

            --town portrait records still loading: look again soon, without
            --spending a pass, so their art is warmed under the veil.
            if dmhub.Time() < recordDeadline and #AwaitedTownPortraitIds() > 0 then
                element:ScheduleEvent("warmPortraits", VEIL_WAIT_POLL_SECONDS, passesLeft)
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
    --town hero art whose records are on their way: not settled, however
    --idle the warmer looks (the veil's deadline still bounds the wait).
    if #AwaitedTownPortraitIds() > 0 then
        return false
    end
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

---- Steam invites -------------------------------------------------------
--Any party member can invite Steam friends ("Invite Steam Friends" in the
--party view), and an open party is each member's Steam "Join Game" target.
--Both carry kind "eotw" and payload "<gameid>:<invite code>"; the code is
--what lets a friend into a private party (the city's invite-code action).

local STEAM_INVITE_KIND = "eotw"

--The party invite this player accepted, { gameid, code }, waiting for the
--town screen to join it (TryAcceptInvite inside CreateScreen).
---@type nil|{gameid: string, code: string}
local m_pendingInvite = nil

--Takes an accepted invite from the engine once we are at the titlescreen
--past its splash, and opens the town to act on it. Accepting does not need
--the beta setting: the invite is the way in. Reschedules itself every
--second for the life of this codemod generation.
local function PollSteamInvite()
    if mod.unloaded then
        return
    end
    dmhub.Schedule(1, PollSteamInvite)

    local root = rawget(_G, "CodexTitlescreenRoot")
    if root == nil or not root.valid or root:HasClass("starting-screen") then
        return
    end
    if dmhub.isLobbyGame ~= true or (dmhub.gameLoadingProgress or 0) < 1 then
        return
    end

    local invite = dmhub.TakeSteamInvite()
    if invite == nil then
        return
    end
    local gameid, code = string.match(invite.payload, "^([%w_%-]+):([%w_%-]+)$")
    if invite.kind ~= STEAM_INVITE_KIND or gameid == nil then
        printf("EotW: ignoring a Steam invite we do not understand (%s)", tostring(invite.kind))
        return
    end
    m_pendingInvite = { gameid = gameid, code = code }
    EncounterOfTheWeek.ShowScreen()
end
dmhub.Schedule(1, PollSteamInvite)

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
            --everything in the screen, including the back button (which
            --lands under the titlescreen link that opened us). The
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

            --a town portrait record that has not come by now is not coming;
            --never hold a later veil for it.
            for _,id in ipairs(AwaitedTownPortraitIds()) do
                m_abandonedTownPortraits[id] = true
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
                AnalyticsTownOpened()
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

--The town screen, for panels that mount over the whole town (the EotW hero
--sheet), or nil while it is not up.
---@return Panel|nil
function EncounterOfTheWeek.TownScreen()
    if EncounterOfTheWeek.IsScreenOpen() then
        return m_screen
    end
    return nil
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
        {
            text = "Encounter of the Week...",
            icon = "phosphor/trophy-fill.png",
            click = function()
                EncounterOfTheWeek.ShowWeekDialog()
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
            text = "Community modules published Public or Unlisted as Encounter of the Week. A pulled module's encounters are not offered in the Proving Pits (or at the Gate, if one was an Encounter of the Week); games already formed keep playing it.",
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

--Admin: the weekly assessment and the rotation. Lists every encounter in the
--pool that is not this week's, Proving Pits votes, plays and feedback beside
--each, best net vote first, each with "Make Encounter of the Week" (a second
--click confirms). Mounted over the town screen.
function EncounterOfTheWeek.ShowWeekDialog()
    if m_screen == nil or not m_screen.valid then
        return
    end

    local dlg
    local listPanel
    local headerLabel
    local statusLabel

    local SetStatus = function(text, isError)
        if statusLabel ~= nil and statusLabel.valid then
            statusLabel.text = text or ""
            statusLabel.selfStyle.color = cond(isError, "#ff8888", Styles.textColor)
        end
    end

    local Small = function(text, color)
        return gui.Label{
            text = text,
            fontSize = 14,
            color = color or "#b8ad96",
            width = "100%",
            height = "auto",
            textWrap = true,
        }
    end

    local Rebuild
    Rebuild = function(report)
        if listPanel == nil or not listPanel.valid then
            return
        end
        local current = EncounterOfTheWeek.CurrentEncounterKey()
        local past = EncounterOfTheWeek.PastEncounterKeys()
        local pastTitles = {}
        for _,key in ipairs(past) do
            pastTitles[#pastTitles+1] = EncounterOfTheWeek.EncounterTitle(key)
        end
        if headerLabel ~= nil and headerLabel.valid then
            local week = EncounterOfTheWeek.GetWeek()
            if current == nil then
                headerLabel.text = "No Encounter of the Week is set yet. Choose one below."
            else
                headerLabel.text = string.format("Week %s: <b>%s</b>\nPast: %s", tostring(week ~= nil and week.week or "?"),
                    EncounterOfTheWeek.EncounterTitle(current), cond(#pastTitles > 0, table.concat(pastTitles, ", "), "none"))
            end
        end

        local byKey = {}
        for _,e in ipairs(report ~= nil and report.encounters or {}) do
            byKey[e.encounter] = e
        end
        local entries = {}
        for _,entry in ipairs(EncounterOfTheWeek.GetEncounters() or {}) do
            if entry.key ~= current then
                entries[#entries+1] = entry
            end
        end
        table.sort(entries, function(a, b)
            local ea, eb = byKey[a.key], byKey[b.key]
            local va = ea ~= nil and ((ea.up or 0) - (ea.down or 0)) or 0
            local vb = eb ~= nil and ((eb.up or 0) - (eb.down or 0)) or 0
            if va ~= vb then
                return va > vb
            end
            return a.title < b.title
        end)

        local rows = {}
        for _,entry in ipairs(entries) do
            local stats = byKey[entry.key]
            local kind = "Proving Pits"
            if EncounterOfTheWeek.IsScheduledEncounter(entry.key) then
                kind = "Past Encounter of the Week"
            elseif entry.official then
                kind = "Official module (retired)"
            end
            local details = {
                gui.Label{
                    text = entry.title,
                    fontSize = 20,
                    bold = true,
                    color = Styles.textColor,
                    width = "100%",
                    height = "auto",
                },
                Small(string.format("%s -- %s%s", kind, entry.moduleName or entry.moduleid,
                    cond(entry.author ~= nil and entry.author ~= "", " by " .. tostring(entry.author), ""))),
                Small(string.format("%d up, %d down, %d play%s",
                    stats ~= nil and stats.up or 0, stats ~= nil and stats.down or 0,
                    stats ~= nil and stats.plays or 0, cond(stats ~= nil and stats.plays == 1, "", "s")), "#e6dcc6"),
            }
            for _,f in ipairs(stats ~= nil and stats.feedback or {}) do
                if f.feedback ~= nil and f.feedback ~= "" or (f.vote or 0) ~= 0 then
                    local vote = cond((f.vote or 0) > 0, "up", cond((f.vote or 0) < 0, "down", "no vote"))
                    details[#details+1] = Small(string.format("  %s (%s): %s", f.name or "?", vote, f.feedback or ""), "#d9d0bd")
                end
            end
            rows[#rows+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 6,
                gui.Panel{
                    width = "100%-230",
                    height = "auto",
                    flow = "vertical",
                    valign = "center",
                    children = details,
                },
                gui.Button{
                    text = "Make Encounter of the Week",
                    fontSize = 15,
                    width = 220,
                    height = 38,
                    valign = "center",
                    data = { confirming = false },
                    resetConfirm = function(element)
                        element.data.confirming = false
                        element.text = "Make Encounter of the Week"
                    end,
                    click = function(element)
                        if not element.data.confirming then
                            element.data.confirming = true
                            element.text = "Click again to confirm"
                            element:ScheduleEvent("resetConfirm", 4)
                            return
                        end
                        SetStatus("Rotating the week...")
                        EncounterOfTheWeek.SetWeek(entry.key, function(ok, result)
                            if not ok then
                                SetStatus("Could not set the week: " .. tostring(result), true)
                                return
                            end
                            SetStatus(entry.title .. " is now the Encounter of the Week.")
                            dmhub.Schedule(0.5, function()
                                if dlg ~= nil and dlg.valid then
                                    EncounterOfTheWeek.DangerReport(function(okReport, newReport)
                                        Rebuild(cond(okReport, newReport, nil))
                                    end)
                                end
                            end)
                        end)
                    end,
                },
            }
        end
        if #rows == 0 then
            rows[1] = Small("The pool holds no other encounters.")
        end
        listPanel.children = rows
    end

    dlg = gui.Panel{
        floating = true,
        width = 860,
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
            text = "Encounter of the Week",
            fontSize = 32,
            bold = true,
            color = Styles.textColor,
            width = "auto",
            height = "auto",
            halign = "center",
            vmargin = 8,
        },
        gui.Label{
            text = "",
            fontSize = 17,
            color = Styles.textColor,
            width = "100%",
            height = "auto",
            textAlignment = "center",
            textWrap = true,
            vmargin = 4,
            create = function(element)
                headerLabel = element
            end,
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            maxHeight = 600,
            vscroll = true,
            flow = "vertical",
            vmargin = 8,
            rpad = 12,
            borderBox = true,
            create = function(element)
                listPanel = element
            end,
        },
        gui.Label{
            text = "Loading the week's report...",
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
        EncounterOfTheWeek.DangerReport(function(ok, report)
            if dlg == nil or not dlg.valid then
                return
            end
            if ok then
                SetStatus("")
                Rebuild(report)
            else
                SetStatus("Could not load the report: " .. tostring(report), true)
                Rebuild(nil)
            end
        end)
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
        m_conn = lobbiesApi:Connect(LOBBY_ID, EotwRoster.CityOptions())
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
    local chatMessagesPanel = nil
    local presenceLabel = nil
    local statusLabel = nil
    local chatErrorLabel = nil
    local chatTitleLabel = nil
    local chatTabRow = nil
    local chatInput = nil

    --whether the chat drawer is open, and per channel the last-viewed mark
    --taken when it opened: newer messages sit below the New divider until
    --the drawer closes (or we post).
    local m_chatOpen = false
    local m_chatDividers = {}
    --follow new messages to the bottom unless the player has scrolled up
    --to read history; reset on opening the drawer or changing channel.
    local m_chatStickBottom = true
    local m_chatChannel = nil
    --in a party view the drawer has a Town Chat and a Game Chat tab; this
    --is the one showing ("town" or "game"). Entering a party keeps it.
    local m_chatTab = "town"

    --The two party boards: the Town Gate's ("gate": the Encounter of the
    --Week and the past ones) and the Proving Pits' ("danger"). Each is the
    --body of its location's scene; both are built once and kept, and
    --RefreshGames renders each. Per board: { list, title, error, controls,
    --creatorButton, pastButton, cardWidth }.
    local PARTY_MODES = { "gate", "danger" }
    local m_partyUI = { gate = {}, danger = {} }

    local resultPanel = nil
    ---@type fun(key: string, explicitPart?: boolean)
    local ShowCreateDialog = nil
    ---@type fun()
    local ShowPastEncountersDialog = nil
    ---@type fun()
    local ShowCreatorFeedbackDialog = nil
    --Proving Pits votes from the city's danger-stats, { [key] = {up, down,
    --plays} }.
    local m_dangerStats = {}

    --When set, the games area shows this game's lobby view (slots + your
    --heroes) instead of the games list, and the chat drawer gains a tab
    --for the game's private chat channel.
    local m_viewGameid = nil

    --The hero-card keys ("userid|kind|id") rendered by the last game-view
    --build. nil right after opening a view, so the first build renders
    --without animation; afterwards any hero not in this set is NEW and its
    --card plays the grow + fade-in entrance.
    local m_knownHeroCards = nil

    --The party whose host is choosing how long to blow the horn for (the
    --button row shows the 2/5/10 minute choices instead), or nil.
    local m_hornPickerFor = nil

    --Milliseconds the party's horn still sounds, or 0. While it sounds the
    --server refuses Begin unless every slot is filled.
    local HornRemainingMs = function(record)
        if type(record.hornUntil) ~= "number" then
            return 0
        end
        return math.max(0, record.hornUntil - dmhub.serverTimeMilliseconds)
    end

    local FormatCountdown = function(ms)
        local secs = math.ceil(ms / 1000)
        return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
    end

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
        for _,mode in ipairs(PARTY_MODES) do
            local label = m_partyUI[mode].error
            if label ~= nil and label.valid then
                label:FireEvent("showError", message)
            end
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

    --True when a channel holds someone else's message newer than our
    --last look at it.
    local ChatUnread = function(channel, chat)
        if chat == nil then
            return false
        end
        local viewed = dmhub.GetSettingValue("eotw:chatlastviewed")
        local seen = type(viewed) == "table" and viewed[channel] or 0
        for _,msg in pairs(chat) do
            if type(msg) == "table" and type(msg.ts) == "number" and msg.ts > seen and msg.userid ~= dmhub.loginUserid then
                return true
            end
        end
        return false
    end

    --One of the chat drawer's two tabs; a red NEW marks unread messages.
    local ChatTab = function(tab, text)
        return gui.Label{
            classes = { "chatTab" },
            bgimage = "panels/square.png",
            text = text,
            fontSize = 20,
            bold = true,
            color = Styles.textColor,
            textAlignment = "center",
            width = "50%",
            height = "100%",
            refreshTab = function(element, info)
                element:SetClass("selected", info.selected == tab)
                element.text = cond(info.unread[tab], text .. " <color=#f23f43><size=70%>NEW</size></color>", text)
            end,
            press = function(element)
                if m_chatTab ~= tab then
                    m_chatTab = tab
                    RefreshChat()
                end
            end,
        }
    end

    --A board's scene card is narrow over its lists, so the art (the Gate's
    --tower, the Proving Pits' monster) stays clear, and wide in a party view,
    --where a full party's six hero cards need one row. The list panel sits in
    --the board, which sits in the card.
    local CARD_WIDTH_LIST = { gate = 1000, danger = 900 }
    local CARD_WIDTH_PARTY = 1240
    local SetCardWidth = function(mode, width)
        local ui = m_partyUI[mode]
        if width == ui.cardWidth or ui.list == nil or not ui.list.valid then
            return
        end
        local body = ui.list.parent
        local card = body ~= nil and body.parent or nil
        if card ~= nil then
            ui.cardWidth = width
            card.selfStyle.width = width
        end
    end

    --A small cream heading over a group of rows in a location's card.
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

    --A chat message's time: "3:42 PM" today, "Oct 19, 3:42 PM" before.
    local FormatChatTime = function(ms)
        local secs = math.floor(ms / 1000)
        local t = os.date("*t", secs) --[[@as osdate]]
        local now = os.date("*t") --[[@as osdate]]
        local hour = t.hour % 12
        if hour == 0 then
            hour = 12
        end
        local clock = string.format("%d:%02d %s", hour, t.min, cond(t.hour < 12, "AM", "PM"))
        if t.year == now.year and t.yday == now.yday then
            return clock
        end
        return string.format("%s, %s", os.date("%b %d", secs), clock)
    end

    --Chat text shown as typed: rich-text tags in it are not applied.
    local ChatPlain = function(text)
        return "<noparse>" .. string.gsub(text, "</?[nN][oO][pP][aA][rR][sS][eE]>", "") .. "</noparse>"
    end

    --The red line between unread chat messages and those already seen.
    local ChatNewDivider = function()
        local red = "#f23f43"
        return gui.Panel{
            width = "96%",
            height = 18,
            halign = "left",
            vmargin = 6,
            flow = "horizontal",
            gui.Panel{
                bgimage = "panels/square.png",
                bgcolor = red,
                width = "100%-52",
                height = 1,
                valign = "center",
            },
            gui.Label{
                text = "NEW",
                fontSize = 12,
                bold = true,
                color = "#ffffff",
                bgimage = "panels/square.png",
                bgcolor = red,
                width = 44,
                height = 16,
                lmargin = 8,
                valign = "center",
                textAlignment = "center",
            },
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
            --a dying hero must rest at the inn before setting out again.
            if hero.status ~= "fallen" and not busy[hero.heroid] and not EotwRoster.IsDying(hero.heroid) then
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

    --Give up an EotW game for good. The eotwAbandonGame cloud function
    --deletes it (and releases its storage) only when no other member still
    --holds it in their Encounter of the Week slot -- whoever we are, owner or
    --not, since only the server may delete a game for a non-owner. Then we
    --leave it: off its player list, account slot cleared.
    local AbandonGame = function(gameid, gameinfo)
        local function Leave()
            if gameinfo ~= nil then
                gameinfo:Leave()
            end
        end
        net.Post{
            url = dmhub.cloudFunctionsBaseUrl .. "/eotwAbandonGame",
            data = { gameid = gameid },
            success = function(data)
                if type(data) == "table" and data.ok then
                    printf("EotW: abandoned game %s is deleted (storage released: %s)", gameid, tostring(data.released))
                else
                    --usually "Other players still have this game": they play on.
                    printf("EotW: abandoned game %s stays for the others: %s", gameid,
                        tostring(type(data) == "table" and data.error or "invalid response"))
                end
                Leave()
            end,
            error = function(msg)
                printf("EotW: could not reach eotwAbandonGame for %s: %s", gameid, tostring(msg))
                Leave()
            end,
        }
    end

    --Destroy/leave the EotW game we had before entering a new one, and
    --drop any lobby roster record we still hold for it.
    --opts.abandon: walking away from a game others may still be playing --
    --AbandonGame above, rather than the owner deleting it from under them.
    --Without it (a concluded game), the owner deletes and others leave.
    local DestroyPreviousGame = function(prevGameid, opts)
        opts = opts or {}
        if prevGameid == nil then
            return
        end
        --analytics: a run this player still had open in it ends here.
        pcall(EotwAnalytics.CloseRun, prevGameid, opts.how or cond(opts.abandon, "replaced", "cleanup"))
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
            if opts.abandon then
                AbandonGame(prevGameid, gameinfo)
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
    --the previous one (one EotW game per account). inviteCode (from a Steam
    --invite) is what admits us to a private game.
    ---@param gameid string
    ---@param inviteCode? string
    local JoinGame = function(gameid, inviteCode)
        if m_conn == nil then
            return
        end
        m_conn:Request{
            action = "join-game",
            args = { gameid = gameid, invite = inviteCode },
            success = function()
                local joined = GetGameRecord(gameid)
                EotwAnalytics.Track("eotw_party_join", {
                    runid = gameid,
                    encounter = joined ~= nil and joined.encounter or nil,
                    board = joined ~= nil and type(joined.encounter) == "string" and cond(EncounterOfTheWeek.IsDangerRoomEncounter(joined.encounter), "pits", "gate") or nil,
                })
                local prev = EotwSlotGameid()
                EngineJoinEotw(gameid)
                if prev ~= nil and prev ~= gameid then
                    DestroyPreviousGame(prev, { abandon = true })
                end
                ClaimActiveHeroes(gameid, prev)
                if OpenGameView ~= nil then
                    OpenGameView(gameid)
                end
            end,
            error = ShowGamesError,
        }
    end

    --Invite codes of parties we belong to, by gameid (see the Steam invites
    --note above CreateScreen). A code never changes, so one ask per party.
    ---@type table<string, string>
    local m_inviteCodes = {}
    ---@type table<string, boolean>
    local m_inviteCodeAsked = {}

    --Calls fn(code) with the party's invite code, asking the city for it the
    --first time. onError gets the city's message if it refuses.
    ---@param gameid string
    ---@param fn fun(code: string)
    ---@param onError? fun(message: string)
    local WithInviteCode = function(gameid, fn, onError)
        if m_inviteCodes[gameid] ~= nil then
            fn(m_inviteCodes[gameid])
            return
        end
        if m_conn == nil then
            return
        end
        m_inviteCodeAsked[gameid] = true
        m_conn:Request{
            action = "invite-code",
            args = { gameid = gameid },
            success = function(result)
                if type(result) == "table" and type(result.code) == "string" then
                    m_inviteCodes[gameid] = result.code
                    fn(result.code)
                end
            end,
            error = function(message)
                --a later push may try again (the party may have reopened).
                m_inviteCodeAsked[gameid] = nil
                if onError ~= nil then
                    onError(message)
                end
            end,
        }
    end

    --The Steam overlay's invite dialog for one of our parties.
    local InviteSteamFriends = function(gameid)
        WithInviteCode(gameid, function(code)
            if not dmhub.InviteViaSteam(STEAM_INVITE_KIND, gameid .. ":" .. code) then
                ShowGamesError("Steam's overlay is not available, so friends cannot be invited from here. Check that the Steam overlay is enabled.")
                return
            end
            EotwAnalytics.Track("eotw_party_invite", { runid = gameid })
        end, ShowGamesError)
    end

    --" -- Encounter: <title>" for a roster record whose host chose an
    --encounter; "" when the record has no choice (the module's default map).
    local EncounterSuffix = function(record)
        if record ~= nil and type(record.encounter) == "string" and record.encounter ~= "" then
            return " -- " .. EncounterOfTheWeek.EncounterDisplayName(record.encounter)
        end
        return ""
    end

    --Which board lists a party: the Proving Pits' for a Proving Pits
    --encounter, the Gate's for everything else.
    local PartyMode = function(record)
        if record ~= nil and EncounterOfTheWeek.IsDangerRoomEncounter(record.encounter) then
            return "danger"
        end
        return "gate"
    end

    --What the Proving Pits mean for the heroes, wherever a party forms there.
    local PRACTICE_TEXT = "The Proving Pits are practice. Heroes earn no Victories, keep no treasure and carry nothing else home. Afterwards you can vote on the encounter and leave feedback for its creator."

    local PracticeNote = function(width)
        return gui.Label{
            text = PRACTICE_TEXT,
            fontSize = 17,
            color = "#ffcf8a",
            width = width,
            height = "auto",
            halign = "center",
            textAlignment = "center",
            textWrap = true,
            vmargin = 8,
        }
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
            --a Proving Pits party: the host stamps the game as practice, so
            --no Victory or treasure is awarded and players debrief it in town.
            practice = encounterMap ~= nil and EncounterOfTheWeek.IsDangerRoomEncounter(encounterMap),
            --members entered alongside the host (see fastLaunchSetting): the
            --game side waits for the host's setup stamp before placing heroes.
            fastLaunch = EncounterOfTheWeek.FastLaunch(),
            --for the game's analytics, which cannot read the schedule.
            week = (EncounterOfTheWeek.GetWeek() or {}).week,
        }
        _G.EotwPendingArrival = arrival

        --analytics: the hand-off from town to game. resume = this player
        --already has a run open in it (going back into a game under way).
        local memberCount = 0
        for _,_ in pairs(members or {}) do
            memberCount = memberCount + 1
        end
        EotwAnalytics.Track("eotw_enter_game", {
            runid = gameid,
            encounter = encounterMap,
            board = encounterMap ~= nil and cond(arrival.practice, "pits", "gate") or nil,
            resume = EotwAnalytics.HasOpenRun(gameid),
            members = memberCount,
            slotsFilled = slotsFilled,
            myHeroes = #myHeroes,
            host = record ~= nil and record.hostUserid == dmhub.loginUserid or nil,
            fastLaunch = arrival.fastLaunch,
        })

        --start directly on the encounter map rather than on the module's
        --first map and travelling. Only for the official module's maps: a
        --Proving Pits module is installed by the host's setup, after load.
        local enterOptions = nil
        if arrival.fastLaunch and encounterMap ~= nil then
            local moduleid, mapName = EncounterOfTheWeek.ParseEncounterKey(encounterMap)
            if moduleid == STARTING_MODULE then
                --a series part on its own map starts there.
                local part = EncounterOfTheWeek.GetPart(encounterMap)
                if part ~= nil and part.mapName ~= nil then
                    mapName = part.mapName
                end
                enterOptions = { startMap = mapName }
            end
        end

        --Hold the loading screen through arrival setup: the engine then runs
        --the callback below BEHIND the loading screen and keeps it up until
        --the game side releases it -- once the opening montage stage is on
        --screen, or right after hero placement when the week has no
        --montage -- so nobody watches the map travel and the tokens pop in.
        --A 20s engine timeout backstops a game side that never releases.
        --Older engines lack the call and simply show the map as before.
        pcall(function() dmhub.HoldLoadingScreen() end)

        EotwProf("lobby:EnterGame called game=%s", gameid)
        local onArrive
        onArrive = function()
            --the engine fires this only once the game has finished loading,
            --so the stamp doubles as the game side's guarantee that running
            --setup -- travelling maps, pasting tokens -- is safe now.
            EotwProf("arrival callback (engine load finished) game=%s", gameid)
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
        end
        lobby:EnterGame(gameid, onArrive, enterOptions)
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
            local fast = EncounterOfTheWeek.FastLaunch()
            if isMember and (record.status == "ready" or (record.status == "launched" and (isHost or fast)))
                    and m_initialGameStatus[gameid] ~= record.status then
                EotwProf("saw status=%s (%s); entering game=%s", tostring(record.status), isHost and "host" or "member", gameid)
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
            --a lineup card opens its Hero in the EotW hero sheet (a teammate's
            --read-only); nothing while a teammate's Hero is still on its way
            click = function()
                if tok == nil then
                    return
                end
                audio.FireSoundEvent("Mouse.Click")
                EotwHeroSheet.Show{ token = tok, charid = tok.charid, context = "town" }
            end,
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

    --The whole game lobby view, as a child list for a board's list panel.
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
        if PartyMode(record) == "danger" then
            children[#children+1] = PracticeNote("86%")
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

        --the horn: a countdown everyone in the party sees while it sounds.
        if isOpen and type(record.hornUntil) == "number" then
            local HornText = function()
                local remaining = HornRemainingMs(record)
                if slotsFilled >= slotsTotal then
                    return "The horn has sounded and the party is full."
                elseif remaining <= 0 then
                    return "The horn has sounded."
                end
                return string.format("The horn sounds! Waiting %s for more heroes to join -- the party can begin when it is full or time runs out.", FormatCountdown(remaining))
            end
            children[#children+1] = gui.Label{
                text = HornText(),
                fontSize = 18,
                color = "#d9b56a",
                width = "90%",
                height = "auto",
                halign = "center",
                textAlignment = "center",
                vmargin = 8,
                thinkTime = 0.5,
                think = function(element)
                    element.text = HornText()
                end,
            }
        end

        --controls. (Adding heroes is the "+" card in the lineup above.)
        local buttons = {}
        --Blow the Horn: host of an open public party, once. The host picks
        --how long to wait; the town chat and Discord hear it.
        local canHorn = isHost and isOpen and record.public == true and record.hornUntil == nil and slotsFilled < slotsTotal
        if canHorn and m_hornPickerFor == gameid then
            for _,minutes in ipairs({ 2, 5, 10 }) do
                buttons[#buttons+1] = gui.Button{
                    text = string.format("Wait %d min", minutes),
                    fontSize = 20,
                    width = 140,
                    height = 44,
                    hmargin = 6,
                    click = function()
                        m_hornPickerFor = nil
                        if m_conn == nil then
                            return
                        end
                        EotwAnalytics.Track("eotw_party_horn", {
                            runid = gameid,
                            encounter = record.encounter,
                            minutes = minutes,
                            slotsFilled = slotsFilled,
                        })
                        m_conn:Request{
                            action = "blow-horn",
                            args = { gameid = gameid, minutes = minutes },
                            error = ShowGamesError,
                        }
                    end,
                }
            end
            buttons[#buttons+1] = gui.Button{
                text = "Cancel",
                fontSize = 20,
                width = 120,
                height = 44,
                hmargin = 6,
                click = function()
                    m_hornPickerFor = nil
                    RefreshGames()
                end,
            }
        elseif canHorn then
            buttons[#buttons+1] = gui.Button{
                text = "Blow the Horn",
                fontSize = 20,
                width = 180,
                height = 44,
                hmargin = 6,
                hover = gui.Tooltip("Call for more heroes in town and on Discord. The party waits until it is full or the time you choose runs out."),
                click = function()
                    m_hornPickerFor = gameid
                    RefreshGames()
                end,
            }
        end
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
        if isHost and isOpen and m_hornPickerFor ~= gameid then
            local canBegin = slotsFilled >= MIN_HEROES and slotsFilled <= slotsTotal
            --the horn holds Begin until the party is full or time is up.
            local HornHolds = function()
                return slotsFilled < slotsTotal and HornRemainingMs(record) > 0
            end
            buttons[#buttons+1] = gui.Button{
                text = "Begin",
                fontSize = 20,
                width = 160,
                height = 44,
                hmargin = 6,
                opacity = cond(canBegin and not HornHolds(), 1, 0.45),
                thinkTime = 0.5,
                think = function(element)
                    element.selfStyle.opacity = cond(canBegin and not HornHolds(), 1, 0.45)
                end,
                click = function()
                    if HornHolds() then
                        ShowGamesError(string.format("The horn is still sounding: the party can begin when it is full or in %s.", FormatCountdown(HornRemainingMs(record))))
                        return
                    end
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
                    EotwProf("Begin pressed (launch-game sent) game=%s", gameid)
                    local memberCount = 0
                    for _,_ in pairs(record.players or {}) do
                        memberCount = memberCount + 1
                    end
                    EotwAnalytics.Track("eotw_party_launch", {
                        runid = gameid,
                        encounter = record.encounter,
                        board = cond(PartyMode(record) == "danger", "pits", "gate"),
                        members = memberCount,
                        slotsFilled = slotsFilled,
                        slotsTotal = slotsTotal,
                    })
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
        --Any member may invite Steam friends while the party is forming; the
        --invite gets them in even when the party is private. Without the
        --Steam overlay (not launched through Steam, or overlay disabled)
        --there is no invite dialog to open, so no button.
        if isMember and isOpen and dmhub.IsSteamOverlayRunning() then
            buttons[#buttons+1] = gui.Button{
                text = "Invite Friends",
                fontSize = 20,
                width = 180,
                height = 44,
                hmargin = 6,
                hover = gui.Tooltip("Invite Steam friends to join this party."),
                click = function()
                    InviteSteamFriends(gameid)
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
                        EotwAnalytics.Track("eotw_party_leave", { runid = gameid, how = "disband", encounter = record.encounter })
                        DestroyPreviousGame(gameid)
                        if CloseGameView ~= nil then
                            CloseGameView()
                        end
                        return
                    end
                    EotwAnalytics.Track("eotw_party_leave", { runid = gameid, how = "leave", encounter = record.encounter })
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

            --Abandon gives up the in-progress game: it is deleted (storage
            --released) only when nobody else still holds it (AbandonGame);
            --otherwise we just leave it to the others. Account slot cleared
            --either way; second click confirms.
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
                    DestroyPreviousGame(resumeGameid, { abandon = true, how = "resume_abandon" })
                    if rowPanel ~= nil and rowPanel.valid then
                        rowPanel:DestroySelf()
                    end
                end,
            },
        }
        return rowPanel
    end

    --A series' parts as a row of chips: "Part 1: The Gate", a tick on each part
    --this account has won (on this board), a lock on each it may not play yet.
    --With onPick, the unlocked chips are buttons (onPick(partKey)) and
    --currentKey's chip is marked; without it they only show progress. An
    --empty, collapsed panel when parts is nil (not a series), so it can sit
    --in a children list.
    local SeriesPartChips = function(seriesKey, parts, currentKey, onPick)
        if parts == nil then
            return gui.Panel{ classes = { "collapsed" }, width = 0, height = 0 }
        end
        local chips = {}
        for _,p in ipairs(parts) do
            local partKey = EncounterOfTheWeek.PartKey(seriesKey, p.number)
            local unlocked, why = EncounterOfTheWeek.PartUnlocked(partKey)
            local won = EncounterOfTheWeek.PartWon(partKey)
            local text = string.format("Part %d", p.number)
            if p.title ~= nil then
                text = text .. ": " .. p.title
            end
            local icon = nil
            if won then
                icon = "phosphor/check-bold.png"
            elseif not unlocked then
                icon = "phosphor/lock-simple-fill.png"
            end
            chips[#chips+1] = gui.Panel{
                classes = { "seriesPart", cond(onPick ~= nil and partKey == currentKey, "selected", nil),
                    cond(not unlocked, "locked", nil) },
                width = "auto",
                height = 34,
                hpad = 12,
                borderBox = true,
                hmargin = 4,
                vmargin = 3,
                flow = "horizontal",
                bgimage = "panels/square.png",
                hover = function(element)
                    local tip = why
                    if tip == nil and won then
                        tip = "Your party has won this part."
                    end
                    if tip ~= nil then
                        gui.Tooltip(tip)(element)
                    end
                end,
                press = function(element)
                    if onPick == nil or not unlocked or partKey == currentKey then
                        return
                    end
                    audio.FireSoundEvent("Mouse.Click")
                    onPick(partKey)
                end,
                gui.Panel{
                    classes = { cond(icon == nil, "collapsed", nil) },
                    interactable = false,
                    bgimage = icon or "panels/square.png",
                    bgcolor = "#f6ead0",
                    width = 16,
                    height = 16,
                    valign = "center",
                    rmargin = 6,
                },
                gui.Label{
                    interactable = false,
                    text = text,
                    fontSize = 16,
                    color = "#f6ead0",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                },
            }
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            wrap = true,
            vmargin = 4,
            styles = {
                {
                    selectors = { "seriesPart" },
                    bgcolor = "#ffffff0e",
                    borderWidth = 1,
                    borderColor = "#8f8a7f88",
                    cornerRadius = 6,
                },
                {
                    selectors = { "seriesPart", "hover" },
                    borderColor = "#e6dcc6",
                },
                {
                    selectors = { "seriesPart", "selected" },
                    bgcolor = "#5a4a2acc",
                    borderColor = "#f6ead0",
                },
                {
                    selectors = { "seriesPart", "locked" },
                    opacity = 0.5,
                },
            },
            children = chips,
        }
    end

    --A small cream overline ("THIS WEEK'S ENCOUNTER").
    local Overline = function(text)
        return gui.Label{
            text = string.format("<cspace=0.25em>%s</cspace>", string.upper(text)),
            fontSize = 15,
            bold = true,
            color = "#e6dcc6",
            width = "auto",
            height = "auto",
        }
    end

    --The Gate's header: this week's encounter, its backstory (the script's
    --"# Town Gate" text, published with the module) and who made it.
    local WeekBanner = function()
        local key = EncounterOfTheWeek.CurrentEncounterKey()
        ---@type Panel[]
        local children = { Overline("This Week's Encounter") }
        if key == nil then
            children[#children+1] = gui.Label{
                text = "The guild has not posted this week's encounter yet. Check back soon.",
                fontSize = 20,
                italics = true,
                color = "#efe4cc",
                width = "100%",
                height = "auto",
                tmargin = 8,
            }
        else
            children[#children+1] = gui.Label{
                text = EncounterOfTheWeek.EncounterTitle(key),
                fontFace = "display",
                fontSize = 46,
                color = "#f6ead0",
                width = "100%",
                height = "auto",
            }
            local credit = EncounterOfTheWeek.EncounterCredit(key)
            if credit ~= nil then
                children[#children+1] = gui.Label{
                    text = credit,
                    fontSize = 15,
                    color = "#b8ad96",
                    width = "100%",
                    height = "auto",
                }
            end
            --a series: its parts and how far this account has got.
            local entry = EncounterOfTheWeek.GetEncounter(key)
            children[#children+1] = SeriesPartChips(key, entry ~= nil and entry.parts or nil)
            local backstory = EncounterOfTheWeek.GetTownGateText(key)
            children[#children+1] = gui.Label{
                text = backstory or "",
                fontSize = 19,
                italics = true,
                color = "#efe4cc",
                width = "100%",
                height = "auto",
                textWrap = true,
                tmargin = 8,
                classes = { cond(backstory == nil, "collapsed", nil) },
            }
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            bgimage = "panels/square.png",
            bgcolor = "#ffffff0c",
            borderWidth = 1,
            borderColor = "#e6dcc644",
            cornerRadius = 10,
            pad = 16,
            borderBox = true,
            vmargin = 4,
            children = children,
        }
    end

    --One encounter on the Proving Pits' board: its title, maker, votes so
    --far, backstory, and a Form a Party for it.
    local DangerEncounterRow = function(entry)
        local stats = m_dangerStats[entry.key]
        local statsText = "Not yet tried"
        if stats ~= nil then
            statsText = string.format("%d up, %d down -- played %d time%s", stats.up or 0, stats.down or 0,
                stats.plays or 0, cond(stats.plays == 1, "", "s"))
        end
        local byline = entry.moduleName or entry.moduleid
        if entry.author ~= nil and entry.author ~= "" then
            byline = string.format("%s by %s", byline, entry.author)
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "#ffffff0e",
            cornerRadius = 8,
            pad = 12,
            borderBox = true,
            vmargin = 4,

            gui.Panel{
                width = "100%-190",
                height = "auto",
                valign = "center",
                flow = "vertical",
                gui.Label{
                    text = entry.title,
                    fontSize = 24,
                    bold = true,
                    color = Styles.textColor,
                    width = "100%",
                    height = "auto",
                },
                gui.Label{
                    text = byline,
                    fontSize = 15,
                    color = "#b8ad96",
                    width = "100%",
                    height = "auto",
                },
                gui.Label{
                    text = statsText,
                    fontSize = 15,
                    color = "#e6dcc6",
                    width = "100%",
                    height = "auto",
                },
                SeriesPartChips(entry.key, entry.parts),
                gui.Label{
                    text = entry.townGate or "",
                    fontSize = 16,
                    italics = true,
                    color = "#efe4cc",
                    width = "100%",
                    height = "auto",
                    textWrap = true,
                    tmargin = 4,
                    classes = { cond(entry.townGate == nil, "collapsed", nil) },
                },
            },
            gui.Button{
                text = "Form a Party",
                fontSize = 18,
                width = 170,
                height = 42,
                halign = "right",
                valign = "center",
                click = function()
                    ShowCreateDialog(entry.key)
                end,
            },
        }
    end

    --This account's own encounters in the pool (it published the module),
    --whose Proving Pits feedback it may read.
    local MyEncounters = function()
        local result = {}
        for _,entry in ipairs(EncounterOfTheWeek.GetEncounters() or {}) do
            if entry.ours == true and not entry.official then
                result[#result+1] = entry
            end
        end
        return result
    end

    --A board's list mode: its header, then the parties it holds (forming
    --ones first, then those underway), then -- in the Proving Pits -- the
    --encounters to try.
    local BoardChildren = function(mode, games, ids)
        local children = {}
        if mode == "gate" then
            children[#children+1] = WeekBanner()
        else
            children[#children+1] = PracticeNote("96%")
        end
        --the account's in-progress game, unless it also has a live roster
        --record below (then the richer roster row covers it).
        if m_resumeGameid ~= nil and (games == nil or games[m_resumeGameid] == nil) then
            children[#children+1] = MakeResumeRow()
        end

        local forming = {}
        local underway = {}
        for _,gameid in ipairs(ids) do
            ---@cast games -nil
            local record = games[gameid]
            --private games are listed only for their members (the host, and
            --friends who joined through a Steam invite).
            local isMember = record.hostUserid == dmhub.loginUserid or (record.players ~= nil and record.players[dmhub.loginUserid] ~= nil)
            if PartyMode(record) == mode and (record.public == true or isMember) then
                if record.status == "open" then
                    forming[#forming+1] = MakeGameRow(gameid, record)
                else
                    underway[#underway+1] = MakeGameRow(gameid, record)
                end
            end
        end

        children[#children+1] = ListSectionTitle("Parties Forming")
        if #forming == 0 then
            children[#children+1] = EmptyNote(cond(mode == "gate",
                "No parties are forming right now. Form one and others can join you!",
                "Nobody is in the Proving Pits right now. Pick an encounter below to form a party."))
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

        if mode == "danger" then
            children[#children+1] = ListSectionTitle("Encounters to Try")
            local encounters = EncounterOfTheWeek.GetDangerRoomEncounters()
            if EncounterOfTheWeek.GetEncounters() == nil then
                children[#children+1] = EmptyNote("Gathering the encounters...")
            elseif #encounters == 0 then
                children[#children+1] = EmptyNote("No new encounters have been submitted. Publish one as an Encounter of the Week module and it will appear here.")
            end
            for _,entry in ipairs(encounters) do
                children[#children+1] = DangerEncounterRow(entry)
            end
        end
        return children
    end

    RefreshGames = function()
        local any = false
        for _,mode in ipairs(PARTY_MODES) do
            local list = m_partyUI[mode].list
            if list ~= nil and list.valid then
                any = true
                if m_conn == nil then
                    list.children = { EmptyNote("This build of the Codex does not include the lobby engine update.") }
                end
            end
        end
        if not any or m_conn == nil then
            return
        end

        --a launched game we belong to pulls us into the world; the lists
        --still re-render below while the game switch spins up.
        CheckLaunchedGames()

        --game lobby view mode: the viewed party renders on its own board
        --(the other board keeps its lists); if it vanished (abandoned,
        --expired, or we left it) both boards show their lists.
        local viewRecord = nil
        if m_viewGameid ~= nil then
            viewRecord = GetGameRecord(m_viewGameid)
            if viewRecord == nil then
                m_viewGameid = nil
                ShowGamesError("That game is no longer available.")
                RefreshChat()
            end
        end
        local viewMode = viewRecord ~= nil and PartyMode(viewRecord) or nil

        local games = m_conn:GetPath("/state/games")
        local ids = {}
        if games ~= nil then
            for gameid,_ in pairs(games) do
                ids[#ids+1] = gameid
            end
        end
        table.sort(ids)

        for _,mode in ipairs(PARTY_MODES) do
            local ui = m_partyUI[mode]
            if ui.list ~= nil and ui.list.valid then
                local inView = mode == viewMode
                if inView then
                    ---@cast viewRecord -nil
                    SetCardWidth(mode, CARD_WIDTH_PARTY)
                    ui.list.children = BuildGameView(m_viewGameid, viewRecord)
                else
                    SetCardWidth(mode, CARD_WIDTH_LIST[mode])
                    ui.list.children = BoardChildren(mode, games, ids)
                end
                if ui.title ~= nil and ui.title.valid then
                    ui.title.text = cond(inView, "Your Party", cond(mode == "gate", "Encounter of the Week", "The Proving Pits"))
                end
                --no back button in a party view: leaving the party
                --(Abandon/Leave) is the way back to the lists. The collapsed
                --controls free their space to the view.
                if ui.controls ~= nil and ui.controls.valid then
                    ui.controls:SetClass("collapsed", inView)
                end
                if ui.creatorButton ~= nil and ui.creatorButton.valid then
                    ui.creatorButton:SetClass("collapsed", #MyEncounters() == 0)
                end
                if ui.pastButton ~= nil and ui.pastButton.valid then
                    ui.pastButton:SetClass("collapsed", #EncounterOfTheWeek.PastEncounterKeys() == 0)
                end
            end
        end
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
        --a game the player abandoned from inside (EncounterPresence.Abandon)
        --is left behind for the others, or deleted when nobody else still
        --holds it (AbandonGame).
        local abandonedText = dmhub.GetSettingValue("eotw:abandonedgame")
        if type(abandonedText) == "string" and abandonedText ~= "" then
            dmhub.SetSettingValue("eotw:abandonedgame", "")
            local parsed = dmhub.FromJson(abandonedText)
            local abandoned = (type(parsed) == "table" and parsed.success) and parsed.result or nil
            if type(abandoned) == "table" and type(abandoned.gameid) == "string" then
                printf("EotW: cleaning up abandoned game %s", abandoned.gameid)
                DestroyPreviousGame(abandoned.gameid, { abandon = true })
                if EotwSlotGameid() == abandoned.gameid then
                    m_resumeGameid = nil
                    m_resumeInfo = nil
                    return
                end
            end
        end

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
        --the Game Chat tab lists the party, marking who is not in town.
        if m_viewGameid ~= nil and m_chatTab == "game" then
            local record = m_conn:GetPath("/state/games/" .. m_viewGameid)
            for userid,player in pairs(record ~= nil and record.players or {}) do
                local name = ChatPlain(player.name or "?")
                if presence == nil or presence[userid] == nil then
                    name = name .. " <color=#ffffff80>(away)</color>"
                end
                names[#names+1] = name
            end
            table.sort(names)
            presenceLabel.text = string.format("In this party (%d): %s", #names, table.concat(names, ", "))
            return
        end
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

        --the line above the messages follows the tab: town or party.
        RefreshPresence()

        --in a party view the tabs pick the town or the party's private
        --channel; otherwise the drawer is the town chat alone.
        local townChat = m_conn:GetPath("/chat")
        local gameChat = nil
        if m_viewGameid ~= nil then
            gameChat = m_conn:GetPath("/gamechat/" .. m_viewGameid)
        end
        local gameTab = m_viewGameid ~= nil and m_chatTab == "game"
        local chat = townChat
        local channel = "town"
        if gameTab then
            chat = gameChat
            channel = m_viewGameid --[[@as string]] --gameTab implies a party view
        end
        if chatTitleLabel ~= nil and chatTitleLabel.valid then
            chatTitleLabel:SetClass("collapsed", m_viewGameid ~= nil)
        end
        if chatTabRow ~= nil and chatTabRow.valid then
            chatTabRow:SetClass("collapsed", m_viewGameid == nil)
            if m_viewGameid ~= nil then
                chatTabRow:FireEventTree("refreshTab", {
                    selected = m_chatTab,
                    unread = {
                        town = gameTab and ChatUnread("town", townChat),
                        game = (not gameTab) and ChatUnread(m_viewGameid, gameChat),
                    },
                })
            end
        end
        --players must know when what they type also shows on Discord.
        if chatInput ~= nil and chatInput.valid then
            local mirrored = channel == "town" and m_conn:GetPath("/city/discordBridge") == true
            chatInput.placeholderText = cond(mirrored, "Say something... (also posted to Discord)", "Say something...")
        end
        local ids = {}
        local newestTs = nil
        if chat ~= nil then
            for msgid,msg in pairs(chat) do
                ids[#ids+1] = msgid
                if type(msg.ts) == "number" and (newestTs == nil or msg.ts > newestTs) then
                    newestTs = msg.ts
                end
            end
        end
        --msgids sort chronologically: oldest at the top, newest at the bottom.
        table.sort(ids)
        if channel ~= m_chatChannel then
            m_chatChannel = channel
            m_chatStickBottom = true
        end

        --while the drawer is open everything shown counts as seen, but the
        --divider stays where it was when the drawer opened. false = no
        --divider (first visit to this channel).
        local divider = nil
        if m_chatOpen then
            local viewed = dmhub.GetSettingValue("eotw:chatlastviewed")
            if type(viewed) ~= "table" then
                viewed = {}
            end
            if m_chatDividers[channel] == nil then
                m_chatDividers[channel] = viewed[channel] or false
            end
            divider = m_chatDividers[channel]
            local lastViewed = viewed[channel] --[[@as number|nil]]
            if newestTs ~= nil and (lastViewed == nil or newestTs > lastViewed) then
                --keep only the town and the party in view: party chats come and go.
                local keep = { town = viewed.town }
                if m_viewGameid ~= nil then
                    keep[m_viewGameid] = viewed[m_viewGameid]
                end
                keep[channel] = newestTs
                dmhub.SetSettingValue("eotw:chatlastviewed", keep)
            end

            --posting clears the divider, as in Discord.
            if divider and chat ~= nil then
                for _,msg in pairs(chat) do
                    if msg.userid == dmhub.loginUserid and type(msg.ts) == "number" and msg.ts > divider then
                        divider = false
                        m_chatDividers[channel] = newestTs
                        break
                    end
                end
            end
        end

        local children = {}
        local seenAbove = false
        for _,msgid in ipairs(ids) do
            --ids is empty unless chat is non-nil.
            ---@cast chat -nil
            local msg = chat[msgid]
            local ts = type(msg.ts) == "number" and msg.ts or nil
            if divider and ts ~= nil then
                if ts <= divider then
                    seenAbove = true
                elseif seenAbove then
                    children[#children+1] = ChatNewDivider()
                    seenAbove = false
                    divider = false
                end
            end
            local stamp = ""
            if ts ~= nil then
                stamp = string.format("<color=#ffffff80><size=80%%>%s</size></color>  ", FormatChatTime(ts))
            end
            --messages bridged in from the Discord channel carry a tag.
            local name = string.format("<b>%s:</b>", ChatPlain(msg.name or "?"))
            if msg.source == "discord" then
                name = string.format("<color=#8c9eff><b>%s</b> <size=70%%>DISCORD</size>:</color>", ChatPlain(msg.name or "?"))
            end
            local edited = ""
            if msg.edited then
                edited = " <color=#ffffff80><size=80%>(edited)</size></color>"
            end
            local body = ChatPlain(msg.text or "")
            --a horn's announcement reads as one gold line: "Aria blows the horn! ...",
            --as does its close (horn-launched / horn-canceled / horn-expired).
            if type(msg.kind) == "string" and (msg.kind == "horn" or msg.kind:sub(1, 5) == "horn-") then
                name = string.format("<color=#d9b56a><b>%s</b>", ChatPlain(msg.name or "?"))
                body = body .. "</color>"
            end
            children[#children+1] = gui.Label{
                text = string.format("%s%s %s%s", stamp, name, body, edited),
                fontSize = 18,
                color = Styles.textColor,
                width = "96%",
                height = "auto",
                halign = "left",
                vmargin = 2,
            }
        end
        chatMessagesPanel.children = children
        if m_chatStickBottom then
            --set again once layout has measured the new children.
            chatMessagesPanel.vscrollPosition = 0
            chatMessagesPanel:ScheduleEvent("moveToBottom", 0.05)
        end
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
            statusLabel.text = "Disconnected from the town."
        else
            statusLabel.text = "Connecting to the town..."
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
        m_chatTab = "town"
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
        local dyingNames = {}
        for _,hero in ipairs(EotwRoster.GetHeroes() or {}) do
            if not claimed[hero.heroid] and away[hero.heroid] == nil then
                --a dying hero must rest at the Blue Fish Inn first (the city
                --refuses the claim too).
                if EotwRoster.IsDying(hero.heroid) then
                    dyingNames[#dyingNames+1] = (hero.summary or {}).name or "A hero"
                else
                    heroes[#heroes+1] = hero
                end
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
        if #dyingNames > 0 then
            rows[#rows+1] = EmptyNote(string.format("%s %s dying and must rest at the Blue Fish Inn before setting out again.",
                table.concat(dyingNames, ", "), cond(#dyingNames == 1, "is", "are")))
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

    --explicitPart: encounterKey names the part to play. Otherwise a series'
    --key opens on the next part this account has to play (NextPartKey).
    ShowCreateDialog = function(encounterKey, explicitPart)
        if m_conn == nil or resultPanel == nil or not resultPanel.valid then
            return
        end
        if m_modalDialog ~= nil and m_modalDialog.valid then
            return
        end
        if encounterKey == nil or encounterKey == "" then
            return
        end

        --A series sets out for one of its parts. The part chips below re-open
        --this dialog on the part clicked; a locked part cannot be chosen.
        local seriesEntry = EncounterOfTheWeek.GetEncounter(encounterKey)
        local seriesParts = seriesEntry ~= nil and seriesEntry.parts or nil
        local seriesKey = EncounterOfTheWeek.SplitPartKey(encounterKey)
        if seriesParts ~= nil and not explicitPart then
            encounterKey = EncounterOfTheWeek.NextPartKey(encounterKey)
        end
        local partUnlocked, partLockedWhy = EncounterOfTheWeek.PartUnlocked(encounterKey)

        local m_public = true
        local m_busy = false
        ---@type Input
        local nameInput = nil
        local dialogStatusLabel = nil
        --assigned below, before any of its click handlers can fire.
        ---@type Panel
        local dlg = nil

        --The party sets out for one encounter, chosen where it was formed:
        --the Encounter of the Week (or a past one) at the Gate, a Proving Pits
        --encounter in the Proving Pits. It rides the party record as its
        --encounter KEY (the town keys who has already won an encounter by it).
        local m_encounter = encounterKey
        local practice = EncounterOfTheWeek.IsDangerRoomEncounter(m_encounter)
        local credit = EncounterOfTheWeek.EncounterCredit(m_encounter)
        local backstory = EncounterOfTheWeek.GetTownGateText(m_encounter)

        --default the game name to the creator's name ("David's Party"),
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
            if not partUnlocked then
                SetDialogStatus(partLockedWhy or "That part is locked.", true)
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
                    EotwAnalytics.Track("eotw_party_create", {
                        encounter = m_encounter,
                        board = cond(m_encounter ~= nil and EncounterOfTheWeek.IsDangerRoomEncounter(m_encounter), "pits", "gate"),
                        public = m_public,
                    })
                    SetDialogStatus("Creating the game...")
                    --one EotW game per account: capture the current slot
                    --value now -- creating the new game overwrites it --
                    --and destroy that game once the new one exists.
                    local prev = EotwSlotGameid()
                    lobby:CreateGame{
                        description = name,
                        coverart = LOADING_SCREEN_ART,
                        startingModule = STARTING_MODULE,
                        backend = EotwRoster.GameBackend(),
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
                                DestroyPreviousGame(prev, { abandon = true })
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

        dlg = gui.Panel{
            floating = true,
            width = 600,
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
                tmargin = 16,
            },

            --where the party is going.
            gui.Label{
                text = EncounterOfTheWeek.EncounterTitle(m_encounter),
                fontFace = "display",
                fontSize = 30,
                color = "#f6ead0",
                width = 520,
                height = "auto",
                halign = "center",
                textAlignment = "center",
                vmargin = 4,
            },
            gui.Label{
                classes = { cond(credit == nil, "collapsed", nil) },
                text = credit or "",
                fontSize = 15,
                color = "#b8ad96",
                width = 520,
                height = "auto",
                halign = "center",
                textAlignment = "center",
                textWrap = true,
                vmargin = 2,
            },
            --a series: which part (won parts say so; locked ones cannot be picked).
            SeriesPartChips(seriesKey, seriesParts, m_encounter, function(partKey)
                if dlg ~= nil and dlg.valid then
                    dlg:DestroySelf()
                end
                m_modalDialog = nil
                ShowCreateDialog(partKey, true)
            end),
            gui.Panel{
                classes = { cond(backstory == nil, "collapsed", nil) },
                width = 520,
                height = "auto",
                halign = "center",
                BackstoryLabel(backstory or "", 520),
            },
            gui.Panel{
                classes = { cond(not practice, "collapsed", nil) },
                width = 520,
                height = "auto",
                halign = "center",
                PracticeNote(520),
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

    --A modal over the town with the house frame, a title and a scrolling body.
    --Returns the dialog (already mounted) or nil when one is already up.
    local ModalDialog = function(args)
        if resultPanel == nil or not resultPanel.valid then
            return nil
        end
        if m_modalDialog ~= nil and m_modalDialog.valid then
            return nil
        end
        local dlg
        dlg = gui.Panel{
            floating = true,
            width = args.width or 860,
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
                if args.escape ~= nil then
                    args.escape(element)
                else
                    element:DestroySelf()
                end
            end,

            gui.Label{
                text = args.title,
                fontSize = 32,
                bold = true,
                color = Styles.textColor,
                width = "auto",
                height = "auto",
                halign = "center",
                vmargin = 8,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                maxHeight = args.maxBodyHeight or 640,
                vscroll = true,
                flow = "vertical",
                rpad = 12,
                borderBox = true,
                vmargin = 8,
                children = args.children,
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                flow = "horizontal",
                vmargin = 8,
                children = args.buttons or {
                    gui.Button{
                        text = "Close",
                        fontSize = 20,
                        width = 140,
                        height = 42,
                        click = function(element)
                            dlg:DestroySelf()
                        end,
                    },
                },
            },
        }
        m_modalDialog = dlg
        resultPanel:AddChild(dlg)
        return dlg
    end

    --The Gate's Past Encounters: every earlier Encounter of the Week, newest
    --first, each still playable (and still worth its Victory, once a hero).
    ShowPastEncountersDialog = function()
        local rows = {}
        local dlg = nil
        local past = EncounterOfTheWeek.PastEncounterKeys()
        if #past == 0 then
            rows[1] = EmptyNote("There are no past Encounters of the Week yet.")
        end
        for _,key in ipairs(past) do
            local credit = EncounterOfTheWeek.EncounterCredit(key)
            local backstory = EncounterOfTheWeek.GetTownGateText(key)
            rows[#rows+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                bgimage = "panels/square.png",
                bgcolor = "#ffffff0e",
                cornerRadius = 8,
                pad = 12,
                borderBox = true,
                vmargin = 4,
                gui.Panel{
                    width = "100%-190",
                    height = "auto",
                    valign = "center",
                    flow = "vertical",
                    gui.Label{
                        text = EncounterOfTheWeek.EncounterTitle(key),
                        fontSize = 24,
                        bold = true,
                        color = Styles.textColor,
                        width = "100%",
                        height = "auto",
                    },
                    gui.Label{
                        classes = { cond(credit == nil, "collapsed", nil) },
                        text = credit or "",
                        fontSize = 15,
                        color = "#b8ad96",
                        width = "100%",
                        height = "auto",
                    },
                    SeriesPartChips(key, (EncounterOfTheWeek.GetEncounter(key) or {}).parts),
                    gui.Label{
                        classes = { cond(backstory == nil, "collapsed", nil) },
                        text = backstory or "",
                        fontSize = 16,
                        italics = true,
                        color = "#efe4cc",
                        width = "100%",
                        height = "auto",
                        textWrap = true,
                        tmargin = 4,
                    },
                },
                gui.Button{
                    text = "Form a Party",
                    fontSize = 18,
                    width = 170,
                    height = 42,
                    halign = "right",
                    valign = "center",
                    click = function()
                        if dlg ~= nil and dlg.valid then
                            dlg:DestroySelf()
                        end
                        m_modalDialog = nil
                        ShowCreateDialog(key)
                    end,
                },
            }
        end
        dlg = ModalDialog{ title = "Past Encounters", children = rows }
    end

    --A creator's view of what Proving Pits players said about their
    --encounters: the votes so far and every piece of feedback, newest first.
    ShowCreatorFeedbackDialog = function()
        local mine = MyEncounters()
        if #mine == 0 or m_conn == nil then
            return
        end
        local keys = {}
        local titles = {}
        for _,entry in ipairs(mine) do
            keys[#keys+1] = entry.key
            titles[entry.key] = entry.title
        end
        local body = nil
        local dlg = ModalDialog{
            title = "Feedback on Your Encounters",
            children = {
                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    create = function(element)
                        body = element
                    end,
                    EmptyNote("Asking the Proving Pits..."),
                },
            },
        }
        if dlg == nil then
            return
        end
        m_conn:Request{
            action = "danger-feedback-for",
            args = { encounters = keys },
            success = function(result)
                if body == nil or not body.valid then
                    return
                end
                local rows = {}
                for _,key in ipairs(keys) do
                    local stats = (result.stats or {})[key]
                    rows[#rows+1] = ListSectionTitle(titles[key])
                    rows[#rows+1] = gui.Label{
                        text = cond(stats == nil, "Nobody has tried it yet.",
                            string.format("%d up, %d down -- played %d time%s", stats ~= nil and stats.up or 0,
                                stats ~= nil and stats.down or 0, stats ~= nil and stats.plays or 0,
                                cond(stats ~= nil and stats.plays == 1, "", "s"))),
                        fontSize = 16,
                        color = "#e6dcc6",
                        width = "100%",
                        height = "auto",
                    }
                    for _,f in ipairs(result.feedback or {}) do
                        if f.encounter == key then
                            local vote = cond((f.vote or 0) > 0, "voted up", cond((f.vote or 0) < 0, "voted down", "no vote"))
                            rows[#rows+1] = gui.Label{
                                text = string.format("<b>%s</b> (%s)%s", f.name or "?", vote,
                                    cond(f.feedback ~= nil and f.feedback ~= "", ": " .. tostring(f.feedback), "")),
                                fontSize = 16,
                                color = Styles.textColor,
                                width = "100%",
                                height = "auto",
                                textWrap = true,
                                vmargin = 3,
                            }
                        end
                    end
                end
                body.children = rows
            end,
            error = function(message)
                if body ~= nil and body.valid then
                    body.children = { EmptyNote("Could not load the feedback: " .. tostring(message)) }
                end
            end,
        }
    end

    --The Proving Pits' votes so far, for the board.
    local FetchDangerStats = function()
        if m_conn == nil or not m_conn.connected then
            return
        end
        m_conn:Request{
            action = "danger-stats",
            success = function(result)
                if mod.unloaded then
                    return
                end
                m_dangerStats = result.stats or {}
                RefreshGames()
            end,
            error = function(message)
                printf("EotW: could not read the Proving Pits' votes: %s", tostring(message))
            end,
        }
    end

    --- the Proving Pits debrief -------------------------------------------
    --After a Proving Pits game the game side leaves eotw:pendingDebrief; back
    --in town the player is asked to vote and give the creator feedback.
    --Sending or skipping clears it.

    local ReadPendingDebrief = function()
        local text = dmhub.GetSettingValue("eotw:pendingDebrief")
        if type(text) ~= "string" or text == "" then
            return nil
        end
        --FromJson answers {success, result}, not the decoded value.
        local parsed = dmhub.FromJson(text)
        if type(parsed) ~= "table" or not parsed.success or type(parsed.result) ~= "table" then
            return nil
        end
        local entry = parsed.result[dmhub.loginUserid]
        if type(entry) ~= "table" or type(entry.encounter) ~= "string" or type(entry.gameid) ~= "string" then
            return nil
        end
        return entry
    end

    local ClearPendingDebrief = function(gameid)
        local text = dmhub.GetSettingValue("eotw:pendingDebrief")
        local parsed = type(text) == "string" and text ~= "" and dmhub.FromJson(text) or nil
        if type(parsed) ~= "table" or not parsed.success or type(parsed.result) ~= "table" then
            dmhub.SetSettingValue("eotw:pendingDebrief", "")
            return
        end
        local all = parsed.result
        local entry = all[dmhub.loginUserid]
        if type(entry) == "table" and entry.gameid == gameid then
            all[dmhub.loginUserid] = nil
            dmhub.SetSettingValue("eotw:pendingDebrief", dmhub.ToJson(all))
        end
    end

    local m_debriefOpen = false
    --{gameid -> true}: Proving Pits wins sent this session (record-practice-win).
    local m_practiceWinSent = {}

    local ShowDebriefDialog = function(entry)
        local m_vote = 0
        local m_feedback = ""
        local m_sending = false
        local voteButtons = {}
        ---@type Label
        local debriefStatus = nil
        local dlg = nil

        local SetDebriefStatus = function(text, isError)
            if debriefStatus ~= nil and debriefStatus.valid then
                debriefStatus.text = text or ""
                debriefStatus.selfStyle.color = cond(isError, "#ff8888", Styles.textColor)
            end
        end

        local Close = function()
            m_debriefOpen = false
            if dlg ~= nil and dlg.valid then
                dlg:DestroySelf()
            end
        end

        local VoteButton = function(vote, icon, text)
            local button
            button = gui.Panel{
                classes = { "debriefVote" },
                width = 200,
                height = 50,
                hmargin = 10,
                flow = "horizontal",
                bgimage = "panels/square.png",
                styles = {
                    {
                        selectors = { "debriefVote" },
                        bgcolor = "#ffffff0e",
                        borderWidth = 2,
                        borderColor = "#8f8a7f88",
                        cornerRadius = 8,
                        transitionTime = 0.12,
                    },
                    {
                        selectors = { "debriefVote", "hover" },
                        borderColor = "#e6dcc6",
                    },
                    {
                        selectors = { "debriefVote", "selected" },
                        bgcolor = cond(vote > 0, "#3f6b3acc", "#7a3434cc"),
                        borderColor = "#f6ead0",
                    },
                },
                press = function(element)
                    audio.FireSoundEvent("Mouse.Click")
                    m_vote = cond(m_vote == vote, 0, vote)
                    for v,b in pairs(voteButtons) do
                        if b.valid then
                            b:SetClass("selected", v == m_vote)
                        end
                    end
                end,
                gui.Panel{
                    interactable = false,
                    bgimage = icon,
                    bgcolor = "#f6ead0",
                    width = 26,
                    height = 26,
                    valign = "center",
                    lmargin = 34,
                    rmargin = 10,
                },
                gui.Label{
                    interactable = false,
                    text = text,
                    fontSize = 20,
                    bold = true,
                    color = "#f6ead0",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                },
            }
            voteButtons[vote] = button
            return button
        end

        local resultText = cond(entry.result == "victory", "Your party survived the Proving Pits.",
            cond(entry.result == "defeat", "The Proving Pits got the better of your party.", "Your party left the Proving Pits."))

        local Label = function(text, size, color)
            return gui.Label{
                text = text,
                fontSize = size,
                color = color or Styles.textColor,
                width = "100%",
                height = "auto",
                textAlignment = "center",
                textWrap = true,
                vmargin = 4,
            }
        end

        dlg = ModalDialog{
            title = "Proving Pits Debrief",
            width = 720,
            maxBodyHeight = 720,
            --closing with Escape counts as Skip.
            escape = function(element)
                ClearPendingDebrief(entry.gameid)
                Close()
            end,
            children = {
                gui.Label{
                    text = EncounterOfTheWeek.EncounterTitle(entry.encounter),
                    fontFace = "display",
                    fontSize = 34,
                    color = "#f6ead0",
                    width = "100%",
                    height = "auto",
                    textAlignment = "center",
                },
                Label(string.format("%s It was practice: nothing was awarded.", resultText), 17, "#ffcf8a"),
                Label("How was it?", 20),
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    flow = "horizontal",
                    vmargin = 6,
                    VoteButton(1, "phosphor/thumbs-up-fill.png", "Upvote"),
                    VoteButton(-1, "phosphor/thumbs-down-fill.png", "Downvote"),
                },
                Label("Feedback for its creator (optional)", 18),
                gui.Input{
                    width = "94%",
                    height = 110,
                    halign = "center",
                    fontSize = 17,
                    multiline = true,
                    textAlignment = "topleft",
                    characterLimit = 2000,
                    placeholderText = "What worked? What would make it better?",
                    change = function(element)
                        m_feedback = element.text or ""
                    end,
                },
                gui.Label{
                    text = "",
                    fontSize = 16,
                    color = Styles.textColor,
                    width = "100%",
                    height = "auto",
                    minHeight = 22,
                    textAlignment = "center",
                    vmargin = 4,
                    create = function(element)
                        ---@cast element Label
                        debriefStatus = element
                    end,
                },
            },
            buttons = {
                gui.Button{
                    text = "Send",
                    fontSize = 20,
                    width = 160,
                    height = 44,
                    hmargin = 8,
                    click = function(element)
                        if m_sending or m_conn == nil then
                            return
                        end
                        m_sending = true
                        SetDebriefStatus("Sending...")
                        m_conn:Request{
                            action = "danger-feedback",
                            args = {
                                --a series is voted on as a whole: its bare key.
                                encounter = (EncounterOfTheWeek.SplitPartKey(entry.encounter)),
                                gameid = entry.gameid,
                                vote = m_vote,
                                feedback = m_feedback,
                            },
                            success = function()
                                EotwAnalytics.Track("eotw_debrief", {
                                    action = "send",
                                    runid = entry.gameid,
                                    encounter = entry.encounter,
                                    result = entry.result,
                                    vote = m_vote,
                                    hasFeedback = type(m_feedback) == "string" and m_feedback:match("%S") ~= nil,
                                })
                                ClearPendingDebrief(entry.gameid)
                                Close()
                                FetchDangerStats()
                            end,
                            error = function(message)
                                m_sending = false
                                SetDebriefStatus("Could not send: " .. tostring(message), true)
                            end,
                        }
                    end,
                },
                gui.Button{
                    text = "Skip",
                    fontSize = 20,
                    width = 160,
                    height = 44,
                    hmargin = 8,
                    click = function(element)
                        EotwAnalytics.Track("eotw_debrief", {
                            action = "skip",
                            runid = entry.gameid,
                            encounter = entry.encounter,
                            result = entry.result,
                        })
                        ClearPendingDebrief(entry.gameid)
                        Close()
                    end,
                },
            },
        }
        if dlg == nil then
            m_debriefOpen = false
        end
    end

    --Ask for a Proving Pits debrief owed from the last game, once the town is
    --connected and the pool (which names the encounter) has loaded.
    local MaybeShowDebrief = function()
        if m_debriefOpen or m_conn == nil or not m_conn.connected then
            return
        end
        local entry = ReadPendingDebrief()
        if entry == nil then
            return
        end
        if m_modalDialog ~= nil and m_modalDialog.valid then
            return
        end
        m_debriefOpen = true
        --a won Proving Pits game counts for the account, whatever the player does
        --with the debrief: it unlocks a series' next part there. Idempotent.
        if entry.result == "victory" and not m_practiceWinSent[entry.gameid] then
            m_practiceWinSent[entry.gameid] = true
            m_conn:Request{
                action = "record-practice-win",
                args = { encounter = entry.encounter, gameid = entry.gameid },
                success = function(result)
                    EotwRoster.SetPracticeWins(result.practiceWins)
                    if RefreshGames ~= nil then
                        RefreshGames()
                    end
                end,
                error = function(message)
                    m_practiceWinSent[entry.gameid] = nil
                    printf("EotW: could not record the Proving Pits win: %s", tostring(message))
                end,
            }
        end
        EncounterOfTheWeek.RefreshPool(function()
            if mod.unloaded or resultPanel == nil or not resultPanel.valid then
                m_debriefOpen = false
                return
            end
            ShowDebriefDialog(entry)
        end)
    end

    ---- results left while we were away ------------------------------------

    --A game this player left WITHOUT abandoning went on with their heroes as
    --free agents; when it was won or lost, its host left the heroes' results
    --with the city (offer-outcomes). Back in town the player chooses: accept
    --them (the usual pending-outcome queue brings the Victories home and
    --buries the heroes who fell) or count the game as abandoned and drop
    --them. One game at a time; asked once a connection.
    local m_offersAsked = false
    local m_offersOpen = false

    local function ShowOfferedOutcomes(games, index)
        local game = games[index]
        if game == nil or resultPanel == nil or not resultPanel.valid then
            m_offersOpen = false
            return
        end

        local encounter = nil
        local defeat = false
        local anyFell = false
        local lines = {}
        for _, hero in ipairs(game.heroes or {}) do
            local outcome = type(hero.outcome) == "table" and hero.outcome or {}
            encounter = encounter or outcome.encounter
            if outcome.result == "defeat" then
                defeat = true
            end
            local parts = {}
            local victories = tonumber(outcome.victories) or 0
            if outcome.died == true then
                anyFell = true
                parts[#parts + 1] = "fell in battle"
            elseif victories > 0 then
                parts[#parts + 1] = string.format("%d %s", victories, cond(victories == 1, "Victory", "Victories"))
            elseif outcome.completed then
                parts[#parts + 1] = "no Victory (already completed)"
            end
            local found = {}
            for _, t in ipairs(type(outcome.treasures) == "table" and outcome.treasures or {}) do
                found[#found + 1] = tostring(t.name or "an item")
            end
            if #found > 0 then
                parts[#parts + 1] = "found " .. table.concat(found, ", ")
            end
            local wounds = type(outcome.wounds) == "table" and outcome.wounds or {}
            if (tonumber(wounds.damage) or 0) > 0 or (tonumber(wounds.recoveriesUsed) or 0) > 0 then
                parts[#parts + 1] = "came back wounded"
            end
            local name = (hero.name ~= nil and hero.name ~= "") and hero.name or "Your hero"
            lines[#lines + 1] = string.format("<b>%s</b>%s", name, cond(#parts > 0, ": " .. table.concat(parts, "; "), ""))
        end
        local title = encounter ~= nil and EncounterOfTheWeek.EncounterTitle(encounter) or "your Encounter of the Week"

        local hint = "Claim the victory for your heroes, or count the game as abandoned and leave it be."
        if defeat then
            hint = "Accept the defeat, and your fallen heroes are laid to rest in the Graveyard; or count the game as abandoned and leave it be."
        elseif anyFell then
            hint = "Claim the victory for your heroes, and your fallen heroes are laid to rest in the Graveyard; or count the game as abandoned and leave it be."
        end

        local dlg = nil
        local busy = false
        local function Done(claim)
            if busy then
                return
            end
            busy = true
            EotwAnalytics.Track("eotw_offered_outcome", {
                runid = game.gameid,
                claim = claim == true,
                heroes = #(game.heroes or {}),
            })
            if claim then
                local entries = {}
                for _, hero in ipairs(game.heroes or {}) do
                    entries[#entries + 1] = { gameid = game.gameid, heroid = hero.heroid, outcome = hero.outcome }
                end
                EotwRoster.AddPendingOutcomes(entries)
            end
            local function Next()
                if dlg ~= nil and dlg.valid then
                    dlg:DestroySelf()
                end
                ShowOfferedOutcomes(games, index + 1)
            end
            if m_conn == nil then
                Next()
                return
            end
            m_conn:Request{
                action = "resolve-offered-outcomes",
                args = { gameid = game.gameid },
                success = function() Next() end,
                --the offer stays for next time; a claim already queued is
                --not doubled by a second one (one outcome per hero a game).
                error = function(err)
                    printf("EotW town: could not settle the results of %s: %s", tostring(game.gameid), tostring(err))
                    Next()
                end,
            }
        end

        dlg = ModalDialog{
            title = "While You Were Away",
            width = 760,
            escape = function() end,
            children = {
                gui.Label{
                    text = string.format("Your party finished <b>%s</b> after you left, with your heroes fighting on as free agents, and %s.", title, cond(defeat, "was defeated", "won")),
                    fontSize = 20,
                    color = Styles.textColor,
                    width = "100%",
                    height = "auto",
                    textWrap = true,
                    vmargin = 6,
                },
                gui.Label{
                    text = table.concat(lines, "\n"),
                    fontSize = 18,
                    color = Styles.textColor,
                    width = "100%",
                    height = "auto",
                    textWrap = true,
                    vmargin = 6,
                },
                gui.Label{
                    text = hint,
                    fontSize = 16,
                    color = Styles.textColor,
                    opacity = 0.7,
                    width = "100%",
                    height = "auto",
                    textWrap = true,
                    vmargin = 6,
                },
            },
            buttons = {
                gui.Button{
                    text = cond(defeat, "Accept the Defeat", "Claim the Victory"),
                    fontSize = 20,
                    width = 240,
                    height = 44,
                    hmargin = 8,
                    click = function()
                        Done(true)
                    end,
                },
                gui.Button{
                    text = "Count as Abandoned",
                    fontSize = 20,
                    width = 240,
                    height = 44,
                    hmargin = 8,
                    click = function()
                        Done(false)
                    end,
                },
            },
        }
        if dlg == nil then
            --another dialog is up: ask again on the next refresh.
            m_offersOpen = false
            m_offersAsked = false
        end
    end

    local MaybeShowOfferedOutcomes = function()
        if m_offersAsked or m_offersOpen or m_debriefOpen or m_conn == nil or not m_conn.connected then
            return
        end
        if m_modalDialog ~= nil and m_modalDialog.valid then
            return
        end
        m_offersAsked = true
        m_offersOpen = true
        m_conn:Request{
            action = "list-offered-outcomes",
            args = {},
            success = function(result)
                if mod.unloaded or resultPanel == nil or not resultPanel.valid then
                    m_offersOpen = false
                    return
                end
                local games = type(result) == "table" and result.games or nil
                if type(games) ~= "table" or #games == 0 then
                    m_offersOpen = false
                    return
                end
                ShowOfferedOutcomes(games, 1)
            end,
            error = function(err)
                m_offersOpen = false
                printf("EotW town: could not list results left while away: %s", tostring(err))
            end,
        }
    end

    --- the beta survey -----------------------------------------------------
    --After a finished game of ten minutes or more the game side leaves
    --eotw:pendingSurvey; back in town, once nothing else is asking, the
    --player is invited to a short survey. Sending it or declining it ("No
    --thanks", or Escape) is recorded in the city (eotw-survey) and clears the
    --invitation. The questions live here; the city stores choice ids and
    --text and tallies them for the admins (survey-report).

    --Bump when the questions change, so the report keeps the sets apart.
    local SURVEY_ID = "eotw-beta-1"

    --Each question: an id, a prompt, choices ({id, text}) and optionally a
    --comment box, shown once a choice other than `hideFor` is picked.
    local SURVEY_LEAVE_QUESTION = {
        id = "leave",
        prompt = "What made you leave?",
        choices = {
            { id = "time", text = "Ran out of time" },
            { id = "not_fun", text = "Wasn't enjoying it" },
            { id = "bugs", text = "Bugs or problems" },
            { id = "doomed", text = "I saw the writing on the wall, I knew I was going to lose :)" },
            { id = "other", text = "Something else" },
        },
        comment = { placeholder = "Anything to add? (optional)" },
    }
    local SURVEY_QUESTIONS = {
        {
            id = "length",
            prompt = "How did the length of the session feel?",
            choices = {
                { id = "too_short", text = "Too short" },
                { id = "about_right", text = "About right" },
                { id = "too_long", text = "Too long" },
            },
        },
        {
            id = "difficulty",
            prompt = "Were you satisfied with the difficulty?",
            choices = {
                { id = "too_easy", text = "No, too easy" },
                { id = "satisfied", text = "Yes, it felt right" },
                { id = "too_hard", text = "No, too hard" },
            },
        },
        {
            id = "bugs",
            prompt = "Did you run into any bugs?",
            choices = {
                { id = "none", text = "No bugs" },
                { id = "minor", text = "Minor annoyances" },
                { id = "disruptive", text = "They got in the way" },
                { id = "ruined", text = "They ruined the session" },
            },
            comment = { hideFor = "none", placeholder = "What went wrong? (optional)" },
        },
        {
            id = "ui",
            prompt = "Was the interface clear?",
            choices = {
                { id = "clear", text = "Clear" },
                { id = "mostly", text = "Mostly clear" },
                { id = "confusing", text = "Often confusing" },
            },
            comment = { hideFor = "clear", placeholder = "What was confusing? (optional)" },
        },
        {
            id = "again",
            prompt = "Do you want to keep playing Encounter of the Week?",
            choices = {
                { id = "yes", text = "Yes" },
                { id = "maybe", text = "Maybe" },
                { id = "no", text = "No" },
            },
        },
    }

    local ReadPendingSurvey = function()
        local text = dmhub.GetSettingValue("eotw:pendingSurvey")
        if type(text) ~= "string" or text == "" then
            return nil
        end
        --FromJson answers {success, result}, not the decoded value.
        local parsed = dmhub.FromJson(text)
        if type(parsed) ~= "table" or not parsed.success or type(parsed.result) ~= "table" then
            return nil
        end
        local entry = parsed.result[dmhub.loginUserid]
        if type(entry) ~= "table" or type(entry.gameid) ~= "string" or type(entry.outcome) ~= "string" then
            return nil
        end
        return entry
    end

    local ClearPendingSurvey = function(gameid)
        local text = dmhub.GetSettingValue("eotw:pendingSurvey")
        local parsed = type(text) == "string" and text ~= "" and dmhub.FromJson(text) or nil
        if type(parsed) ~= "table" or not parsed.success or type(parsed.result) ~= "table" then
            dmhub.SetSettingValue("eotw:pendingSurvey", "")
            return
        end
        local all = parsed.result
        local entry = all[dmhub.loginUserid]
        if type(entry) == "table" and entry.gameid == gameid then
            all[dmhub.loginUserid] = nil
            dmhub.SetSettingValue("eotw:pendingSurvey", dmhub.ToJson(all))
        end
    end

    local m_surveyOpen = false

    local SURVEY_CHOICE_STYLES = {
        {
            selectors = { "surveyChoice" },
            bgcolor = "#ffffff0e",
            borderWidth = 2,
            borderColor = "#8f8a7f88",
            cornerRadius = 8,
            transitionTime = 0.12,
        },
        {
            selectors = { "surveyChoice", "hover" },
            borderColor = "#e6dcc6",
        },
        {
            selectors = { "surveyChoice", "selected" },
            bgcolor = "#38386ecc",
            borderColor = "#f6ead0",
        },
    }

    --nil for an empty table: an empty Lua table can go out as a JSON array,
    --which the city refuses where it wants an object.
    local NonEmpty = function(t)
        if t == nil or next(t) == nil then
            return nil
        end
        return t
    end

    --The eotw-survey request for this invitation: answers/comments, or a decline.
    local SurveyArgs = function(entry, declined, answers, comments)
        return {
            survey = SURVEY_ID,
            gameid = entry.gameid,
            kind = cond(entry.kind == "danger", "danger", "week"),
            outcome = entry.outcome,
            encounter = entry.encounter or "",
            declined = declined,
            answers = NonEmpty(answers),
            comments = NonEmpty(comments),
            context = {
                minutes = tonumber(entry.minutes) or 0,
                players = tonumber(entry.players) or 0,
                heroes = tonumber(entry.heroes) or 0,
                version = dmhub.version,
            },
        }
    end

    local ShowSurveyDialog = function(entry)
        local m_answers = {}
        local m_comments = {}
        local m_sending = false
        ---@type Label
        local surveyStatus = nil
        local dlg = nil

        local SetSurveyStatus = function(text, isError)
            if surveyStatus ~= nil and surveyStatus.valid then
                surveyStatus.text = text or ""
                surveyStatus.selfStyle.color = cond(isError, "#ff8888", Styles.textColor)
            end
        end

        local Close = function()
            m_surveyOpen = false
            if dlg ~= nil and dlg.valid then
                dlg:DestroySelf()
            end
        end

        --Declining is recorded too (best-effort: the invitation goes either way).
        local Decline = function()
            if m_sending then
                return
            end
            ClearPendingSurvey(entry.gameid)
            Close()
            EotwAnalytics.Track("eotw_survey", {
                action = "decline",
                runid = entry.gameid,
                encounter = entry.encounter,
                outcome = entry.outcome,
                minutes = entry.minutes,
            })
            if m_conn ~= nil then
                m_conn:Request{
                    action = "eotw-survey",
                    args = SurveyArgs(entry, true),
                    error = function(message)
                        printf("EotW: could not record the declined survey: %s", tostring(message))
                    end,
                }
            end
        end

        --One question: its prompt, a row of choices and (optionally) a comment box.
        local Question = function(q)
            local choicePanels = {}
            local commentInput = nil
            if q.comment ~= nil then
                commentInput = gui.Input{
                    classes = { cond(q.comment.hideFor ~= nil, "collapsed", nil) },
                    width = "96%",
                    height = 64,
                    halign = "center",
                    fontSize = 16,
                    multiline = true,
                    textAlignment = "topleft",
                    characterLimit = 2000,
                    placeholderText = q.comment.placeholder,
                    vmargin = 4,
                    change = function(element)
                        m_comments[q.id] = element.text or ""
                    end,
                }
            end
            for _,choice in ipairs(q.choices) do
                local panel
                panel = gui.Panel{
                    classes = { "surveyChoice" },
                    width = "auto",
                    height = "auto",
                    hpad = 14,
                    vpad = 8,
                    borderBox = true,
                    margin = 4,
                    bgimage = "panels/square.png",
                    styles = SURVEY_CHOICE_STYLES,
                    press = function(element)
                        audio.FireSoundEvent("Mouse.Click")
                        if m_answers[q.id] == choice.id then
                            m_answers[q.id] = nil
                        else
                            m_answers[q.id] = choice.id
                        end
                        for id,p in pairs(choicePanels) do
                            if p.valid then
                                p:SetClass("selected", m_answers[q.id] == id)
                            end
                        end
                        if commentInput ~= nil and q.comment.hideFor ~= nil then
                            local picked = m_answers[q.id]
                            commentInput:SetClass("collapsed", picked == nil or picked == q.comment.hideFor)
                        end
                    end,
                    gui.Label{
                        interactable = false,
                        text = choice.text,
                        fontSize = 17,
                        color = "#f6ead0",
                        width = "auto",
                        height = "auto",
                    },
                }
                choicePanels[choice.id] = panel
            end
            local choiceRow = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                halign = "center",
                children = (function()
                    local list = {}
                    for _,choice in ipairs(q.choices) do
                        list[#list+1] = choicePanels[choice.id]
                    end
                    return list
                end)(),
            }
            return gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                vmargin = 6,
                gui.Label{
                    text = q.prompt,
                    fontSize = 19,
                    bold = true,
                    color = Styles.textColor,
                    width = "100%",
                    height = "auto",
                    textWrap = true,
                },
                choiceRow,
                commentInput,
            }
        end

        local questions = {}
        if entry.outcome == "abandoned" then
            questions[#questions+1] = SURVEY_LEAVE_QUESTION
        end
        for _,q in ipairs(SURVEY_QUESTIONS) do
            questions[#questions+1] = q
        end

        local resultText = cond(entry.outcome == "victory", "Your party won.",
            cond(entry.outcome == "defeat", "Your party was defeated.", "You left the encounter."))
        local encounterTitle = ""
        if type(entry.encounter) == "string" and entry.encounter ~= "" then
            encounterTitle = EncounterOfTheWeek.EncounterTitle(entry.encounter)
        end

        ---@type Panel[]
        local children = {
            gui.Label{
                classes = { cond(encounterTitle == "", "collapsed", nil) },
                text = encounterTitle,
                fontFace = "display",
                fontSize = 30,
                color = "#f6ead0",
                width = "100%",
                height = "auto",
                textAlignment = "center",
            },
            gui.Label{
                text = string.format("%s Encounter of the Week is in beta, and a minute of your time helps us make it better. Every question is optional.", resultText),
                fontSize = 17,
                color = "#ffcf8a",
                width = "100%",
                height = "auto",
                textAlignment = "center",
                textWrap = true,
                vmargin = 6,
            },
        }
        for _,q in ipairs(questions) do
            children[#children+1] = Question(q)
        end
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            vmargin = 6,
            gui.Label{
                text = "Anything else you'd like to tell us?",
                fontSize = 19,
                bold = true,
                color = Styles.textColor,
                width = "100%",
                height = "auto",
            },
            gui.Input{
                width = "96%",
                height = 80,
                halign = "center",
                fontSize = 16,
                multiline = true,
                textAlignment = "topleft",
                characterLimit = 2000,
                placeholderText = "Optional",
                vmargin = 4,
                change = function(element)
                    m_comments.comments = element.text or ""
                end,
            },
        }
        children[#children+1] = gui.Label{
            text = "",
            fontSize = 16,
            color = Styles.textColor,
            width = "100%",
            height = "auto",
            minHeight = 22,
            textAlignment = "center",
            vmargin = 4,
            create = function(element)
                ---@cast element Label
                surveyStatus = element
            end,
        }

        dlg = ModalDialog{
            title = "Encounter of the Week Survey",
            width = 780,
            maxBodyHeight = 680,
            --closing with Escape counts as No thanks.
            escape = function(element)
                Decline()
            end,
            children = children,
            buttons = {
                gui.Button{
                    text = "Send",
                    fontSize = 20,
                    width = 160,
                    height = 44,
                    hmargin = 8,
                    click = function(element)
                        if m_sending or m_conn == nil then
                            return
                        end
                        m_sending = true
                        SetSurveyStatus("Sending...")
                        m_conn:Request{
                            action = "eotw-survey",
                            args = SurveyArgs(entry, false, m_answers, m_comments),
                            success = function()
                                --the answers are choice ids (the city keeps
                                --the comment text; analytics only notes one).
                                local hasComment = false
                                for _, text in pairs(m_comments or {}) do
                                    if type(text) == "string" and text:match("%S") ~= nil then
                                        hasComment = true
                                    end
                                end
                                EotwAnalytics.Track("eotw_survey", {
                                    action = "send",
                                    runid = entry.gameid,
                                    encounter = entry.encounter,
                                    outcome = entry.outcome,
                                    minutes = entry.minutes,
                                    surveyId = SURVEY_ID,
                                    answers = m_answers,
                                    hasComment = hasComment,
                                })
                                ClearPendingSurvey(entry.gameid)
                                Close()
                            end,
                            error = function(message)
                                m_sending = false
                                SetSurveyStatus("Could not send: " .. tostring(message), true)
                            end,
                        }
                    end,
                },
                gui.Button{
                    text = "No thanks",
                    fontSize = 20,
                    width = 160,
                    height = 44,
                    hmargin = 8,
                    click = function(element)
                        Decline()
                    end,
                },
            },
        }
        if dlg == nil then
            m_surveyOpen = false
        end
    end

    --Invite the player to a survey owed from the last game, once the town is
    --connected and nothing else (a debrief, results left while away, another
    --dialog) is asking. Polled by the town's watcher.
    local MaybeShowSurvey = function()
        if m_surveyOpen or m_debriefOpen or m_offersOpen or m_conn == nil or not m_conn.connected then
            return
        end
        if m_modalDialog ~= nil and m_modalDialog.valid then
            return
        end
        --a Proving Pits debrief goes first.
        if ReadPendingDebrief() ~= nil then
            return
        end
        local entry = ReadPendingSurvey()
        if entry == nil then
            return
        end
        m_surveyOpen = true
        --the pool names the encounter in the dialog's title.
        EncounterOfTheWeek.RefreshPool(function()
            if mod.unloaded or resultPanel == nil or not resultPanel.valid then
                m_surveyOpen = false
                return
            end
            if m_modalDialog ~= nil and m_modalDialog.valid then
                m_surveyOpen = false
                return
            end
            ShowSurveyDialog(entry)
        end)
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
    local chatPanel = nil

    --The location open full screen over the map ("guild", "gate"), or nil
    --on the map. The town's own furniture (map, plaque, hero strip) hides
    --while one is open. The Gate's scene is built once and kept, because its
    --games list must stay live (RefreshGames is what notices a launched
    --game and takes us into it); the Guild's is built on each visit.
    local m_locationId = nil
    --when the open location was opened (dmhub.Time), for its analytics.
    local m_locationOpenedAt = nil
    --true from the moment the Blue Fish Inn's reveal shows its node until the
    --reveal is recorded (see PlayInnReveal).
    local m_innRevealing = false
    --true for the whole reveal, dialog included; the guild holds its own
    --beckon meanwhile so the only thing pulsing is the inn.
    local m_innRevealActive = false
    --the map's location nodes, by location id.
    local m_nodePanels = {}
    local m_guildScene = nil
    local m_innScene = nil
    local m_marketScene = nil
    --the Construction or the Hall of Heroes, whichever was opened.
    local m_hallScene = nil
    local gateScene = nil
    local dangerScene = nil
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
        OpenDangerRooms = function()
            OpenLocation("danger")
        end,
        OpenInn = function()
            OpenLocation("inn")
        end,
        OpenMarket = function()
            OpenLocation("market")
        end,
        InnShown = function()
            return m_innRevealing or EotwRoster.InnRevealed()
        end,
        OpenGraveyard = function()
            EotwRoster.ShowGraveyard(resultPanel)
        end,
        OpenHall = function()
            OpenLocation("hall")
        end,
    }

    --One location on the map: a round icon over a name plaque. A locked
    --location dims and says why instead of opening.
    local LocationNode = function(loc)
        local NODE_WIDTH = 200
        --a location's label and icon may be functions of the town (the Hall
        --of Heroes reads "Construction" until it is built).
        local function LocValue(v)
            if type(v) == "function" then
                return v(townContext)
            end
            return v
        end
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
            data = { lockedReason = nil, nextBeckon = 0 },
            thinkTime = 0.5,
            think = function(element)
                if loc.hidden ~= nil then
                    element:SetClass("collapsed", loc.hidden(townContext) == true)
                end
                local reason = nil
                if loc.locked ~= nil then
                    reason = loc.locked(townContext)
                end
                element.data.lockedReason = reason
                element:SetClass("locked", reason ~= nil)
                if type(loc.label) == "function" or type(loc.icon) == "function" then
                    --compared with what was last set, not read back from the panels.
                    local text = LocValue(loc.label)
                    local icon = LocValue(loc.icon)
                    if element.data.shownLabel ~= text or element.data.shownIcon ~= icon then
                        element.data.shownLabel = text
                        element.data.shownIcon = icon
                        local label = element:Get("eotwTownLabel-" .. loc.id)
                        if label ~= nil then
                            label.text = text
                        end
                        local glyph = element:Get("eotwTownGlyph-" .. loc.id)
                        if glyph ~= nil then
                            glyph.bgimage = icon
                        end
                    end
                end

                --while the hero strip says no hero is active, the guild
                --icon pulses to point the player at it.
                if loc.id == "guild" and EotwRoster.GetHeroes() ~= nil and not m_innRevealActive then
                    local anyActive = false
                    for _,hero in ipairs(EotwRoster.ActiveHeroes()) do
                        if dmhub.GetCharacterById(hero.heroid) ~= nil then
                            anyActive = true
                        end
                    end
                    local now = dmhub.Time()
                    if not anyActive and now >= element.data.nextBeckon then
                        element.data.nextBeckon = now + 1.5
                        local halo = element:Get("eotwTownHalo-" .. loc.id)
                        if halo ~= nil then
                            halo:PulseClass("beckon")
                        end
                    end
                end
            end,
            create = function(element)
                m_nodePanels[loc.id] = element
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
                --a halo ring, invisible until the think above pulses it
                --(only the guild's does). First child, so the glyph draws
                --over it.
                gui.Panel{
                    id = "eotwTownHalo-" .. loc.id,
                    classes = { "eotwTownNodeHalo" },
                    floating = true,
                    interactable = false,
                },
                gui.Panel{
                    id = "eotwTownGlyph-" .. loc.id,
                    classes = { "eotwTownNodeGlyph" },
                    interactable = false,
                    bgimage = LocValue(loc.icon),
                },
            },
            gui.Label{
                id = "eotwTownLabel-" .. loc.id,
                classes = { "eotwTownNodeLabel" },
                interactable = false,
                text = LocValue(loc.label),
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
        --A ring around the icon. It rests large and fully transparent;
        --PulseClass("beckon") snaps it to the {beckon} rule (icon-sized,
        --bright) and eases back to rest over that rule's transitionTime,
        --so each pulse is a ring that swells outward and fades.
        {
            selectors = { "eotwTownNodeHalo" },
            width = 64,
            height = 64,
            halign = "center",
            valign = "center",
            cornerRadius = 32,
            bgimage = "panels/square.png",
            bgcolor = "clear",
            borderWidth = 4,
            borderColor = "#ffe9b000",
            scale = 1.9,
        },
        {
            selectors = { "eotwTownNodeHalo", "beckon" },
            borderColor = "#ffe9b0ff",
            scale = 1.05,
            transitionTime = 1.2,
            --a pulse eases on the REMAINING weight (1 -> 0), so the curve
            --runs backwards: easeIn here plays as a fast burst that settles.
            easing = "easeInCubic",
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

    ---- the Blue Fish Inn's reveal ----

    --A new player's town has no inn (EotwRoster.InnUnlocked). The first time
    --the town finds it unlocked -- heroes just came home from the Town Gate --
    --the map pans to the tavern, a returning hero says, in the montage's
    --dialog box, that it is time to rest, and the inn's node drops onto the
    --map from large. Played once per account on this machine.
    local INN_PAN_SECONDS = 0.9
    local INN_TYPE_CPS = 45
    --the node starts this many times its size, fades in over the first part
    --of the drop and lands with a small bounce and a jolt of the map.
    local INN_DROP_SCALE = 5
    local INN_DROP_SECONDS = 0.85
    local INN_DROP_FADE = 0.35
    local INN_SETTLE_SECONDS = 0.4
    local INN_SETTLE_BOUNCE = 0.14
    local INN_SHAKE_PX = 6
    --the speaker's figure on the dialog box (the montage stage's sizes).
    local INN_PORTRAIT_WIDTH = 230
    local INN_PORTRAIT_HEIGHT = 300
    local INN_PORTRAIT_FADE = 0.15
    local INN_LINE = "That was a tough challenge! We should head to the Blue Fish Inn to rest before continuing on more adventures."

    local m_innRevealQueuedAt = nil

    --Who announces the inn: of the heroes who came home this session, the
    --one who lost the most Stamina. With none (an account that adventured
    --before the inn was hidden), the most wounded hero at home, active first.
    local PickInnSpeaker = function()
        local best = nil
        for _,h in ipairs(EotwRoster.Homecomings()) do
            if EotwRoster.FindHero(h.heroid) ~= nil and dmhub.GetCharacterById(h.heroid) ~= nil then
                if best == nil or h.damage > best.damage then
                    best = h
                end
            end
        end
        if best ~= nil then
            return best.heroid
        end
        local bestid, bestScore = nil, nil
        for _,hero in ipairs(EotwRoster.GetHeroes() or {}) do
            local tok = dmhub.GetCharacterById(hero.heroid)
            if tok ~= nil then
                local damage = 0
                pcall(function() damage = tonumber(tok.properties.damage_taken) or 0 end)
                local score = damage + cond(hero.active == true, 100000, 0)
                if bestScore == nil or score > bestScore then
                    bestid, bestScore = hero.heroid, score
                end
            end
        end
        return bestid
    end

    --Set opacity on a panel and everything inside it (opacity is not inherited).
    local function SetTreeOpacity(element, opacity)
        element.selfStyle.opacity = opacity
        for _,child in ipairs(element.children or {}) do
            SetTreeOpacity(child, opacity)
        end
    end

    --The hero's off-token portrait cropped to the figure's shape, its bottom
    --band trimmed so the foot stays crisp under the edge fade (the montage
    --stage's SetPortraitFrom).
    local function InnSpeakerPortrait(tok)
        local aspect = INN_PORTRAIT_WIDTH / INN_PORTRAIT_HEIGHT
        return gui.Panel{
            width = INN_PORTRAIT_WIDTH,
            height = INN_PORTRAIT_HEIGHT,
            hmargin = 40,
            halign = "left",
            bgimage = "panels/square.png",
            bgcolor = "#00000000",
            --set on the panel itself: edgeFade from a class rule is not applied.
            edgeFade = INN_PORTRAIT_FADE,
            interactable = false,
            create = function(element)
                local portrait = nil
                pcall(function() portrait = tok.offTokenPortrait end)
                if portrait == nil or portrait == "" then
                    return
                end
                element.bgimage = portrait
                element.selfStyle.bgcolor = "white"
                local rect = nil
                pcall(function() rect = tok:GetPortraitRectForAspect(aspect * (1 - INN_PORTRAIT_FADE), portrait) end)
                if rect ~= nil then
                    local y1 = math.max(INN_PORTRAIT_FADE, rect.y1 + (rect.y2 - rect.y1) * INN_PORTRAIT_FADE)
                    rect = { x1 = rect.x1, y1 = y1, x2 = rect.x2, y2 = rect.y2 }
                end
                element.selfStyle.imageRect = rect
            end,
        }
    end

    local PlayInnReveal = function(heroid)
        local tok = dmhub.GetCharacterById(heroid)
        local node = m_nodePanels["inn"]
        if tok == nil or node == nil or not node.valid or resultPanel == nil or not resultPanel.valid then
            return
        end
        local inn = CityLocation("inn")
        m_innRevealActive = true
        --the hero strip would sit under the dialog box: hide it meanwhile.
        --"hidden", not "collapsed" (that one belongs to ApplyLocationMode).
        local strip = resultPanel:Get("eotwTownHeroStrip")
        if strip ~= nil then
            strip:SetClass("hidden", true)
        end

        --pan so the inn sits in the upper part of the screen, clear of the
        --dialog box.
        local fromX, fromY = m_panX, m_panY
        local toX = math.max(0, math.min(mapW - panelWidth, inn.x * mapW - panelWidth / 2))
        local toY = math.max(0, math.min(mapH - panelHeight, inn.y * mapH - panelHeight * 0.32))

        --"pan" -> "type" -> "drop" -> "settle" -> "wait" (for a click) -> "closing"
        local phase = "pan"
        local phaseStart = dmhub.Time()
        --- @type Panel
        local overlay
        --- @type Panel
        local textLabel
        --- @type Panel
        local prompt
        --- @type Panel
        local stage

        local function Enter(newPhase)
            phase = newPhase
            phaseStart = dmhub.Time()
        end

        local function StartDrop()
            textLabel.text = INN_LINE
            m_innRevealing = true
            node:SetClass("collapsed", false)
            node.selfStyle.scale = INN_DROP_SCALE
            SetTreeOpacity(node, 0)
            audio.FireSoundEvent("DiceImp.Whoosh_MetalBlade")
            Enter("drop")
        end

        local function Close()
            if phase == "closing" then
                return
            end
            Enter("closing")
            if strip ~= nil and strip.valid then
                strip:SetClass("hidden", false)
            end
            EotwRoster.MarkInnRevealed()
            m_innRevealing = false
            audio.FireSoundEvent("Mouse.Click")
            stage:SetClassTree("innSpeechOff", true)
            overlay:SetClass("innSpeechOff", true)
            dmhub.Schedule(0.4, function()
                if mod.unloaded then
                    return
                end
                if overlay ~= nil and overlay.valid then
                    overlay:DestroySelf()
                end
                if m_modalDialog == overlay then
                    m_modalDialog = nil
                end
            end)
            --a few beckoning pulses point the player at their new destination.
            for i = 0, 2 do
                dmhub.Schedule(0.5 + i * 1.5, function()
                    if mod.unloaded or node == nil or not node.valid then
                        return
                    end
                    local halo = node:Get("eotwTownHalo-inn")
                    if halo ~= nil then
                        halo:PulseClass("beckon")
                    end
                end)
            end
            --the guild may beckon again once the inn's last pulse has faded.
            dmhub.Schedule(5, function()
                m_innRevealActive = false
            end)
        end

        --a click (or Escape) hurries the line along, and once the inn has
        --landed, closes the dialog.
        local function Advance()
            if phase == "pan" or phase == "type" then
                ApplyPan()
                StartDrop()
            elseif phase == "wait" then
                Close()
            end
        end

        textLabel = gui.Label{
            classes = { "innSpeechText" },
            text = "",
            interactable = false,
        }
        prompt = gui.Panel{
            classes = { "innSpeechPrompt", "collapsed" },
            floating = true,
            width = 18,
            height = 18,
            halign = "right",
            valign = "bottom",
            bgimage = "phosphor/caret-down-fill.png",
            interactable = false,
            thinkTime = 0.6,
            think = function(element)
                element:SetClass("dimmed", not element:HasClass("dimmed"))
            end,
        }

        stage = gui.Panel{
            classes = { "innSpeechStage" },
            floating = true,
            width = 1000,
            height = "auto",
            halign = "center",
            valign = "bottom",
            bmargin = 30,
            flow = "vertical",
            interactable = false,
            InnSpeakerPortrait(tok),
            gui.Panel{
                classes = { "innSpeechBox" },
                width = "100%",
                height = 150,
                bgimage = "panels/square.png",
                pad = 18,
                borderBox = true,
                flow = "vertical",
                interactable = false,
                gui.Label{
                    classes = { "innSpeechSpeaker" },
                    text = tok.name or "",
                    interactable = false,
                },
                textLabel,
                prompt,
            },
        }

        overlay = gui.Panel{
            classes = { "innSpeechOverlay" },
            floating = true,
            width = "100%",
            height = "100%",
            --a clear background still catches clicks, so the map and its
            --nodes cannot be used until the dialog is done.
            bgimage = "panels/square.png",
            bgcolor = "clear",
            styles = {
                --born with "innSpeechOff" (on the whole stage subtree), so the
                --figure and box fade and rise in; Close puts it back.
                {
                    selectors = { "innSpeechOff" },
                    opacity = 0,
                    transitionTime = 0.35,
                },
                {
                    selectors = { "innSpeechStage", "innSpeechOff" },
                    y = 30,
                    transitionTime = 0.35,
                    easing = "easeOutCubic",
                },
                --the montage stage's dialog box (EncounterMontageStage.lua).
                {
                    selectors = { "innSpeechBox" },
                    --opaque, unlike the montage's: the town map is busy behind it.
                    bgcolor = "#06080cff",
                    border = 2,
                    borderColor = "#ffffff60",
                    cornerRadius = 8,
                },
                {
                    selectors = { "innSpeechSpeaker" },
                    fontSize = 16,
                    bold = true,
                    color = "#ffd66b",
                    width = "100%",
                    height = "auto",
                    textAlignment = "left",
                    bmargin = 4,
                },
                {
                    selectors = { "innSpeechText" },
                    fontSize = 19,
                    color = "#ffffff",
                    width = "100%",
                    height = "auto",
                    textAlignment = "left",
                },
                {
                    selectors = { "innSpeechPrompt" },
                    bgcolor = "#ffd66b",
                },
                {
                    selectors = { "innSpeechPrompt", "dimmed" },
                    opacity = 0.25,
                },
            },
            captureEscape = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            escape = function(element)
                Advance()
            end,
            press = function(element)
                Advance()
            end,

            stage,

            thinkTime = 0.02,
            think = function(element)
                local t = dmhub.Time() - phaseStart
                if phase == "pan" then
                    local p = math.min(1, t / INN_PAN_SECONDS)
                    --ease in and out.
                    local e = cond(p < 0.5, 4 * p * p * p, 1 - ((-2 * p + 2) ^ 3) / 2)
                    m_panX = fromX + (toX - fromX) * e
                    m_panY = fromY + (toY - fromY) * e
                    ApplyPan()
                    if p >= 1 then
                        Enter("type")
                    end
                elseif phase == "type" then
                    local n = math.floor(t * INN_TYPE_CPS)
                    if n >= #INN_LINE then
                        StartDrop()
                    else
                        textLabel.text = string.sub(INN_LINE, 1, n)
                    end
                elseif phase == "drop" then
                    local p = math.min(1, t / INN_DROP_SECONDS)
                    --hangs large, then accelerates down onto the map.
                    node.selfStyle.scale = 1 + (INN_DROP_SCALE - 1) * (1 - p * p)
                    SetTreeOpacity(node, math.min(1, p / INN_DROP_FADE))
                    if p >= 1 then
                        node.selfStyle.scale = 1
                        local halo = node:Get("eotwTownHalo-inn")
                        if halo ~= nil then
                            halo:PulseClass("beckon")
                        end
                        audio.FireSoundEvent("Foot.Generic_Stone")
                        Enter("settle")
                    end
                elseif phase == "settle" then
                    local q = math.min(1, t / INN_SETTLE_SECONDS)
                    node.selfStyle.scale = 1 + INN_SETTLE_BOUNCE * math.sin(math.pi * q)
                    --the map jolts as it lands, dying away.
                    local shake = INN_SHAKE_PX * (1 - q)
                    for _,layer in ipairs({ mapPanel, nodeLayer }) do
                        if layer ~= nil and layer.valid then
                            layer.selfStyle.x = -m_panX + math.random(-100, 100) / 100 * shake
                            layer.selfStyle.y = -m_panY + math.random(-100, 100) / 100 * shake
                        end
                    end
                    if q >= 1 then
                        node.selfStyle.scale = 1
                        ApplyPan()
                        prompt:SetClass("collapsed", false)
                        Enter("wait")
                    end
                end
            end,
        }

        --the overlay counts as the town's modal, so no other dialog stacks on it.
        m_modalDialog = overlay
        resultPanel:AddChild(overlay)
        stage:SetClassTreeImmediate("innSpeechOff", true)
        dmhub.Schedule(0.03, function()
            if mod.unloaded or stage == nil or not stage.valid then
                return
            end
            stage:SetClassTree("innSpeechOff", false)
        end)
    end

    --Start the reveal once the inn is unlocked and the town is quiet: on the
    --map, nothing else up, every returning hero's outcome carried home, and
    --that state held for a moment so the last homecoming can land.
    local MaybePlayInnReveal = function()
        --what the reveal is waiting on, kept in EncounterOfTheWeek.innRevealWaitingOn
        --for debugging over MCP (nil once it has played or is playing).
        local waiting = nil
        if resultPanel == nil or not resultPanel.valid or resultPanel:HasClass("hidden") or resultPanel:HasClass("eotwOpening") then
            waiting = "screen"
        elseif EotwRoster.InnRevealed() or m_innRevealing then
            waiting = nil
        elseif EotwRoster.InnUnlocked() ~= true then
            waiting = "unlock"
        elseif m_locationId ~= nil then
            waiting = "location"
        elseif m_debriefOpen or m_offersOpen or (m_modalDialog ~= nil and m_modalDialog.valid) then
            waiting = "dialog"
        elseif EotwRoster.OutcomesInFlight() then
            waiting = "outcomes"
        end
        EncounterOfTheWeek.innRevealWaitingOn = waiting
        local ready = waiting == nil and not m_innRevealing and not EotwRoster.InnRevealed()
        if not ready then
            m_innRevealQueuedAt = nil
            return
        end
        local now = dmhub.Time()
        if m_innRevealQueuedAt == nil then
            m_innRevealQueuedAt = now
            return
        end
        if now - m_innRevealQueuedAt < 1.5 then
            return
        end
        m_innRevealQueuedAt = nil
        local heroid = PickInnSpeaker()
        if heroid == nil then
            EncounterOfTheWeek.innRevealWaitingOn = "speaker"
            return
        end
        printf("EotW town: the Blue Fish Inn reveal starts (speaker %s)", heroid)
        PlayInnReveal(heroid)
    end

    --- the welcome dialog --------------------------------------------------
    --The first time an account opens the town on this machine it is welcomed
    --to Encounter of the Week (eotw:welcomed). It is a ModalDialog, so the
    --inn's reveal, the debrief and the survey all wait for it to close.

    local DISCORD_URL = "https://discord.gg/q7kg5AVSfj"

    local LoadWelcomed = function()
        local text = dmhub.GetSettingValue("eotw:welcomed")
        if type(text) == "string" and text ~= "" then
            local parsed = dmhub.FromJson(text)
            if type(parsed) == "table" and parsed.success and type(parsed.result) == "table" then
                return parsed.result
            end
        end
        return {}
    end

    local MarkWelcomed = function()
        local all = LoadWelcomed()
        all[dmhub.loginUserid] = true
        dmhub.SetSettingValue("eotw:welcomed", dmhub.ToJson(all))
        --analytics: an account's first visit to the town on this machine.
        EotwAnalytics.Track("eotw_welcome", { action = "shown" })
    end

    --Also reachable over MCP for testing: EncounterOfTheWeek.ShowWelcomeDialog().
    local ShowWelcomeDialog = function()
        local dlg = nil
        --<link=url> spans in the text open their url when pressed.
        local Paragraph = function(text)
            return gui.Label{
                text = text,
                fontSize = 19,
                color = "#efe4cc",
                width = "100%",
                height = "auto",
                textWrap = true,
                vmargin = 8,
                links = true,
                press = function(element)
                    if element.linkHovered ~= nil then
                        dmhub.OpenURL(element.linkHovered)
                    end
                end,
            }
        end
        dlg = ModalDialog{
            title = "Welcome to Encounter of the Week",
            width = 760,
            children = {
                Paragraph("Play Draw Steel by yourself or with a few friends, or people you meet along the way. This game mode is experimental and in beta. Please report bugs using Feedback in the menus."),
                Paragraph(string.format("Discuss Encounter of the Week in the <color=#8fc7ff><u><link=%s>DMHub Discord</link></u></color>!", DISCORD_URL)),
                Paragraph("Encounter of the Week does let you play with other users. Be kind to each other. We really don't want to ban anybody, but we will if we have to."),
            },
            buttons = {
                gui.Button{
                    text = "Join the Discord",
                    fontSize = 20,
                    width = 200,
                    height = 44,
                    hmargin = 8,
                    click = function(element)
                        dmhub.OpenURL(DISCORD_URL)
                        EotwAnalytics.Track("eotw_welcome", { action = "discord" })
                    end,
                },
                gui.Button{
                    text = "Let's Go!",
                    fontSize = 20,
                    width = 160,
                    height = 44,
                    hmargin = 8,
                    click = function(element)
                        if dlg ~= nil and dlg.valid then
                            dlg:DestroySelf()
                        end
                    end,
                },
            },
        }
        return dlg
    end
    EncounterOfTheWeek.ShowWelcomeDialog = ShowWelcomeDialog

    --Welcome an account the first time it reaches the town map: the screen
    --up and settled, no location open and no other dialog. Marked seen as it
    --opens, so it never comes back even if the app quits with it up.
    local MaybeShowWelcome = function()
        if resultPanel == nil or not resultPanel.valid or resultPanel:HasClass("hidden") or resultPanel:HasClass("eotwOpening") then
            return
        end
        if m_locationId ~= nil or m_innRevealing or m_debriefOpen or m_offersOpen or m_surveyOpen then
            return
        end
        if m_modalDialog ~= nil and m_modalDialog.valid then
            return
        end
        if LoadWelcomed()[dmhub.loginUserid] == true then
            return
        end
        if ShowWelcomeDialog() ~= nil then
            MarkWelcomed()
        end
    end

    ---- Steam invites (see the note above CreateScreen) -----------------

    local InviteNotice = function(title, text)
        ModalDialog{
            title = title,
            width = 640,
            children = {
                gui.Label{
                    text = text,
                    fontSize = 20,
                    color = Styles.textColor,
                    width = "100%",
                    height = "auto",
                    textWrap = true,
                    textAlignment = "center",
                    vmargin = 8,
                },
            },
        }
    end

    --True when we host, or have joined, this roster record.
    ---@param record table
    local IsMemberOf = function(record)
        local myUserid = dmhub.loginUserid
        return record.hostUserid == myUserid or (record.players ~= nil and record.players[myUserid] ~= nil)
    end

    --Act on an accepted invite (m_pendingInvite) once the town is up and the
    --lobby snapshot has arrived: open the party's board and join it, first
    --asking if that means leaving a party we are already in.
    local TryAcceptInvite = function()
        local invite = m_pendingInvite
        if invite == nil or m_conn == nil or not m_conn.connected or m_enteringWorld then
            return
        end
        if resultPanel == nil or not resultPanel.valid or resultPanel:HasClass("hidden") or resultPanel:HasClass("eotwOpening") then
            return
        end
        --we are always present ourselves, so an empty /presence means the
        --snapshot (and with it the party list) has not arrived yet.
        if next(m_conn:GetPath("/presence") or {}) == nil then
            return
        end
        if m_modalDialog ~= nil and m_modalDialog.valid then
            return
        end
        m_pendingInvite = nil

        local gameid = invite.gameid
        local record = GetGameRecord(gameid)
        if record == nil then
            InviteNotice("Party Not Found", "That party is no longer forming. Your friend may have disbanded it, or it may have timed out.")
            return
        end
        local mode = PartyMode(record)
        if IsMemberOf(record) then
            OpenLocation(mode)
            OpenGameView(gameid)
            return
        end
        if record.status ~= "open" then
            InviteNotice("Party Already Set Out", string.format("%s's party has already begun its encounter.", record.hostName or "Your friend"))
            return
        end

        local Join = function()
            EotwAnalytics.Track("eotw_party_invite_accept", { runid = gameid })
            OpenLocation(mode)
            JoinGame(gameid, invite.code)
        end

        --joining replaces the party we are in (JoinGame leaves our EotW slot
        --game, disbanding it if we host it), so ask first.
        local current = nil
        for otherid,other in pairs(m_conn:GetPath("/state/games") or {}) do
            if otherid ~= gameid and IsMemberOf(other) then
                current = other
            end
        end
        if current == nil then
            Join()
            return
        end

        local consequence
        if current.hostUserid == dmhub.loginUserid then
            consequence = "Joining will disband the party you are hosting."
        else
            consequence = string.format("Joining will take you out of %s's party.", current.hostName or "your current")
        end
        local dlg
        dlg = ModalDialog{
            title = "Join Your Friend's Party?",
            width = 680,
            children = {
                gui.Label{
                    text = string.format("%s invited you to their party. %s", record.hostName or "A friend", consequence),
                    fontSize = 20,
                    color = Styles.textColor,
                    width = "100%",
                    height = "auto",
                    textWrap = true,
                    textAlignment = "center",
                    vmargin = 8,
                },
            },
            buttons = {
                gui.Button{
                    text = "Join",
                    fontSize = 20,
                    width = 140,
                    height = 42,
                    hmargin = 6,
                    click = function()
                        if dlg ~= nil then
                            dlg:DestroySelf()
                        end
                        Join()
                    end,
                },
                gui.Button{
                    text = "Cancel",
                    fontSize = 20,
                    width = 140,
                    height = 42,
                    hmargin = 6,
                    click = function()
                        if dlg ~= nil then
                            dlg:DestroySelf()
                        end
                    end,
                },
            },
        }
    end

    --Our forming party is our Steam "Join Game" target, so friends can join
    --from the Steam friends list too. The engine forgets it 10s after the
    --last push, so a closed or hidden town stops advertising on its own.
    local PushSteamJoinTarget = function()
        if m_conn == nil or not m_conn.connected then
            dmhub.SetSteamJoinTarget(nil)
            return
        end
        local party = nil
        local partyid = nil
        for gameid,record in pairs(m_conn:GetPath("/state/games") or {}) do
            if record.status == "open" and IsMemberOf(record) and (partyid == nil or gameid == m_viewGameid) then
                party = record
                partyid = gameid
            end
        end
        if party == nil or partyid == nil then
            dmhub.SetSteamJoinTarget(nil)
            return
        end
        local code = m_inviteCodes[partyid]
        if code == nil then
            if not m_inviteCodeAsked[partyid] then
                WithInviteCode(partyid, function() end)
            end
            return
        end
        local members = 0
        for _,_ in pairs(party.players or {}) do
            members = members + 1
        end
        if party.players == nil or party.players[party.hostUserid] == nil then
            members = members + 1
        end
        dmhub.SetSteamJoinTarget(STEAM_INVITE_KIND, partyid .. ":" .. code, partyid, members)
    end

    --Was the Arcane Market found when the roster was last listed? nil until
    --then. A hidden node is collapsed, and a collapsed panel stops thinking,
    --so it cannot show itself again: this watcher does it.
    local m_marketFound = nil

    --Put the Arcane Market on the map once the player finds it (the Find
    --the Arcane Market project completes). Found while the town is open, it
    --beckons a few times; already found when the town opened, it just shows.
    local RevealFoundLocations = function()
        local node = m_nodePanels["market"]
        if node == nil or not node.valid then
            return
        end
        local found = EotwRoster.MarketUnlocked()
        if found and node:HasClass("collapsed") then
            node:SetClass("collapsed", false)
        end
        if EotwRoster.GetHeroes() == nil then
            return
        end
        if found and m_marketFound == false then
            --usually found at the inn: beckon once the player is back on the map.
            if m_locationId ~= nil then
                return
            end
            for i = 0, 2 do
                dmhub.Schedule(0.5 + i * 1.5, function()
                    if mod.unloaded or node == nil or not node.valid then
                        return
                    end
                    local halo = node:Get("eotwTownHalo-market")
                    if halo ~= nil then
                        halo:PulseClass("beckon")
                    end
                end)
            end
        end
        m_marketFound = found
    end

    --Re-list the projects whenever the City says a community one changed
    --(/city/projectsRev): someone in town worked on the Hall of Heroes.
    local m_projectsRevSeen = nil
    local WatchCommunityProjects = function()
        local conn = EotwRoster.Connection()
        if m_conn == nil or conn == nil or not conn.connected then
            return
        end
        local rev = m_conn:GetPath("/city/projectsRev")
        if rev ~= m_projectsRevSeen then
            m_projectsRevSeen = rev
            EotwDowntime.RefreshProjects()
        end
    end

    --The moment the town finishes the Hall of Heroes: an open Construction
    --becomes the Hall (after the builders' banner has had its moment), and
    --the node beckons once the player is back on the map. Already built when
    --the town opened, nothing plays.
    local m_hallBuilt = nil
    local m_hallSwapScheduled = false
    local RevealHall = function()
        if EotwRoster.GetHeroes() == nil then
            return
        end
        local built = EotwRoster.HallBuilt()
        if built and m_hallBuilt == false then
            if m_locationId == "hall" and not m_hallSwapScheduled then
                m_hallSwapScheduled = true
                dmhub.Schedule(4, function()
                    m_hallSwapScheduled = false
                    if mod.unloaded or m_locationId ~= "hall" or CityLocation("hall").scene == HALL_SCENE then
                        return
                    end
                    CloseLocation()
                    OpenLocation("hall")
                end)
            end
            if m_locationId ~= nil then
                return
            end
            local node = m_nodePanels["hall"]
            for i = 0, 2 do
                dmhub.Schedule(0.5 + i * 1.5, function()
                    if mod.unloaded or node == nil or not node.valid then
                        return
                    end
                    local halo = node:Get("eotwTownHalo-hall")
                    if halo ~= nil then
                        halo:PulseClass("beckon")
                    end
                end)
            end
        end
        m_hallBuilt = built
    end

    ---- locations: full-screen scenes over the map ----

    --The card holding a location's controls sits on the right, clear of the
    --creator credit + chat button below it.
    local SCENE_CARD_TOP = 76
    local SCENE_CARD_BOTTOM = 104
    local SCENE_CARD_MARGIN = 40
    --The creator badge's inset from a scene's right edge; the chat button
    --moves left of the badge while a scene is up (see ApplyLocationMode).
    local SCENE_BADGE_HMARGIN = 28

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

    --A cream-edged "<- text" pill: the way back out of a scene, and out of
    --the town itself. Carries sceneStyles' eotwSceneBack rules, so it can
    --sit outside a scene panel.
    local BackButton = function(text, press)
        return gui.Panel{
            classes = { "eotwSceneBack" },
            styles = sceneStyles,
            width = "auto",
            height = 40,
            hpad = 16,
            borderBox = true,
            flow = "horizontal",
            hover = function(element)
                audio.FireSoundEvent("Mouse.Hover")
            end,
            press = function(element)
                audio.FireSoundEvent("Mouse.Click")
                press(element)
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
                text = text,
                fontSize = 17,
                bold = true,
                color = "#f6ead0",
                width = "auto",
                height = "auto",
                valign = "center",
            },
        }
    end

    --The top-left of a scene: the way back to the map, then the place's
    --name over a cream rule and a line about it.
    local SceneHeader = function(scene, side)
        return gui.Panel{
            floating = true,
            halign = side or "left",
            valign = "top",
            hmargin = 56,
            vmargin = 40,
            width = 620,
            height = "auto",
            flow = "vertical",

            BackButton("Back to Town", function()
                CloseLocation()
            end),

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
            --a cream rule, fading out to the right.
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
    --CreatorCredit.Backdrop; scene.video loops over the still), a shade down
    --the header's side for it to read on, the header, and a card holding
    --content -- on the right, or on the left when scene.cardSide = "left"
    --(the header then moves right). `side` (optional) goes in the free space
    --under the header, at the bottom of the header's side (the Guild's
    --project under way). The scene is opaque, so the map behind it takes no
    --clicks.
    local LocationScene = function(loc, cardWidth, content, side)
        local scene = loc.scene
        local cardLeft = scene.cardSide == "left"
        local headerSide = cond(cardLeft, "right", "left")
        local fadeFrom, fadeTo = 0, 1
        if cardLeft then
            fadeFrom, fadeTo = 1, 0
        end
        return CreatorCredit.Backdrop{
            width = panelWidth,
            height = panelHeight,
            image = scene.art,
            video = scene.video,
            aspect = scene.aspect,
            focusX = scene.focusX,
            --every EotW scene shows the creator's logo white.
            badge = { hmargin = SCENE_BADGE_HMARGIN, vmargin = 24, light = true },
            children = {
                gui.Panel{
                    floating = true,
                    halign = headerSide,
                    valign = "top",
                    width = 1000,
                    height = panelHeight,
                    interactable = false,
                    bgimage = "panels/square.png",
                    bgcolor = "black",
                    gradient = gui.Gradient{
                        point_a = { x = fadeFrom, y = 0.5 },
                        point_b = { x = fadeTo, y = 0.5 },
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
                    SceneHeader(scene, headerSide),
                    gui.Panel{
                        floating = true,
                        halign = headerSide,
                        valign = "bottom",
                        hmargin = 56,
                        bmargin = 90,
                        width = "auto",
                        height = "auto",
                        children = { side },
                    },
                    gui.Panel{
                        classes = { "eotwSceneCard" },
                        floating = true,
                        halign = cond(cardLeft, "left", "right"),
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
        id = "eotwTownHeroStrip",
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
                                --the hammer chip: Downtime Activities to spend.
                                showDowntime = true,
                                subtitle = function(tok)
                                    local className, ancestry, level = EotwRoster.HeroDetails(tok)
                                    local text = EotwRoster.FormatDetails(level, ancestry, className)
                                    if EotwRoster.TokenIsDying(tok) then
                                        text = "<color=#ff8f7a>Dying: needs a respite</color>"
                                    end
                                    return text
                                end,
                                --the town's cards open the EotW hero sheet
                                click = function()
                                    audio.FireSoundEvent("Mouse.Click")
                                    EotwHeroSheet.Show{ charid = heroid, context = "town" }
                                end,
                                --back to the guild: inactive, not deleted.
                                dismiss = {
                                    tooltip = "Dismiss Hero: send them back to the guild.",
                                    click = function()
                                        EotwRoster.SetActive(heroid, false)
                                    end,
                                },
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

    --A party board, the body of the Gate's or the Proving Pits' scene: its
    --title, the list RefreshGames renders (the week's encounter or the
    --Proving Pits encounters, parties forming and underway, or a party's own
    --view while you are in it), an error line and the board's controls.
    local PartyBoard = function(mode)
        local ui = m_partyUI[mode]
        local controls
        if mode == "gate" then
            controls = {
                gui.Button{
                    text = "Form a Party",
                    fontSize = 22,
                    width = 240,
                    height = 48,
                    hmargin = 8,
                    click = function(element)
                        local key = EncounterOfTheWeek.CurrentEncounterKey()
                        if key == nil then
                            ShowGamesError("This week's encounter has not been posted yet.")
                            return
                        end
                        ShowCreateDialog(key)
                    end,
                },
                gui.Button{
                    --shown by RefreshGames once the week has past encounters.
                    classes = { "collapsed" },
                    text = "Past Encounters",
                    fontSize = 22,
                    width = 240,
                    height = 48,
                    hmargin = 8,
                    create = function(element)
                        ui.pastButton = element
                    end,
                    click = function(element)
                        ShowPastEncountersDialog()
                    end,
                },
            }
        else
            controls = {
                gui.Button{
                    classes = { "collapsed" },
                    text = "Feedback on Your Encounters",
                    fontSize = 20,
                    width = 340,
                    height = 48,
                    hmargin = 8,
                    create = function(element)
                        ui.creatorButton = element
                    end,
                    click = function(element)
                        ShowCreatorFeedbackDialog()
                    end,
                },
            }
        end

        return gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",

            gui.Label{
                text = "",
                fontSize = 26,
                bold = true,
                color = "#efe4cc",
                width = "100%",
                height = "auto",
                bmargin = 4,
                create = function(element)
                    ui.title = element
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
                    ui.list = element
                    RefreshGames()
                    if mode == "gate" then
                        RefreshResumeState()
                    end
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
                    ui.error = element
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
            --leaving the party is the way back to the lists.
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "bottom",
                flow = "horizontal",
                create = function(element)
                    ui.controls = element
                end,
                children = controls,
            },
        }
    end

    gateScene = LocationScene(CityLocation("gate"), CARD_WIDTH_LIST.gate, PartyBoard("gate"))
    gateScene:SetClass("collapsed", true)
    dangerScene = LocationScene(CityLocation("danger"), CARD_WIDTH_LIST.danger, PartyBoard("danger"))
    dangerScene:SetClass("collapsed", true)

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
            --the badge's width depends on the creator: a licence watermark
            --spans a share of the screen (Czepeku's is a quarter of it).
            local hmargin = 20
            if m_locationId ~= nil then
                local info = CreatorCredit.ForArt(CityLocation(m_locationId).scene.art)
                if info ~= nil then
                    hmargin = SCENE_BADGE_HMARGIN + CreatorCredit.BadgeWidth(info.id, panelWidth) + 24
                end
            end
            chatButton.selfStyle.hmargin = hmargin
        end
    end

    CloseLocation = function()
        if m_locationId == nil then
            return
        end
        if m_locationOpenedAt ~= nil then
            EotwAnalytics.Track("eotw_location_close", {
                location = m_locationId,
                seconds = math.floor(dmhub.Time() - m_locationOpenedAt),
            })
            m_locationOpenedAt = nil
        end
        for _,scene in ipairs({ gateScene, dangerScene }) do
            if scene ~= nil and scene.valid then
                scene:SetClass("collapsed", true)
            end
        end
        if m_guildScene ~= nil and m_guildScene.valid then
            m_guildScene:DestroySelf()
        end
        m_guildScene = nil
        if m_innScene ~= nil and m_innScene.valid then
            m_innScene:DestroySelf()
        end
        m_innScene = nil
        if m_marketScene ~= nil and m_marketScene.valid then
            m_marketScene:DestroySelf()
        end
        m_marketScene = nil
        if m_hallScene ~= nil and m_hallScene.valid then
            m_hallScene:DestroySelf()
        end
        m_hallScene = nil
        m_locationId = nil
        ApplyLocationMode()
    end

    OpenLocation = function(id)
        if m_locationId == id or locationHost == nil or not locationHost.valid then
            return
        end
        CloseLocation()
        m_locationId = id
        m_locationOpenedAt = dmhub.Time()
        EotwAnalytics.Track("eotw_location_open", { location = id })
        if id == "gate" then
            gateScene:SetClass("collapsed", false)
            CreatorCredit.ReplayFade(gateScene)
            --re-check the resume row too: the lookup made when the screen
            --was built can come back empty if the lobby was not ready yet.
            RefreshResumeState()
            RefreshGames()
            --pick up encounter modules published since the town opened (a
            --community Encounter of the Week needs its backstory from it).
            EncounterOfTheWeek.RefreshPool(function()
                if not mod.unloaded and resultPanel ~= nil and resultPanel.valid then
                    RefreshGames()
                end
            end)
        elseif id == "danger" then
            dangerScene:SetClass("collapsed", false)
            CreatorCredit.ReplayFade(dangerScene)
            RefreshGames()
            FetchDangerStats()
            --the encounters on offer come from the pool: catch new ones.
            EncounterOfTheWeek.RefreshPool(function()
                if not mod.unloaded and resultPanel ~= nil and resultPanel.valid then
                    RefreshGames()
                end
            end)
        elseif id == "guild" then
            m_guildScene = LocationScene(CityLocation("guild"), 860, EotwRoster.GuildPanel(resultPanel),
                --the guild's project under way, if any, in the space on the left.
                EotwDowntime.ProjectSidePanel(resultPanel, "expand-guild", 620))
            locationHost:AddChild(m_guildScene)
        elseif id == "inn" then
            m_innScene = LocationScene(CityLocation("inn"), 820, EotwDowntime.InnPanel(resultPanel, function(where)
                OpenLocation(where)
            end),
                --the hunt for the Arcane Market, while it is under way.
                EotwDowntime.ProjectSidePanel(resultPanel, "find-arcane-market", 620))
            locationHost:AddChild(m_innScene)
            EotwRoster.Refresh()
        elseif id == "market" then
            m_marketScene = LocationScene(CityLocation("market"), 820, EotwMarket.MarketPanel(resultPanel))
            locationHost:AddChild(m_marketScene)
            EotwRoster.Refresh()
        elseif id == "hall" then
            --the Construction until the town has built the Hall, then the Hall.
            local loc = CityLocation("hall")
            if EotwRoster.HallBuilt() then
                loc.scene = HALL_SCENE
                m_hallScene = LocationScene(loc, 980, EotwRoster.HallPanel(resultPanel))
            else
                loc.scene = CONSTRUCTION_SCENE
                m_hallScene = LocationScene(loc, 820, EotwDowntime.ConstructionPanel(resultPanel))
            end
            locationHost:AddChild(m_hallScene)
            EotwRoster.Refresh()
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

        --in a party view the title gives way to Town Chat | Game Chat tabs.
        gui.Panel{
            classes = { "collapsed" },
            width = "94%",
            height = 40,
            halign = "center",
            vmargin = 16,
            flow = "horizontal",
            styles = {
                {
                    selectors = { "chatTab" },
                    bgcolor = "#ffffff0e",
                    borderWidth = 1,
                    borderColor = "#8f8a7f88",
                    opacity = 0.7,
                },
                {
                    selectors = { "chatTab", "hover" },
                    borderColor = "#e6dcc6",
                    opacity = 1,
                },
                {
                    selectors = { "chatTab", "selected" },
                    bgcolor = "#5a4a2acc",
                    borderColor = "#f6ead0",
                    opacity = 1,
                },
            },
            create = function(element)
                chatTabRow = element
            end,
            ChatTab("town", "Town Chat"),
            ChatTab("game", "Game Chat"),
        },

        gui.Label{
            fontSize = 16,
            color = Styles.textColor,
            opacity = 0.7,
            width = "94%",
            --two lines at most, so a busy town cannot push the input
            --off the bottom of the drawer.
            height = 42,
            textAlignment = "topleft",
            textOverflow = "ellipsis",
            halign = "center",
            text = "",
            create = function(element)
                presenceLabel = element
                RefreshPresence()
            end,
        },

        gui.Panel{
            width = "94%",
            height = "100%-214",
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
            moveToBottom = function(element)
                if m_chatStickBottom then
                    element.vscrollPosition = 0
                end
            end,
            scroll = function(element)
                m_chatStickBottom = element.vscrollPosition <= 0.02
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
            create = function(element)
                chatInput = element
            end,
            change = function(element)
                local text = (element.text or ""):match("^%s*(.-)%s*$")
                if text == "" or m_conn == nil then
                    return
                end
                element.text = ""
                --on the Game Chat tab the send targets that party's channel.
                local args = { text = text }
                if m_viewGameid ~= nil and m_chatTab == "game" then
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

    --closing forgets the dividers, so the next open places them afresh.
    local SetChatOpen = function(open)
        m_chatOpen = open
        m_chatDividers = {}
        m_chatStickBottom = true
        chatPanel:SetClass("collapsed", not open)
        RefreshChat()
    end

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
        --dialogs sit at EXIT_MODAL_DIALOG.
        escapePriority = 4,
        escape = function(element)
            --close the topmost town panel first: the chat drawer, then
            --an open location, and the town itself last.
            if chatPanel ~= nil and chatPanel.valid and not chatPanel:HasClass("collapsed") then
                SetChatOpen(false)
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
            pcall(EotwAnalytics.TownClosed, "enter_game")
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
            --a stale screen from an unloaded generation is about to be swept
            --and replaced; the replacement reports the visit.
            if not mod.unloaded then
                AnalyticsTownOpened()
            end
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
                m_conn = lobbiesApi:Connect(LOBBY_ID, EotwRoster.CityOptions())
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
            dmhub.SetSteamJoinTarget(nil)
            if m_conn ~= nil then
                EotwRoster.Detach(m_conn)
                m_conn:Disconnect()
                m_conn = nil
            end
            --a no-op when the town already closed for a game load; skipped
            --for a stale screen swept on return (its generation is unloaded).
            if not mod.unloaded then
                pcall(EotwAnalytics.TownClosed, "close")
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
            --Keep the normal cursor while draggable so panning doesn't show the
            --"forbidden" drag cursor (a draggable panel with no drop target).
            hoverCursor = "default",
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

        --top-left: the way back to the titlescreen, then the town's name
        --plaque, who is here, and the connection state. Collapsed together
        --while a scene (with its own back button) is up.
        gui.Panel{
            floating = true,
            halign = "left",
            valign = "top",
            hmargin = 20,
            vmargin = 20,
            width = 440,
            height = "auto",
            flow = "vertical",
            create = function(element)
                townPlaque = element
            end,

            BackButton("Back to Title Screen", function(element)
                element:FireEventOnParents("closeEncounterOfTheWeek")
            end),

            gui.Panel{
                classes = { "eotwPlaque" },
                tmargin = 12,
                width = 440,
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
                        --we are always present ourselves, so 0 means the
                        --snapshot has not arrived yet: stay blank until it does.
                        if n == 0 then
                            element.text = ""
                            return
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
        },

        heroStrip,

        --the open location's full-screen scene, over the town and under the
        --chat (see OpenLocation).
        gui.Panel{
            floating = true,
            width = "100%",
            height = "100%",
            flow = "none",
            create = function(element)
                locationHost = element
            end,
            gateScene,
            dangerScene,
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
                SetChatOpen(chatPanel:HasClass("collapsed"))
            end,
        },

        chatPanel,

        --watches for the moment to play the Blue Fish Inn's reveal.
        gui.Panel{
            floating = true,
            width = 1,
            height = 1,
            interactable = false,
            thinkTime = 0.5,
            think = function(element)
                TryAcceptInvite()
                MaybeShowWelcome()
                MaybePlayInnReveal()
                RevealFoundLocations()
                WatchCommunityProjects()
                RevealHall()
                --the beta survey waits for the inn's reveal to finish.
                if not m_innRevealActive then
                    MaybeShowSurvey()
                end
            end,
        },

        --keeps our forming party advertised as our Steam "Join Game".
        gui.Panel{
            floating = true,
            width = 1,
            height = 1,
            interactable = false,
            thinkTime = 3,
            think = function(element)
                PushSteamJoinTarget()
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
                MaybeShowDebrief()
                MaybeShowOfferedOutcomes()
            elseif string.starts_with(path, "/city/week") then
                --the week rotated: the boards re-sort the encounters, and
                --the Proving Pits may have opened (an earlier win of the
                --new past encounter counts).
                RefreshGames()
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
                RefreshPresence()
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
                MaybeShowDebrief()
                MaybeShowOfferedOutcomes()
                --a respite or project roll the last connection did not finish.
                dmhub.Schedule(2, function()
                    if not mod.unloaded then
                        EotwDowntime.ResumePending()
                    end
                end)
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
