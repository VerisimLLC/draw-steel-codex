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
--The screen connects to the "eotw" Lobby -- a server-arbitrated
--chat/presence/roster space that is NOT a game -- through the engine's
--lobbies bridge (lobbies.Connect). All lobby state is written server-side;
--this UI only renders the document and sends typed requests.

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

--The well-known lobby id, and staging until EotW nears release (the whole
--mode is dev-gated, and the staging worker is where the lobby DO is tested).
local LOBBY_ID = "eotw"
local LOBBY_OPTIONS = { staging = true }

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

--The warmer panel. Floating and 1x1, so it takes part in no layout.
local function CreatePortraitWarmer()
    --ids already given a panel; a warm panel is never removed, so the
    --texture stays resident for as long as the screen is open.
    local m_warmed = {}

    return gui.Panel{
        id = "eotwPortraitWarmer",
        interactable = false,
        floating = true,
        halign = "left",
        valign = "top",
        width = 1,
        height = 1,
        flow = "none",

        --deferred a tick rather than fired inline: the first pass adds
        --children, and doing that while the panel is still starting is
        --asking for trouble.
        create = function(element)
            element:ScheduleEvent("warmPortraits", 0.01, PORTRAIT_WARM_PASSES)
        end,

        warmPortraits = function(element, passesLeft)
            local added = 0
            for _,id in ipairs(EligiblePortraitImageIds()) do
                if m_warmed[id] == nil then
                    m_warmed[id] = true
                    added = added + 1
                    element:AddChild(gui.Panel{
                        interactable = false,
                        width = 1,
                        height = 1,
                        halign = "left",
                        valign = "top",
                        bgimage = id,
                        bgcolor = "white",
                    })
                end
            end

            --Done: the pregen cache has landed and this pass found nothing
            --new, so the eligible set is complete. While m_pregens is still
            --nil the snapshot (or its art registration) is in flight, so
            --keep looking until the passes run out.
            if m_pregens ~= nil and added == 0 then
                return
            end
            if passesLeft > 1 then
                element:ScheduleEvent("warmPortraits", PORTRAIT_WARM_RESCAN_SECONDS, passesLeft - 1)
            end
        end,
    }
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

local CreateScreen

--Opens the Encounter of the Week screen over the titlescreen, hosted on
--CodexTitlescreenRoot the same way the shop screen is. No-op if the screen
--is already open or we are not at the titlescreen.
function EncounterOfTheWeek.ShowScreen()
    if m_screen ~= nil and m_screen.valid then
        --a screen hidden for a game load (see the beginLoading handler)
        --is still ours: reopen it rather than leave the player with a link
        --that does nothing.
        m_screen.data.loadingUp = false
        m_screen:SetClass("hidden", false)
        return
    end

    local root = rawget(_G, "CodexTitlescreenRoot")
    if root == nil or not root.valid then
        return
    end

    --make sure the pregen list is (being) loaded by the time the player
    --reaches a game's slot picker.
    EncounterOfTheWeek.CachePregens()

    m_screen = CreateScreen{ titlescreen = root }
    root:AddChild(m_screen)
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
    end

    local areaStyles = {
        {
            selectors = { "eotw-area" },
            bgcolor = "#000000aa",
            borderWidth = 2,
            borderColor = Styles.textColor,
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

    --forward decls (assigned below; captured by earlier click handlers).
    local OpenGameView = nil
    local CloseGameView = nil
    local BuildGameView = nil
    local ShowAddHeroDialog = nil
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
                if OpenGameView ~= nil then
                    OpenGameView(gameid)
                end
            end,
            error = ShowGamesError,
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
        if record ~= nil then
            myHeroes = MyHeroesCopy(record)
            slotsFilled = record.slotsFilled or 0
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
            if h.kind == "lobby" then
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

        lobby:EnterGame(gameid, function()
            local eotwGame = rawget(_G, "EncounterOfTheWeekGame")
            if eotwGame ~= nil and eotwGame.SetupOnArrival ~= nil then
                eotwGame.SetupOnArrival{
                    heroes = myHeroes,
                    clipboardIds = clipboardIds,
                    numHeroes = slotsFilled,
                    members = members,
                }
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
        local slotsTotal = record.slotsTotal or 7
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
            width = "96%",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "#ffffff11",
            pad = 8,
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
                    text = string.format("Hosted by %s -- %d/%d heroes", record.hostName or "?", slotsFilled, slotsTotal),
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
    --pregens come from the module snapshot cache, and MY lobby heroes live
    --in the local lobby game. Other players' lobby heroes exist only on
    --their machines, so they render with a silhouette placeholder.
    local ResolveHeroToken = function(heroEntry, mine)
        if heroEntry.kind == "pregen" then
            return EncounterOfTheWeek.GetPregenToken(heroEntry.id)
        end
        if mine then
            return dmhub.GetCharacterById(heroEntry.id)
        end
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
            --instead of an empty frame.
            if IsUnresolvableAssetId(portrait) then
                portrait = nil
                portraitRect = nil
            end
            if IsUnresolvableAssetId(frameBg) then
                frameBg = nil
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

        local tok = ResolveHeroToken(heroEntry, mine)

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
            ownerText = ownerText,
            chipText = chipText,
            born = params.born,
            extras = extras,
        }
    end

    --The "+" card at the end of the lineup. Hidden entirely once the game
    --is full (7 heroes); shown dimmed when only OUR per-player cap (4) is
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
        local slotsTotal = record.slotsTotal or 7
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
            text = string.format("Hosted by %s -- players: %s", record.hostName or "?", cond(#memberNames > 0, table.concat(memberNames, ", "), "none yet")),
            fontSize = 18,
            color = Styles.textColor,
            opacity = 0.8,
            width = "96%",
            height = "auto",
            halign = "center",
        }

        --slot list: every claimed hero (host's first), then open slots.
        children[#children+1] = gui.Label{
            text = string.format("Hero Slots (%d/%d filled; 3 needed to begin)", slotsFilled, slotsTotal),
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
        --Begin: host-only. Enabled at 3-7 filled slots (the server caps
        --at slotsTotal, so >= 3 is the live gate; the server re-checks).
        --A granted launch flips the roster record to "launched": the HOST
        --enters via CheckLaunchedGames and runs setup in-game; members
        --wait for the game-side "ready-game" signal to flip the record to
        --"ready" before entering (see CheckLaunchedGames).
        if isHost and isOpen then
            local canBegin = slotsFilled >= 3 and slotsFilled <= slotsTotal
            buttons[#buttons+1] = gui.Button{
                text = "Begin",
                fontSize = 20,
                width = 160,
                height = 44,
                hmargin = 6,
                opacity = cond(canBegin, 1, 0.45),
                click = function()
                    if not canBegin then
                        ShowGamesError(string.format("Need at least 3 heroes to begin (%d/%d filled).", slotsFilled, slotsTotal))
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
            width = "96%",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "#334422aa",
            pad = 8,
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

    local RefreshGames = function()
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
                gamesListPanel.children = BuildGameView(m_viewGameid, record)
                if gamesTitleLabel ~= nil and gamesTitleLabel.valid then
                    gamesTitleLabel.text = "Game Lobby"
                end
                --no back button here: leaving the game (Abandon/Leave) is
                --the only way back to the games list. The collapsed button
                --frees its space to the list so a full 7-slot roster plus
                --the control row fits without a scrollbar.
                if createGameButton ~= nil and createGameButton.valid then
                    createGameButton:SetClass("collapsed", true)
                end
                gamesListPanel.selfStyle.height = "100%-100"
                return
            end
        end

        if gamesTitleLabel ~= nil and gamesTitleLabel.valid then
            gamesTitleLabel.text = "Games"
        end
        if createGameButton ~= nil and createGameButton.valid then
            createGameButton:SetClass("collapsed", false)
        end
        gamesListPanel.selfStyle.height = "100%-160"

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
        for _,gameid in ipairs(ids) do
            local record = games[gameid]
            --private games are never listed for anyone but their host.
            if record.public == true or record.hostUserid == dmhub.loginUserid then
                children[#children+1] = MakeGameRow(gameid, record)
            end
        end

        if #children == 0 then
            children[1] = EmptyNote("No games are waiting right now. Create one below!")
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
        local PickerCard = function(spec, tok)
            local chipText = nil
            if spec.kind == "pregen" then
                chipText = "Pregen"
            end
            return MakeCardPanel{
                tok = tok,
                name = spec.name,
                details = FormatHeroDetails(spec.level, spec.ancestry, spec.className),
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

        --our local titlescreen heroes.
        rows[#rows+1] = SectionTitle("Your Heroes")
        local myCards = {}
        for _,token in ipairs(table.values(dmhub.GetAllCharacters())) do
            local charid = token.charid
            if charid ~= nil and not claimed[charid] then
                myCards[#myCards+1] = PickerCard({
                    kind = "lobby",
                    id = charid,
                    name = token.name or "Unnamed Hero",
                    className = GetHeroClassName(token),
                    ancestry = GetHeroAncestry(token),
                    level = GetHeroLevel(token),
                }, token)
            end
        end
        if #myCards == 0 then
            rows[#rows+1] = EmptyNote("No available heroes. Create one on the titlescreen first.")
        else
            rows[#rows+1] = CardGrid(myCards)
        end

        --pregens from the weekly module (may still be loading, or the
        --module may not be published yet).
        rows[#rows+1] = SectionTitle("Pregenerated Heroes")
        local pregens = EncounterOfTheWeek.GetPregens()
        if pregens == nil then
            rows[#rows+1] = EmptyNote("Pregenerated heroes are not available right now.")
        elseif #pregens == 0 then
            rows[#rows+1] = EmptyNote("This week's module has no pregenerated heroes.")
        else
            local pregenCards = {}
            for _,pregen in ipairs(pregens) do
                if not claimed[pregen.id] then
                    pregenCards[#pregenCards+1] = PickerCard({
                        kind = "pregen",
                        id = pregen.id,
                        name = pregen.name,
                        className = pregen.className,
                        ancestry = pregen.ancestry,
                        level = pregen.level,
                    }, EncounterOfTheWeek.GetPregenToken(pregen.id))
                end
            end
            rows[#rows+1] = CardGrid(pregenCards)
        end

        dlg = gui.Panel{
            floating = true,
            width = 1040,
            height = 740,
            halign = "center",
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = "#111111f8",
            borderWidth = 2,
            borderColor = Styles.textColor,
            flow = "vertical",
            styles = { Styles.Default },

            captureEscape = true,
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
        local nameInput = nil
        local dialogStatusLabel = nil
        local dlg = nil

        --default the game name to the creator's name ("David's Game"),
        --prefilled so it can be edited or cleared.
        local defaultName = "Encounter of the Week"
        local myName = dmhub.GetDisplayName(dmhub.loginUserid)
        if myName ~= nil and myName ~= "" then
            defaultName = myName .. "'s Game"
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
                args = { name = name, public = m_public },
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
            width = 560,
            height = 340,
            halign = "center",
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = "#111111f8",
            borderWidth = 2,
            borderColor = Styles.textColor,
            flow = "vertical",
            styles = { Styles.Default },

            captureEscape = true,
            escape = function(element)
                element:DestroySelf()
            end,

            gui.Label{
                text = "Create a Game",
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
                placeholderText = "Name your game...",
                create = function(element)
                    nameInput = element
                    element.text = defaultName
                end,
            },

            gui.Check{
                text = "Public game (anyone can join)",
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

    --── the screen ──────────────────────────────────────────────────────

    resultPanel = gui.Panel{
        id = "encounterOfTheWeekScreen",
        classes = { "framedPanel" },
        floating = true,
        width = panelWidth,
        height = panelHeight,
        uiscale = uiscale,
        halign = "center",
        valign = "center",
        styles = {
            Styles.Default,
            Styles.Panel,
        },

        captureEscape = true,
        escape = function(element)
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

        --Keep our roster records alive: the lobby expires a game 5 minutes
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
                m_conn:Disconnect()
                m_conn = nil
            end
        end,

        gui.CloseButton{
            floating = true,
            halign = "right",
            valign = "top",
            hmargin = 12,
            vmargin = 12,
            click = function(element)
                element:FireEventOnParents("closeEncounterOfTheWeek")
            end,
        },

        --content column, authored inside the 1920-wide logical space.
        gui.Panel{
            width = 1600,
            height = "94%",
            halign = "center",
            valign = "center",
            flow = "vertical",

            gui.Label{
                text = "Encounter of the Week",
                fontSize = 48,
                bold = true,
                color = Styles.textColor,
                width = "auto",
                height = "auto",
                halign = "center",
                vmargin = 12,
            },

            gui.Label{
                text = "Each week a new encounter awaits. Gather a party of 3-7 heroes -- your own or pregenerated ones -- and take on a battle where the Codex's Monster AI runs the opposition. Join a public game below, or create your own and invite others.",
                fontSize = 22,
                color = Styles.textColor,
                width = 1100,
                height = "auto",
                halign = "center",
                textAlignment = "center",
                vmargin = 8,
            },

            --connection status line (blank while healthy).
            gui.Label{
                fontSize = 18,
                color = "#ffcc66",
                width = "auto",
                height = 24,
                halign = "center",
                create = function(element)
                    statusLabel = element
                    RefreshStatus()
                end,
            },

            --lobby row: games list left, chat + presence right.
            gui.Panel{
                width = "100%",
                height = 800,
                flow = "horizontal",
                halign = "center",
                vmargin = 12,

                --games roster, rendered from /state/games.
                gui.Panel{
                    classes = { "eotw-area" },
                    bgimage = "panels/square.png",
                    width = 1080,
                    height = "100%",
                    halign = "left",
                    flow = "vertical",
                    styles = areaStyles,

                    AreaTitle("Games", function(element)
                        gamesTitleLabel = element
                    end),

                    gui.Panel{
                        width = "100%",
                        height = "100%-160",
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

                    --error line for rejected roster requests (join on a full
                    --game, second hosted game, etc).
                    gui.Label{
                        fontSize = 16,
                        color = "#ff8888",
                        width = "94%",
                        height = 22,
                        halign = "center",
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

                    --hidden while a game lobby view is open (RefreshGames
                    --collapses it); leaving the game is the way back.
                    gui.Button{
                        text = "Create Game",
                        fontSize = 24,
                        width = 240,
                        height = 50,
                        halign = "center",
                        vmargin = 10,
                        create = function(element)
                            createGameButton = element
                        end,
                        click = function(element)
                            ShowCreateDialog()
                        end,
                    },
                },

                gui.Panel{ width = 20, height = 1 },

                --chat + presence, rendered from /chat and /presence.
                gui.Panel{
                    classes = { "eotw-area" },
                    bgimage = "panels/square.png",
                    width = 500,
                    height = "100%",
                    halign = "right",
                    flow = "vertical",
                    styles = areaStyles,

                    AreaTitle("Lobby Chat", function(element)
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
                        height = "100%-160",
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

                    --error line for rejected sends (rate limit etc); clears
                    --itself a few seconds after appearing.
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
                            --inside a game lobby view the send targets that
                            --game's private channel.
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
                },
            },
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
