local mod = dmhub.GetModLoading()

-- Games of chance played in turns (liars-dice-brief.md #16): the second flow of the
-- GameOfChance layer, beside GameOfChance.lua's deal-and-bet flow. A turns game (Liar's
-- dice) plays challenges made of turns -- players' moves sent as requests, NPC turns run
-- by the host -- and reports when a challenge decides a round. The layer keeps what both
-- flows share: setup and presets, rounds won and lost, stakes, Play again, Reset, the log,
-- the frame, and a store for the host's secrets.
--
-- Host secrets (#15): what nobody may read from the shared data (the gamblers' hidden
-- dice) lives only on the host's machine, in a per-game preference keyed by puzzle id. It
-- survives a Lua reload or restart there; a new host finds none, and the game deals with
-- that (Liar's dice shakes the challenge again).

---@class ChanceTurnsEvent
---@field log string|nil a line for the game log
---@field chat string|nil a line for the chat
---@field round "win"|"lose"|nil this challenge decided a round
---@field final boolean|nil with round: it also decides the game (every gambler out of dice)
---@field bettor {user: string, tokenid: string}|nil who the stake belongs to (the champion)

---@class ChanceTurnsView
---@field g table the game's public data
---@field phase string ready, playing, revealed or over
---@field eff table the setup in force
---@field readonly boolean
---@field me string this viewer's userid
---@field large boolean
---@field reduceMotion boolean
---@field skipped boolean
---@field request fun(args: table) send a move to the host ({kind = "move", ...})

---@class ChanceTurnsGameDef
---@field id string
---@field name string
---@field flow "turns"
---@field howToPlay? string|fun(config: table): string the puzzle frame's "?" text (PuzzleTypeDef.howToPlay)
---@field presets table<string, table> preset id -> setup values
---@field presetOptions {id: string, text: string}[] the setup's first choice
---@field fields? PuzzleField[] the game's own setup, shown under Customize
---@field startLabel fun(g: table): string the button that starts a challenge
---@field CanStart? fun(g: table, eff: table, req: table, userid: string): boolean may this request start a challenge?
---@field NewGame fun(eff: table, random: (fun(k: integer): integer)): table public data for a new game
---@field Start fun(g: table, eff: table, random: (fun(k: integer): integer), secret: table, events: ChanceTurnsEvent[], req: table, userid: string) begin a challenge
---@field Move fun(g: table, eff: table, secret: table, req: table, userid: string, random: (fun(k: integer): integer), events: ChanceTurnsEvent[], phase: string): boolean apply a player's move (any phase but "over"); true if anything changed
---@field HostStep fun(g: table, eff: table, secret: table, now: number, random: (fun(k: integer): integer), events: ChanceTurnsEvent[], pace: number): boolean run turns that are due; pace scales NPC timing (2 = twice as slow, below 1 = quicker); true if anything changed
---@field EndNow? fun(g: table, secret: table) the Director ended the game mid-challenge: lift the cups
---@field Status fun(g: table, eff: table, phase: string, viewer: string): string the step line
---@field Board fun(): Panel built once; receives the "chanceTurns" event with a ChanceTurnsView

GameOfChanceTurns = {}

local S = GameOfChance.Shared

--------------------------------------------------------------------------------
-- Host secrets
--------------------------------------------------------------------------------

local g_secrets = setting{
    id = "gameofchance:secrets",
    storage = "pergamepreference",
    default = {},
}

---@param value any
---@return any
local function DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = DeepCopy(v)
    end
    return out
end

--The host's secret for a puzzle: a copy, empty when this machine has none.
---@param id string
---@return table
function GameOfChanceTurns.ReadSecret(id)
    local all = g_secrets:Get()
    if type(all) ~= "table" or type(all[id]) ~= "table" then
        return {}
    end
    return DeepCopy(all[id])
end

---@param id string
---@param secret table|nil nil forgets it
function GameOfChanceTurns.WriteSecret(id, secret)
    local all = DeepCopy(g_secrets:Get())
    if type(all) ~= "table" then
        all = {}
    end
    all[id] = DeepCopy(secret)
    g_secrets:Set(all)
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

---@param game ChanceTurnsGameDef
---@return PuzzleField[]
local function Fields(game)
    local IsCustom = S.IsCustom
    local presetOptions = {}
    for i, option in ipairs(game.presetOptions) do
        presetOptions[i] = option
    end
    presetOptions[#presetOptions + 1] = { id = "custom", text = "Customize" }
    local fields = {
        { id = "preset", type = "choice", label = "Game", default = presetOptions[1].id, options = presetOptions },
        { id = "difficulty", type = "choice", label = "Difficulty", default = "medium", visible = IsCustom, options = {
            { id = "easy", text = "Easy" },
            { id = "medium", text = "Medium" },
            { id = "hard", text = "Hard" },
        } },
        { id = "tests", type = "toggle", label = "Offer tests", default = true, visible = IsCustom },
        { id = "stake", type = "choice", label = "Stake", default = "none", visible = IsCustom, options = {
            { id = "none", text = "Nothing" },
            { id = "gold", text = "Gold" },
            { id = "wealth", text = "1 Wealth" },
            { id = "recovery", text = "A Recovery (can only be lost)" },
        } },
        { id = "stakeGold", type = "number", label = "Gold staked", default = 5, min = 1, max = 500,
            visible = function(config) return IsCustom(config) and config.stake == "gold" end },
        { id = "wins", type = "number", label = "Rounds to win", default = 2, min = 1, max = 5, visible = IsCustom },
        { id = "losses", type = "number", label = "Rounds the party can lose", default = 2, min = 1, max = 5, visible = IsCustom },
        { id = "onLoss", type = "choice", label = "When the party loses", default = "again", visible = IsCustom, options = {
            { id = "again", text = "Offer another game" },
            { id = "fail", text = "The puzzle fails" },
        } },
    }
    for _, field in ipairs(game.fields or {}) do
        local f = field
        local visible = f.visible
        f.visible = function(config)
            return IsCustom(config) and (visible == nil or visible(config))
        end
        fields[#fields + 1] = f
    end
    return fields
end

---@param game ChanceTurnsGameDef
---@param config table
---@return table
local function Eff(game, config)
    return S.Effective(config, game.presets)
end

---@param game ChanceTurnsGameDef
---@param eff table
---@return table
local function NewState(game, eff)
    return {
        game = 1,
        round = 0,
        phase = "ready",
        wins = 0,
        losses = 0,
        log = "",
        req = {},
        done = {},
        g = game.NewGame(eff, Puzzle.SeededRandom(dmhub.GenerateGuid())),
    }
end

--------------------------------------------------------------------------------
-- The host
--------------------------------------------------------------------------------

--NPC turns run at the slowest present player's pace; quicker only when every player
--there chose not to watch.
local MAX_PACE = 3

---@param id string
---@param state table
---@return number
local function Pace(id, state)
    local views = state.views or {}
    local slowest = nil
    for _, userid in ipairs(Puzzle.PresentUsers(id)) do
        local factor = tonumber(views[userid])
        if factor == nil then
            factor = 1
        end
        slowest = math.max(slowest or 0, factor)
    end
    if slowest == nil then
        return 1
    end
    if slowest <= 0 then
        return 0.25
    end
    return math.min(MAX_PACE, slowest)
end

--Apply what a game step reported: log and chat lines, and a decided round.
---@param state table
---@param eff table
---@param events ChanceTurnsEvent[]
---@param effects table[]
local function ApplyEvents(state, eff, events, effects)
    for _, e in ipairs(events) do
        if e.log ~= nil then
            S.AppendLog(state, e.log)
        end
        if e.chat ~= nil then
            effects[#effects + 1] = { chat = e.chat }
        end
        if e.round ~= nil and state.phase == "playing" then
            state.round = (state.round or 0) + 1
            if e.final then
                --this round settles the game whatever the count.
                if e.round == "win" then
                    state.wins = math.max(state.wins or 0, eff.wins - 1)
                else
                    state.losses = math.max(state.losses or 0, eff.losses - 1)
                end
            end
            S.FinishRound(state, eff, e.round, e.bettor, effects)
        end
    end
end

---@param game ChanceTurnsGameDef
---@param id string
local function HostTick(game, id)
    local status = Puzzle.Status(id)
    if status.solved or status.failed then
        return
    end
    local secret = GameOfChanceTurns.ReadSecret(id)
    local before = json(secret)
    local effects = {}
    local after = {}
    local random = Puzzle.SeededRandom(dmhub.GenerateGuid())
    Puzzle.Change(id, function(state, config)
        local eff = Eff(game, config)
        local changed = false
        state.g = state.g or game.NewGame(eff, random)

        local function Handle(_, _, req, userid, _)
            local kind = req.kind
            local events = {}
            if req.game ~= nil and req.game ~= state.game then
                return true
            end
            if kind == "start" then
                if (state.phase == "ready" or state.phase == "revealed")
                    and (game.CanStart == nil or game.CanStart(state.g, eff, req, userid)) then
                    state.phase = "playing"
                    game.Start(state.g, eff, random, secret, events, req, userid)
                    changed = true
                end
            elseif kind == "move" then
                if state.phase ~= "over" and game.Move(state.g, eff, secret, req, userid, random, events, state.phase) then
                    changed = true
                end
            elseif kind == "view" then
                --how slowly this player watches (shell #43): 0 = doesn't watch, 2 = slowly.
                state.views = state.views or {}
                local factor = math.max(0, math.min(MAX_PACE, tonumber(req.factor) or 1))
                if state.views[userid] ~= factor then
                    state.views[userid] = factor
                    changed = true
                end
            elseif kind == "playagain" then
                if state.phase == "over" and state.result ~= "won" and eff.onLoss == "again" then
                    local fresh = NewState(game, eff)
                    fresh.game = (state.game or 1) + 1
                    fresh.log = state.log
                    fresh.req = state.req
                    fresh.done = state.done
                    fresh.paidAll = state.paidAll
                    for k in pairs(state) do
                        state[k] = nil
                    end
                    for k, v in pairs(fresh) do
                        state[k] = v
                    end
                    for k in pairs(secret) do
                        secret[k] = nil
                    end
                    S.AppendLog(state, string.format("%s plays again.", Puzzle.UserName(userid)))
                    changed = true
                end
            end
            ApplyEvents(state, eff, events, effects)
            return true
        end
        if Puzzle.ProcessRequests(id, state, Handle, after) then
            changed = true
        end
        if state.phase == "playing" then
            local events = {}
            if game.HostStep(state.g, eff, secret, dmhub.serverTime, random, events, Pace(id, state)) then
                changed = true
            end
            if #events > 0 then
                ApplyEvents(state, eff, events, effects)
                changed = true
            end
        end
        if not changed then
            return false
        end
    end, "Game of chance")

    if json(secret) ~= before then
        GameOfChanceTurns.WriteSecret(id, secret)
    end
    for _, fn in ipairs(after) do
        local ok, err = pcall(fn)
        if not ok then
            print("PUZZLE:: request follow-up failed for", id, err)
        end
    end
    S.RunEffects(id, effects, game.presets)
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

---@param game ChanceTurnsGameDef
---@param ctx PuzzleContext
---@return Panel
local function Render(game, ctx)
    local m_ctx = ctx
    local m_viewSent = nil ---@type string|nil
    local resultPanel
    local board
    local stepLabel
    local scoreLabel
    local logLabel
    local startButton
    local againButton

    local function State()
        return m_ctx.state or {}
    end

    local function Request(args)
        args.game = State().game
        Puzzle.Request(m_ctx.id, args)
    end

    --the last lines of the game log; the board keeps the turn-by-turn history.
    local function LogTail(text, lines)
        local all = {}
        for line in string.gmatch(tostring(text or ""), "[^\n]+") do
            all[#all + 1] = line
        end
        local out = {}
        for i = math.max(1, #all - lines + 1), #all do
            out[#out + 1] = all[i]
        end
        return table.concat(out, "\n")
    end

    local function Refresh()
        if resultPanel == nil or not resultPanel.valid then
            return
        end
        local state = State()
        local eff = Eff(game, m_ctx.config or {})
        local phase = state.phase or "ready"
        local readonly = m_ctx.readonly == true
        --tell the host how this player watches, once per change: what this window last
        --sent, not the saved state, so the write this causes can't send it again.
        local factor = S.skipSetting:Get() == true and 0 or (S.slowSetting:Get() == true and 2 or 1)
        local viewKey = string.format("%s:%s", tostring(state.game), tostring(factor))
        if not readonly and phase ~= "over" and m_viewSent ~= viewKey and (state.views or {})[dmhub.userid] ~= factor then
            m_viewSent = viewKey
            Request({ kind = "view", factor = factor })
        end
        board:FireEventTree("chanceTurns", {
            g = state.g or {},
            phase = phase,
            eff = eff,
            readonly = readonly,
            me = dmhub.userid,
            large = S.largeSetting:Get() == true,
            reduceMotion = ThemeEngine.GetAccessibility().reduceMotion == true,
            skipped = S.skipSetting:Get() == true,
            request = function(args)
                if not readonly then
                    Request(args)
                end
            end,
        })

        local step
        if readonly and m_ctx.editing then
            step = "The game is paused while the page is edited."
        elseif phase == "over" then
            if state.result == "won" then
                step = "The party won the game."
            elseif state.result == "ended" then
                step = "The Director ended the game."
            else
                step = cond(eff.onLoss == "again", "The party lost. Another game is on offer.", "The party lost the game.")
            end
        else
            step = game.Status(state.g or {}, eff, phase, dmhub.userid)
        end
        stepLabel.text = step

        local stake = S.StakeText(eff)
        scoreLabel.text = string.format("Won %d of %d, lost %d of %d.%s", state.wins or 0, eff.wins, state.losses or 0, eff.losses,
            stake ~= nil and string.format(" Stake: %s.", stake) or "")

        logLabel.text = LogTail(state.log, 8)
        logLabel:SetClass("collapsed", logLabel.text == "")

        startButton.text = game.startLabel(state.g or {})
        startButton:SetClass("collapsed", readonly or not (phase == "ready" or phase == "revealed"))
        againButton:SetClass("collapsed", readonly or not (phase == "over" and state.result ~= "won" and eff.onLoss == "again"))
    end

    local function Button(text, click)
        return gui.Button{
            classes = {"sizeS", "collapsed"},
            text = text,
            width = 180,
            height = 28,
            halign = "left",
            hmargin = 3,
            vmargin = 2,
            click = function(element)
                click()
            end,
        }
    end

    board = game.Board()
    stepLabel = gui.Label{ classes = {"sizeM", "bold"}, width = 700, height = "auto", halign = "left", tmargin = 4, text = "" }
    scoreLabel = gui.Label{ classes = {"sizeS"}, width = 700, height = "auto", halign = "left", text = "" }
    logLabel = gui.Label{ classes = {"sizeS", "collapsed"}, width = 700, height = "auto", halign = "left", tmargin = 4, text = "" }
    startButton = Button("", function()
        local tok = Puzzle.MyHero()
        Request({ kind = "start", tokenid = tok ~= nil and tok.charid or nil })
    end)
    againButton = Button("Play again", function() Request({ kind = "playagain" }) end)

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        refreshPuzzle = function(element, newCtx)
            m_ctx = newCtx
            Refresh()
        end,
        board,
        stepLabel,
        scoreLabel,
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            tmargin = 4,
            startButton,
            againButton,
        },
        logLabel,
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            tmargin = 6,
            gui.Check{
                classes = {"sizeS"},
                width = "auto",
                height = 22,
                hmargin = 4,
                text = "Show turns slowly",
                value = S.slowSetting:Get() == true,
                change = function(element) S.slowSetting:Set(element.value) Refresh() end,
            },
            gui.Check{
                classes = {"sizeS"},
                width = "auto",
                height = 22,
                hmargin = 4,
                text = "Don't watch, just play",
                value = S.skipSetting:Get() == true,
                change = function(element) S.skipSetting:Set(element.value) Refresh() end,
            },
            gui.Check{
                classes = {"sizeS"},
                width = "auto",
                height = 22,
                hmargin = 4,
                text = "Larger view",
                value = S.largeSetting:Get() == true,
                change = function(element) S.largeSetting:Set(element.value) Refresh() end,
            },
        },
    }
    return resultPanel
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

---@type table<string, ChanceTurnsGameDef>
local g_turnsGames = {}

--The Director solved or bypassed a game mid-challenge: lift the cups, log it, move no
--stake (C16). Runs on the host.
Puzzle.RegisterOutcomeHandler("gameofchanceturns", {
    apply = function(id, outcome, status)
        local typeid = Puzzle.GetTypeId(id)
        local game = typeid ~= nil and g_turnsGames[typeid] or nil
        if game == nil then
            return
        end
        local state = Puzzle.ReadState(id)
        if state == nil or state.phase ~= "playing" then
            return
        end
        local secret = GameOfChanceTurns.ReadSecret(id)
        Puzzle.Change(id, function(st)
            if st.phase ~= "playing" then
                return false
            end
            if game.EndNow ~= nil then
                game.EndNow(st.g, secret)
            end
            st.phase = "over"
            st.result = "ended"
            S.AppendLog(st, "The Director ends the game.")
        end, "Game of chance ended")
    end,
    undo = function(id, status) end,
})

--Called by GameOfChance.Register for a game with flow = "turns".
---@param game ChanceTurnsGameDef
function GameOfChanceTurns.Register(game)
    g_turnsGames[game.id] = game
    PuzzleType.Register{
        id = game.id,
        name = game.name,
        fields = Fields(game),
        noTimeLimit = true,
        howToPlay = game.howToPlay,
        NewState = function(config, ctx)
            return NewState(game, Eff(game, config))
        end,
        IsSolved = function(state, config)
            return state.result == "won"
        end,
        IsFailed = function(state, config, now)
            return state.result == "lost" and Eff(game, config).onLoss == "fail"
        end,
        Render = function(ctx)
            return Render(game, ctx)
        end,
        HostTick = function(id)
            HostTick(game, id)
        end,
    }
end
