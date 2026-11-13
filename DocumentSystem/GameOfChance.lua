local mod = dmhub.GetModLoading()

-- Games of chance: a thin layer on PuzzleType.Register for games played against
-- a dealer (the shell game first; see ShellGame.lua). The layer owns what every
-- such game shares -- the dealer (NPC or Director, honest or not), the "Watch the
-- dealer" test, stakes, rounds, pointing and betting, the synced deal, and
-- per-player viewing assists. A game supplies only its round: the board, what
-- its own test reveals, and how a bet is judged.
--
-- Winning the required rounds solves the puzzle; losing the allowed rounds fails
-- it (or the dealer offers another game). Everything secret (did the dealer
-- cheat this round?) is decided by the host only when it is first needed.
--
-- Flow of a round: anyone (or the Director, when dealing) asks to deal; the host
-- writes the round and a start time 3 s ahead; every client replays the deal from
-- that time, slowed for its own viewer; players point, test and talk; someone
-- places the bet; the host decides any cheat, judges, and moves to the reveal.
-- Players never write the flow themselves: they file requests the host applies.

---@class ChanceTest
---@field id string
---@field label string button text
---@field skill string skill name the test uses, e.g. "Alertness"
---@field Success fun(data: table): string what a successful test shows, e.g. "It ended under cup 2"

---@class ChanceGameDef
---@field id string
---@field name string
---@field fields? PuzzleField[] the game's own setup, shown under Customize
---@field perception? string characteristic id that slows a player's view (nil: none)
---@field test? ChanceTest the game's own test, rolled once per player per round
---@field cheatText string what the dealer's cheat was, e.g. "the dealer palmed the pea"
---@field DealRound fun(config: table, random: (fun(k: integer): integer), difficulty: string): table public round data (plain, no lists)
---@field Duration fun(data: table): number seconds the deal takes at normal speed
---@field Options fun(data: table): string[] what can be pointed at and bet on (keys 1..n)
---@field Judge fun(data: table, option: integer, cheated: boolean): "win"|"lose"|"push"
---@field Board fun(): Panel built once; receives the "chanceView" event with a ChanceView

---@class ChanceView
---@field data table|nil the round's data, nil before the first deal
---@field phase string ready, dealing, revealed or over
---@field countdown number|nil seconds until the deal starts
---@field t number|nil seconds into this viewer's replay of the deal (slowed time already undone)
---@field viewDone boolean this viewer has finished watching the deal
---@field skipped boolean this viewer chose not to watch
---@field reduceMotion boolean
---@field large boolean
---@field pointers table<integer, string[]> option -> names of players pointing at it (empty until viewDone)
---@field myPoint integer|nil
---@field reveal table|nil {option: integer|nil, cheated: boolean, pick: integer|nil}
---@field choose fun(option: integer) point at (or, while betting, choose) an option

GameOfChance = {}

--Seconds between pressing Deal and the deal starting, so everyone is looking.
local COUNTDOWN_SECONDS = 3
--A player's slowed view never holds the table up by more than this factor.
local MAX_VIEW_FACTOR = 3
--Each point of the perception characteristic adds this much viewing time.
local PERCEPTION_SLOWDOWN = 0.15
--A Director who does not answer "Cheat?" in this time gets the NPC rule.
local CHEAT_PROMPT_SECONDS = 15

local g_slowSetting = setting{
    id = "gameofchance:slow",
    storage = "account",
    default = false,
}
local g_skipSetting = setting{
    id = "gameofchance:skip",
    storage = "account",
    default = false,
}
local g_largeSetting = setting{
    id = "gameofchance:large",
    storage = "account",
    default = false,
}

---@type table<string, ChanceGameDef>
local g_games = {}

--------------------------------------------------------------------------------
-- Setup: presets and fields
--------------------------------------------------------------------------------

local PRESETS = {
    tavern = { dealer = "npc", honesty = "honest", difficulty = "easy", tests = true, stake = "none", stakeGold = 1, wins = 1, losses = 1, onLoss = "again" },
    rigged = { dealer = "npc", honesty = "shady", difficulty = "medium", tests = true, stake = "gold", stakeGold = 10, wins = 1, losses = 1, onLoss = "again" },
    carnival = { dealer = "npc", honesty = "crooked", difficulty = "hard", tests = true, stake = "recovery", stakeGold = 0, wins = 2, losses = 1, onLoss = "fail" },
}

---@param config table
---@return boolean
local function IsCustom(config)
    return config.preset == "custom"
end

local CHARACTERISTIC_OPTIONS = {
    { id = "mgt", text = "Might" },
    { id = "agl", text = "Agility" },
    { id = "rea", text = "Reason" },
    { id = "inu", text = "Intuition" },
    { id = "prs", text = "Presence" },
}

---@param game ChanceGameDef
---@return PuzzleField[]
local function LayerFields(game)
    local fields = {
        { id = "preset", type = "choice", label = "Game", default = "tavern", options = {
            { id = "tavern", text = "Friendly tavern" },
            { id = "rigged", text = "Rigged house" },
            { id = "carnival", text = "Devil's Carnival" },
            { id = "custom", text = "Customize" },
        } },
        { id = "dealerName", type = "text", label = "Dealer's name", default = "" },
        { id = "lineGreeting", type = "text", label = "Dealer's greeting", default = "" },
        { id = "lineWin", type = "text", label = "Dealer when the party wins", default = "" },
        { id = "lineLose", type = "text", label = "Dealer when the party loses", default = "" },
        { id = "lineCaught", type = "text", label = "Dealer when caught cheating", default = "" },
        { id = "lineLeave", type = "text", label = "Dealer when the stake is pulled", default = "" },
        { id = "dealer", type = "choice", label = "Dealer", default = "npc", visible = IsCustom, options = {
            { id = "npc", text = "An NPC deals" },
            { id = "director", text = "I deal" },
        } },
        { id = "honesty", type = "choice", label = "The dealer is", default = "honest", visible = IsCustom, options = {
            { id = "honest", text = "Honest (never cheats)" },
            { id = "shady", text = "Shady (cheats half the time)" },
            { id = "crooked", text = "Crooked (always cheats)" },
        } },
        { id = "difficulty", type = "choice", label = "Difficulty", default = "medium", visible = IsCustom, options = {
            { id = "easy", text = "Easy" },
            { id = "medium", text = "Medium" },
            { id = "hard", text = "Hard" },
        } },
        { id = "tests", type = "toggle", label = "Offer tests (Watch closely, Watch the dealer)", default = true, visible = IsCustom },
        { id = "testAttr", type = "choice", label = "Tests use", default = "inu", visible = IsCustom, options = CHARACTERISTIC_OPTIONS },
        { id = "stake", type = "choice", label = "Stake", default = "none", visible = IsCustom, options = {
            { id = "none", text = "Nothing" },
            { id = "gold", text = "Gold" },
            { id = "wealth", text = "1 Wealth" },
            { id = "recovery", text = "A Recovery (can only be lost)" },
        } },
        { id = "stakeGold", type = "number", label = "Gold staked", default = 5, min = 1, max = 500,
            visible = function(config) return IsCustom(config) and config.stake == "gold" end },
        { id = "wins", type = "number", label = "Rounds to win", default = 1, min = 1, max = 5, visible = IsCustom },
        { id = "losses", type = "number", label = "Rounds the party can lose", default = 1, min = 1, max = 5, visible = IsCustom },
        { id = "onLoss", type = "choice", label = "When the party loses", default = "again", visible = IsCustom, options = {
            { id = "again", text = "The dealer offers another game" },
            { id = "fail", text = "The puzzle fails" },
        } },
        { id = "slowTable", type = "toggle", label = "Show the deal slowly to everyone", default = false, visible = IsCustom },
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

--The setup in force: a preset's values, or the Director's own under Customize.
--Crooked with no tests is refused (nothing could ever win), so it reads as shady.
---@param config table
---@return table
local function Effective(config)
    local result = {}
    for k, v in pairs(config) do
        result[k] = v
    end
    local preset = PRESETS[config.preset or "tavern"]
    if preset ~= nil then
        for k, v in pairs(preset) do
            result[k] = v
        end
    end
    if result.honesty == "crooked" and result.tests ~= true then
        result.honesty = "shady"
    end
    if result.dealer == "director" and dmhub.directorlessPlay then
        result.dealer = "npc"
    end
    result.wins = math.max(1, math.tointeger(tonumber(result.wins)) or 1)
    result.losses = math.max(1, math.tointeger(tonumber(result.losses)) or 1)
    result.stakeGold = math.max(0, math.tointeger(tonumber(result.stakeGold)) or 0)
    result.testAttr = result.testAttr or "inu"
    return result
end
GameOfChance.Effective = Effective

---@param config table
---@return string
local function DealerName(config)
    local name = tostring(config.dealerName or "")
    if name == "" then
        return "The dealer"
    end
    return name
end

local DEFAULT_LINES = {
    lineGreeting = "Step right up! Keep your eye on the prize.",
    lineWin = "Well played. You've a sharp eye.",
    lineLose = "Better luck next time, friend.",
    lineCaught = "Ah... you saw that, did you?",
    lineLeave = "Suit yourself. The table's closed.",
}

---@param config table
---@param key string
---@return string
local function DealerLine(config, key)
    local line = tostring(config[key] or "")
    if line == "" then
        line = DEFAULT_LINES[key] or ""
    end
    return string.format("%s: \"%s\"", DealerName(config), line)
end

--------------------------------------------------------------------------------
-- Heroes, stakes
--------------------------------------------------------------------------------

--The hero a player acts as: their selected token, else their primary character.
---@return CharacterToken|nil
local function MyHero()
    local tokens = dmhub.selectedOrPrimaryTokens or {}
    local tok = tokens[1]
    if tok ~= nil and tok.valid and tok.properties ~= nil then
        return tok
    end
    return nil
end

---@param tokenid string|nil
---@return CharacterToken|nil
local function HeroById(tokenid)
    if tokenid == nil then
        return nil
    end
    local tok = dmhub.GetCharacterById(tokenid)
    if tok ~= nil and tok.valid then
        return tok
    end
    return nil
end

--A token's name, or fallback (the player's name in log lines) when it has none.
---@param tok CharacterToken
---@param fallback string|nil
---@return string
local function HeroName(tok, fallback)
    local name = nil
    pcall(function() name = tok.name end)
    if type(name) ~= "string" or name == "" then
        name = fallback or "A hero"
    end
    return name
end

---@return string|nil
local function GoldCurrencyId()
    local fallback = nil
    for k, c in pairs(dmhub.GetTable(Currency.tableName) or {}) do
        if not c.hidden then
            if c.money then
                return k
            end
            if c.name == "Gold" then
                fallback = k
            end
        end
    end
    return fallback
end

---@param tok CharacterToken
---@return integer
local function Wealth(tok)
    local market = rawget(_G, "EotwMarket")
    if market ~= nil and market.Wealth ~= nil then
        return market.Wealth(tok)
    end
    local wealth = 0
    pcall(function() wealth = tok.properties:CalculateNamedCustomAttribute("Wealth") or 0 end)
    return math.max(0, math.floor(tonumber(wealth) or 0))
end

---@param tok CharacterToken
---@return integer
local function Recoveries(tok)
    local n = 0
    pcall(function() n = tok.properties:RecoveriesAvailableToSpend() or 0 end)
    return n
end

---@param tok CharacterToken
---@return number
local function Gold(tok)
    local id = GoldCurrencyId()
    if id == nil then
        return 0
    end
    return tok.properties:GetCurrency(id)
end

--What the stake is, in words ("5 gold"), or nil when nothing is staked.
---@param eff table
---@return string|nil
local function StakeText(eff)
    if eff.stake == "gold" then
        return string.format("%d gold", eff.stakeGold)
    elseif eff.stake == "wealth" then
        return "1 Wealth"
    elseif eff.stake == "recovery" then
        return "a Recovery"
    end
    return nil
end

--Whether a hero can cover the stake if they lose.
---@param tok CharacterToken
---@param eff table
---@return boolean
local function CanCover(tok, eff)
    if eff.stake == "gold" then
        return Gold(tok) >= eff.stakeGold
    elseif eff.stake == "wealth" then
        return Wealth(tok) >= 1
    elseif eff.stake == "recovery" then
        return Recoveries(tok) >= 1
    end
    return true
end

--Wealth moves by a "Wealth Modification" feature, as the /awardwealth macro
--does; its guid is kept so a Reset can remove it.
---@param tok CharacterToken
---@param amount integer
---@return string|nil guid
local function AddWealthFeature(tok, amount)
    local importer = rawget(_G, "MCDMImporter")
    if importer == nil or importer.GetStandardFeature == nil then
        return nil
    end
    local template = importer.GetStandardFeature("Wealth Modification")
    if template == nil then
        return nil
    end
    local guid = dmhub.GenerateGuid()
    tok:ModifyProperties{
        description = "Game of chance: Wealth",
        undoable = false,
        execute = function()
            local feature = DeepCopy(template)
            feature.guid = guid
            feature.name = "Game of chance"
            feature.source = "Custom"
            local m = feature.modifiers[1]
            m.sourceguid = guid
            m.name = "Game of chance"
            m.source = "Custom"
            if m.behavior == "resource" then
                m.num = amount
            else
                m.value = amount
            end
            local features = tok.properties:get_or_add("characterFeatures", {})
            features[#features + 1] = feature
        end,
    }
    return guid
end

--Move the stake on a hero's sheet. sign: 1 the hero won, -1 they lost.
--Returns what was done, for a Reset to undo, or nil when nothing moved.
---@param tok CharacterToken
---@param eff table
---@param sign integer
---@return table|nil
local function PayStake(tok, eff, sign)
    if eff.stake == "gold" then
        local id = GoldCurrencyId()
        if id == nil then
            return nil
        end
        local before = tok.properties:GetCurrency(id)
        local after = math.max(0, before + sign * eff.stakeGold)
        if after == before then
            return nil
        end
        tok:ModifyProperties{
            description = "Game of chance: gold",
            undoable = false,
            execute = function()
                tok.properties:SetCurrency(id, after, "Game of chance")
            end,
        }
        return { kind = "gold", delta = after - before }
    elseif eff.stake == "wealth" then
        if sign < 0 and Wealth(tok) < 1 then
            return nil
        end
        local guid = AddWealthFeature(tok, sign)
        if guid == nil then
            return nil
        end
        return { kind = "wealth", guid = guid }
    elseif eff.stake == "recovery" and sign < 0 then
        if Recoveries(tok) < 1 then
            return nil
        end
        tok:ModifyProperties{
            description = "Game of chance: lose a Recovery",
            undoable = false,
            execute = function()
                tok.properties:ConsumeResource(CharacterResource.recoveryResourceId, "long", 1, "Game of chance")
            end,
        }
        return { kind = "recovery" }
    end
    return nil
end

---@param tok CharacterToken
---@param paid table
local function UndoStake(tok, paid)
    if paid.kind == "gold" then
        local id = GoldCurrencyId()
        if id == nil then
            return
        end
        local value = math.max(0, tok.properties:GetCurrency(id) - (tonumber(paid.delta) or 0))
        tok:ModifyProperties{
            description = "Game of chance: undo gold",
            undoable = false,
            execute = function()
                tok.properties:SetCurrency(id, value, "Game of chance reset")
            end,
        }
    elseif paid.kind == "wealth" then
        tok:ModifyProperties{
            description = "Game of chance: undo Wealth",
            undoable = false,
            execute = function()
                local features = tok.properties:try_get("characterFeatures") or {}
                for i = #features, 1, -1 do
                    if features[i].guid == paid.guid then
                        table.remove(features, i)
                    end
                end
            end,
        }
    elseif paid.kind == "recovery" then
        tok:ModifyProperties{
            description = "Game of chance: undo Recovery",
            undoable = false,
            execute = function()
                tok.properties:RefreshResource(CharacterResource.recoveryResourceId, "long", 1, "Game of chance reset")
            end,
        }
    end
end

--------------------------------------------------------------------------------
-- Test outcomes: Draw Steel's test difficulty rows
--------------------------------------------------------------------------------

--"success", "consequence" (success with a consequence), "failure" or
--"failconsequence"; reward is true for a natural 19-20 or an easy tier 3.
---@param tier integer
---@param natural number|nil
---@param difficulty string
---@return string outcome, boolean reward
local function Outcome(tier, natural, difficulty)
    local reward = natural ~= nil and natural >= 19
    if difficulty == "easy" then
        if tier >= 3 then
            return "success", true
        elseif tier == 2 then
            return "success", reward
        end
        return "consequence", reward
    elseif difficulty == "hard" then
        if tier >= 3 then
            return "success", reward
        elseif tier == 2 then
            return "failure", reward
        end
        return "failconsequence", reward
    end
    if tier >= 3 then
        return "success", reward
    elseif tier == 2 then
        return "consequence", reward
    end
    return "failure", reward
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

--Everything about the current round lives under state.r, replaced whole at
--each deal; per-game things sit at the top level.
---@return table
local function NewRound()
    return { views = {}, pointers = {}, watched = {}, follow = {}, dealer = {} }
end

---@return table
local function NewGameState()
    return {
        game = 1,
        round = 0,
        phase = "ready",
        wins = 0,
        losses = 0,
        log = "",
        r = NewRound(),
        dealerWatched = {},
        req = {},
        done = {},
    }
end

---@param state table
---@return table
local function Round(state)
    if type(state.r) ~= "table" then
        state.r = NewRound()
    end
    return state.r
end

--File a request for the host: a small queue per player, numbered so the host
--applies each once and in order.
---@param id string
---@param args table
local function SendRequest(id, args)
    Puzzle.Change(id, function(state)
        state.req = state.req or {}
        local queue = state.req[dmhub.userid]
        if type(queue) ~= "table" or queue.seq ~= nil then
            queue = {}
            state.req[dmhub.userid] = queue
        end
        local seq = tonumber((state.done or {})[dmhub.userid]) or 0
        for _, queued in pairs(queue) do
            if type(queued) == "table" then
                seq = math.max(seq, tonumber(queued.seq) or 0)
            end
        end
        seq = seq + 1
        local req = { seq = seq }
        for k, v in pairs(args) do
            req[k] = v
        end
        --keyed, not a list, and one entry per request: a second request sent
        --before the host's next tick must not replace the first.
        queue["s" .. seq] = req
    end, "Game of chance request")
end

--How much slower this player sees the deal: their own "slowly" setting or the
--table's, times their hero's perception.
---@param game ChanceGameDef
---@param eff table
---@return number factor, boolean perceptionSlowed
local function MyViewFactor(game, eff)
    local factor = 1
    if g_slowSetting:Get() == true or eff.slowTable == true then
        factor = 2
    end
    local slowed = false
    if game.perception ~= nil then
        local tok = MyHero()
        if tok ~= nil then
            local value = 0
            pcall(function()
                local attr = tok.properties:GetAttribute(game.perception)
                if attr ~= nil then
                    value = attr:Modifier()
                end
            end)
            if value > 0 then
                factor = factor * (1 + PERCEPTION_SLOWDOWN * value)
                slowed = true
            end
        end
    end
    return math.min(MAX_VIEW_FACTOR, factor), slowed
end

--------------------------------------------------------------------------------
-- Host
--------------------------------------------------------------------------------

--Director "Cheat?" prompts waiting on this host: puzzle id -> {key, answer, deadline, panel}.
---@type table<string, table>
local g_cheatPrompts = {}

---@param id string
---@param key string
---@param title string
local function ShowCheatPrompt(id, key, title)
    local entry = { key = key, answer = nil, deadline = dmhub.Time() + CHEAT_PROMPT_SECONDS }
    g_cheatPrompts[id] = entry
    local panel
    local function Answer(value)
        entry.answer = value
        if panel ~= nil and panel.valid then
            panel:DestroySelf()
        end
    end
    panel = gui.Panel{
        classes = {"framedPanel"},
        styles = ThemeEngine.GetStyles(),
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "top",
        vmargin = 120,
        flow = "vertical",
        pad = 12,
        borderBox = true,
        thinkTime = 0.5,
        think = function(element)
            if entry.answer ~= nil or g_cheatPrompts[id] ~= entry or dmhub.Time() > entry.deadline then
                element:DestroySelf()
            end
        end,
        gui.Label{
            classes = {"sizeM", "bold"},
            width = "auto",
            height = "auto",
            text = string.format("%s: cheat this round?", title),
        },
        gui.Label{
            classes = {"sizeS"},
            width = 360,
            height = "auto",
            text = "Only you see this. No answer in a few seconds plays the dealer's honesty setting.",
        },
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "center",
            tmargin = 6,
            gui.Button{ classes = {"sizeS"}, text = "Cheat", width = 120, height = 28, hmargin = 4, click = function() Answer(true) end },
            gui.Button{ classes = {"sizeS"}, text = "Play it straight", width = 160, height = 28, hmargin = 4, click = function() Answer(false) end },
        },
    }
    gui.ShowDialog(mod, panel)
end

--Decide (once per round) whether the dealer cheats. Returns nil while a
--Director's answer is still awaited.
---@param id string
---@param state table
---@param eff table
---@return boolean|nil
local function DecideCheat(id, state, eff)
    local r = Round(state)
    if r.cheat ~= nil then
        return r.cheat
    end
    local function NpcRule()
        if eff.honesty == "crooked" then
            return true
        elseif eff.honesty == "shady" then
            --a hero the dealer noticed in an earlier round gets cheated now.
            if state.noticedRound ~= nil and state.noticedRound < state.round then
                state.noticedRound = nil
                return true
            end
            return math.random(2) == 1
        end
        return false
    end
    local decided = nil
    if eff.dealer == "director" and dmhub.isDM then
        local key = string.format("%s:%s", tostring(state.game), tostring(state.round))
        local prompt = g_cheatPrompts[id]
        if prompt == nil or prompt.key ~= key then
            ShowCheatPrompt(id, key, Puzzle.Title(id))
            return nil
        end
        if prompt.answer ~= nil then
            decided = prompt.answer
        elseif dmhub.Time() > prompt.deadline then
            decided = NpcRule()
        else
            return nil
        end
        g_cheatPrompts[id] = nil
    else
        decided = NpcRule()
    end
    r.cheat = decided
    return decided
end

---@param state table
---@param line string
local function AppendLog(state, line)
    state.log = (state.log or "") .. line .. "\n"
end

--A round is over: count it and see whether the game is.
---@param state table
---@param eff table
---@param result "win"|"lose"|"push"
---@param bettor table|nil {user, tokenid}
---@param effects table side effects to run once the write is saved
local function FinishRound(state, eff, result, bettor, effects)
    if result == "win" then
        state.wins = (state.wins or 0) + 1
    elseif result == "lose" then
        state.losses = (state.losses or 0) + 1
    end
    state.phase = "revealed"
    local final = nil
    if state.wins >= eff.wins then
        final = "won"
    elseif state.losses >= eff.losses then
        final = "lost"
    end
    if final == nil then
        return
    end
    state.phase = "over"
    state.result = final
    effects[#effects + 1] = { chat = DealerLine(eff, cond(final == "won", "lineWin", "lineLose")) }
    --stakes pay once, on the game's last round, to that round's bettor.
    if bettor ~= nil and bettor.tokenid ~= nil and eff.stake ~= "none" and not state.settled then
        state.settled = true
        effects[#effects + 1] = { pay = bettor.tokenid, sign = cond(final == "won", 1, -1) }
    end
end

---@param game ChanceGameDef
---@param id string
local function HostTick(game, id)
    local status = Puzzle.Status(id)
    if status.solved or status.failed then
        return
    end
    local effects = {}
    Puzzle.Change(id, function(state, config)
        local eff = Effective(config)
        local now = dmhub.serverTime
        local changed = false
        local r = Round(state)

        --everyone at the table has said how slowly they watch: fix the time
        --the bet opens once the deal has started.
        if state.phase == "dealing" and r.openAt == nil and r.start ~= nil and now >= r.start then
            local slowest = 1
            local present = {}
            for _, userid in ipairs(Puzzle.PresentUsers(id)) do
                present[userid] = true
            end
            for userid, factor in pairs(r.views or {}) do
                if present[userid] and type(factor) == "number" then
                    slowest = math.max(slowest, math.min(MAX_VIEW_FACTOR, factor))
                end
            end
            r.openAt = r.start + game.Duration(r.data or {}) * slowest
            changed = true
        end

        state.req = state.req or {}
        state.done = state.done or {}
        for userid, queue in pairs(state.req) do
            if type(queue) == "table" and queue.seq ~= nil then
                --a request in the old one-slot form: drop it.
                state.req[userid] = {}
                changed = true
            elseif type(queue) == "table" then
                local pending = {}
                for key, queued in pairs(queue) do
                    if type(queued) == "table" then
                        pending[#pending + 1] = { key = key, req = queued }
                    end
                end
                table.sort(pending, function(a, b) return (tonumber(a.req.seq) or 0) < (tonumber(b.req.seq) or 0) end)
                for _, item in ipairs(pending) do
                    local req = item.req
                    local doneSeq = tonumber(state.done[userid]) or 0
                    if (tonumber(req.seq) or 0) <= doneSeq then
                        queue[item.key] = nil
                        changed = true
                    else
                        local finished = true
                        local kind = req.kind
                        local inRound = req.round == state.round and req.game == state.game
                        local name = Puzzle.UserName(userid)

                        if kind == "deal" then
                            if req.game == state.game and (state.phase == "ready" or state.phase == "revealed")
                                and (eff.dealer ~= "director" or req.director == true) then
                                state.round = (state.round or 0) + 1
                                local seed = dmhub.GenerateGuid()
                                local nr = NewRound()
                                nr.seed = seed
                                nr.data = game.DealRound(eff, Puzzle.SeededRandom(seed), eff.difficulty or "medium")
                                nr.dealAt = now
                                nr.start = now + COUNTDOWN_SECONDS
                                state.r = nr
                                r = nr
                                state.phase = "dealing"
                                effects[#effects + 1] = { push = true }
                            end
                        elseif kind == "playagain" then
                            if state.phase == "over" and req.game == state.game and state.result ~= "won" and eff.onLoss == "again" then
                                local fresh = NewGameState()
                                fresh.game = (state.game or 1) + 1
                                fresh.log = state.log
                                fresh.done = state.done
                                fresh.req = state.req
                                for k in pairs(state) do
                                    state[k] = nil
                                end
                                for k, v in pairs(fresh) do
                                    state[k] = v
                                end
                                r = Round(state)
                                AppendLog(state, string.format("%s plays again.", name))
                            end
                        elseif kind == "test" and inRound and state.phase == "dealing" and r.bet == nil then
                            local testid = req.test
                            local tier = math.tointeger(tonumber(req.tier)) or 1
                            if testid == "follow" and game.test ~= nil and r.follow[userid] == nil then
                                local outcome, reward = Outcome(tier, tonumber(req.natural), eff.difficulty or "medium")
                                r.follow[userid] = { outcome = outcome, reward = reward or nil }
                                r.watched[userid] = true
                                if outcome == "consequence" or outcome == "failconsequence" then
                                    state.noticedRound = state.noticedRound or state.round
                                end
                            elseif testid == "dealer" and state.dealerWatched[userid] == nil then
                                local cheat = DecideCheat(id, state, eff)
                                if cheat == nil then
                                    finished = false
                                else
                                    state.dealerWatched[userid] = tier
                                    r.dealer[userid] = tier
                                end
                            end
                        elseif kind == "call" and inRound and state.phase == "dealing" and r.bet == nil
                            and r.dealer[userid] == 3 and r.cheat == true then
                            r.bet = { user = userid, tokenid = req.tokenid, called = true }
                            r.reveal = { option = nil, cheated = true, pick = nil }
                            local caller = HeroById(req.tokenid)
                            AppendLog(state, string.format("Round %d: %s called out the dealer -- won.", state.round, caller ~= nil and HeroName(caller, name) or name))
                            effects[#effects + 1] = { chat = DealerLine(eff, "lineCaught") }
                            FinishRound(state, eff, "win", r.bet, effects)
                        elseif kind == "pull" and inRound and state.phase == "dealing" and r.bet == nil
                            and (r.dealer[userid] or 0) >= 2 then
                            state.phase = "over"
                            state.result = "pulled"
                            local puller = HeroById(req.tokenid)
                            local who = puller ~= nil and HeroName(puller, name) or name
                            AppendLog(state, string.format("Round %d: %s pulled the stake. The dealer packs up.", state.round, who))
                            effects[#effects + 1] = { chat = string.format("%s pulled the stake at %s. The dealer packs up.", who, Puzzle.Title(id)) }
                        elseif kind == "bet" and inRound and state.phase == "dealing" and r.bet == nil
                            and r.openAt ~= nil and now >= r.openAt - 0.5 then
                            local options = game.Options(r.data or {})
                            local option = math.tointeger(tonumber(req.option))
                            local tok = HeroById(req.tokenid)
                            if option ~= nil and option >= 1 and option <= #options and (eff.stake == "none" or (tok ~= nil and CanCover(tok, eff))) then
                                local cheat = DecideCheat(id, state, eff)
                                if cheat == nil then
                                    finished = false
                                else
                                    local result = game.Judge(r.data or {}, option, cheat)
                                    r.bet = { user = userid, tokenid = req.tokenid, option = option }
                                    r.reveal = { option = nil, cheated = cheat, pick = option }
                                    local words = { win = "won", lose = "lost", push = "a draw" }
                                    AppendLog(state, string.format("Round %d: %s bet on %s -- %s%s.", state.round,
                                        tok ~= nil and HeroName(tok, name) or name, options[option], words[result] or result,
                                        cond(cheat and result == "lose", " (" .. game.cheatText .. ")", "")))
                                    FinishRound(state, eff, result, r.bet, effects)
                                end
                            end
                        end


                        if finished then
                            state.done[userid] = req.seq
                            queue[item.key] = nil
                            changed = true
                        else
                            --waiting on something (the Director's cheat answer):
                            --later requests wait behind it.
                            break
                        end
                    end
                end
            end
        end
        if not changed then
            return false
        end
    end, "Game of chance")

    for _, effect in ipairs(effects) do
        if effect.chat ~= nil then
            chat.Send(effect.chat)
        elseif effect.push then
            Puzzle.PushToEveryone(id)
        elseif effect.pay ~= nil then
            local tok = HeroById(effect.pay)
            local config = Puzzle.ReadConfig(id)
            local eff = Effective(config)
            if tok ~= nil then
                local paid = PayStake(tok, eff, effect.sign)
                if paid ~= nil then
                    paid.tokenid = effect.pay
                    Puzzle.Change(id, function(state) state.paid = paid end, "Game of chance stake")
                    local stake = StakeText(eff) or ""
                    chat.Send(string.format("%s %s %s.", HeroName(tok), cond(effect.sign > 0, "wins", "loses"), stake))
                end
            end
        end
    end
end

--A Reset gives back what the game took or paid.
Puzzle.RegisterOutcomeHandler("gameofchance", {
    apply = function(id, outcome, status) end,
    undo = function(id, status)
        local def = Puzzle.GetType(id)
        if def == nil or g_games[def.id] == nil then
            return
        end
        local state = Puzzle.ReadState(id)
        local paid = state ~= nil and state.paid or nil
        if type(paid) ~= "table" then
            return
        end
        local tok = HeroById(paid.tokenid)
        if tok ~= nil then
            UndoStake(tok, paid)
        end
    end,
})

--------------------------------------------------------------------------------
-- Rolls
--------------------------------------------------------------------------------

--A player's test: the montage's skill-aware roll (characteristic, the Skilled
--chip, the hero's features), private to the roller. onDone(tier, natural).
---@param tok CharacterToken
---@param attrid string
---@param skill string
---@param name string
---@param stillWanted fun(): boolean
---@param onDone fun(tier: integer, natural: number|nil)
local function RollTest(tok, attrid, skill, name, stillWanted, onDone)
    local info = (creature.attributesInfo or {})[attrid]
    local attrName = info ~= nil and info.description or "Intuition"
    local attr = string.format("%s, %s", attrName, skill)
    local montage = rawget(_G, "EncounterMontage")
    if montage ~= nil and montage.BuildTestRoll ~= nil and montage.ShowTestRoll ~= nil then
        local parts = montage.BuildTestRoll(tok, attr, name, nil)
        montage.ShowTestRoll{
            creature = tok.properties,
            heroToken = tok,
            title = parts.title,
            rollType = parts.rollType,
            roll = parts.roll,
            modifiers = parts.modifiers,
            tiers = { "You see nothing useful.", "You see something.", "You see it clearly." },
            rollSeq = 1,
            share = false,
            completeKind = "rolled",
            cancelKind = "cancel",
            stillWanted = stillWanted,
            send = function(kind, req)
                if kind == "rolled" and stillWanted() then
                    onDone(math.tointeger(tonumber(req.tier)) or 1, tonumber(req.natural))
                end
                return true
            end,
        }
        return
    end
    --without Encounter of the Week: the characteristic alone.
    local bonus = 0
    pcall(function() bonus = tok.properties:GetAttribute(attrid):Modifier() end)
    dmhub.Roll{
        roll = string.format("2d10 + %d", bonus),
        description = string.format("%s: %s", name, attr),
        complete = function(rollInfo)
            local tier = 1
            pcall(function() tier = RollUtils.DiceResultToTier(rollInfo) end)
            if stillWanted() then
                onDone(tier, rollInfo.naturalRoll)
            end
        end,
    }
end

--------------------------------------------------------------------------------
-- The game panel
--------------------------------------------------------------------------------

---@param n integer
---@return string
local function Plural(n)
    return cond(n == 1, "", "s")
end

--What a "Watch closely" result says to the player who rolled it.
---@param game ChanceGameDef
---@param data table
---@param rec table {outcome, reward}
---@param eff table
---@return string
local function FollowText(game, data, rec, eff)
    local text
    if rec.outcome == "success" or rec.outcome == "consequence" then
        text = string.format("%s -- if the dealer played it straight.", game.test.Success(data))
    else
        text = "You lost track of it."
    end
    if rec.outcome == "consequence" or rec.outcome == "failconsequence" then
        text = text .. " The dealer noticed you watching."
    end
    if rec.reward then
        text = text .. cond(eff.honesty == "honest", " You can tell this dealer plays fair.", " You can tell this dealer cheats.")
    end
    return text
end

---@param tier integer
---@param cheat boolean|nil
---@param game ChanceGameDef
---@return string
local function DealerText(tier, cheat, game)
    if tier >= 3 then
        if cheat then
            return string.format("You caught it: %s! Call it out to win the round.", game.cheatText)
        end
        return "Clean deal."
    elseif tier == 2 then
        return "Something's off. You could pull the stake (the game ends)."
    end
    return "You didn't see anything odd."
end

---@param game ChanceGameDef
---@param ctx PuzzleContext
---@return Panel
local function Render(game, ctx)
    local m_ctx = ctx
    local m_betting = false
    local m_betOption = nil ---@type integer|nil
    local m_rolling = {} ---@type table<string, boolean>
    local m_viewKey = nil ---@type string|nil
    local m_lastKey = nil ---@type string|nil

    local resultPanel
    local board
    local dealerLabel
    local stepLabel
    local scoreLabel
    local mineLabel
    local heroLabel
    local watchersLabel
    local logLabel
    local betRow
    local betPrompt
    local betConfirm
    local buttons = {}

    local function State()
        return m_ctx.state or {}
    end

    local function Eff()
        return Effective(m_ctx.config)
    end

    --This viewer's replay of the deal: seconds in (at normal speed), and done?
    local function ViewTimes()
        local state = State()
        local r = state.r or {}
        local eff = Eff()
        local now = dmhub.serverTime
        if state.phase ~= "dealing" and state.phase ~= "revealed" and state.phase ~= "over" then
            return nil, true, nil
        end
        if r.start == nil then
            return nil, true, nil
        end
        if now < r.start then
            return nil, false, r.start - now
        end
        local duration = game.Duration(r.data or {})
        if g_skipSetting:Get() == true or state.phase ~= "dealing" then
            return duration, true, nil
        end
        local factor = (r.views or {})[dmhub.userid]
        if type(factor) ~= "number" then
            factor = MyViewFactor(game, eff)
        end
        local t = (now - r.start) / factor
        return math.min(t, duration), t >= duration, nil
    end

    local function Choose(option)
        if m_ctx.readonly then
            return
        end
        if m_betting then
            m_betOption = option
            resultPanel:FireEvent("chanceRefresh")
            return
        end
        local state = State()
        local r = state.r or {}
        local _, done = ViewTimes()
        if state.phase ~= "dealing" or not done or r.bet ~= nil then
            return
        end
        Puzzle.Change(m_ctx.id, function(s)
            local rr = Round(s)
            rr.pointers[dmhub.userid] = cond(rr.pointers[dmhub.userid] == option, nil, option)
        end, "Point")
    end

    local function View()
        local state = State()
        local r = state.r or {}
        local t, done, countdown = ViewTimes()
        local pointers = {}
        if done then
            for userid, option in pairs(r.pointers or {}) do
                local list = pointers[option] or {}
                list[#list + 1] = Puzzle.UserName(userid)
                pointers[option] = list
            end
            for _, list in pairs(pointers) do
                table.sort(list)
            end
        end
        return {
            data = r.data,
            phase = state.phase or "ready",
            countdown = countdown,
            t = t,
            viewDone = done,
            skipped = g_skipSetting:Get() == true,
            reduceMotion = ThemeEngine.GetAccessibility().reduceMotion == true,
            large = g_largeSetting:Get() == true,
            pointers = pointers,
            myPoint = cond(m_betting, m_betOption, (r.pointers or {})[dmhub.userid]),
            reveal = r.reveal,
            choose = Choose,
        }
    end

    --Tell the host how slowly this player watches, once per round.
    local function ReportView()
        local state = State()
        local r = state.r or {}
        local key = string.format("%s:%s", tostring(state.game), tostring(state.round))
        if state.phase ~= "dealing" or r.start == nil or dmhub.serverTime >= r.start or m_viewKey == key then
            return
        end
        m_viewKey = key
        local factor = 1
        if g_skipSetting:Get() ~= true then
            factor = MyViewFactor(game, Eff())
        end
        if (r.views or {})[dmhub.userid] == factor then
            return
        end
        Puzzle.Change(m_ctx.id, function(s)
            Round(s).views[dmhub.userid] = factor
        end, "Game of chance view")
    end

    local function Request(args)
        local state = State()
        args.game = state.game
        args.round = state.round
        SendRequest(m_ctx.id, args)
    end

    local function StartTest(testid)
        local tok = MyHero()
        if tok == nil then
            return
        end
        local state = State()
        local eff = Eff()
        local key = string.format("%s:%s:%s:%s", testid, tostring(state.game), tostring(state.round), tostring(m_ctx.id))
        if m_rolling[key] then
            return
        end
        m_rolling[key] = true
        local game0, round0 = state.game, state.round
        local id = m_ctx.id
        local skill, name
        if testid == "follow" then
            skill = game.test.skill
            name = game.test.label
        else
            skill = "Read Person, Gamble"
            name = "Watch the dealer"
        end
        RollTest(tok, eff.testAttr, skill, name, function()
            local s = Puzzle.ReadState(id) or {}
            local r = s.r or {}
            return s.game == game0 and s.round == round0 and s.phase == "dealing" and r.bet == nil
        end, function(tier, natural)
            SendRequest(id, { kind = "test", test = testid, tier = tier, natural = natural, game = game0, round = round0 })
        end)
    end

    local function OpenBet()
        m_betting = true
        m_betOption = (State().r or {}).pointers and State().r.pointers[dmhub.userid] or nil
        resultPanel:FireEvent("chanceRefresh")
    end

    local function CancelBet()
        m_betting = false
        m_betOption = nil
        resultPanel:FireEvent("chanceRefresh")
    end

    local function ConfirmBet()
        local tok = MyHero()
        if not m_betting or m_betOption == nil or tok == nil then
            return
        end
        local eff = Eff()
        if eff.stake ~= "none" and not CanCover(tok, eff) then
            return
        end
        Request({ kind = "bet", option = m_betOption, tokenid = tok.charid })
        CancelBet()
    end

    local function Refresh()
        if not resultPanel.valid then
            return
        end
        ReportView()
        local ctx = m_ctx
        local state = State()
        local r = state.r or {}
        local eff = Eff()
        local view = View()
        local data = r.data or {}
        local options = r.data ~= nil and game.Options(data) or {}
        local me = dmhub.userid
        local tok = MyHero()
        local readonly = ctx.readonly
        local open = state.phase == "dealing" and view.viewDone and view.countdown == nil and r.bet == nil and not readonly
        local betOpen = open and r.openAt ~= nil and dmhub.serverTime >= r.openAt

        board:FireEventTree("chanceView", view)

        --the dealer's line for where the game is.
        if state.phase == "over" and state.result == "pulled" then
            dealerLabel.text = DealerLine(eff, "lineLeave")
        elseif state.phase == "over" then
            dealerLabel.text = DealerLine(eff, cond(state.result == "won", "lineWin", "lineLose"))
        elseif r.bet ~= nil and r.bet.called then
            dealerLabel.text = DealerLine(eff, "lineCaught")
        else
            dealerLabel.text = DealerLine(eff, "lineGreeting")
        end

        --one line naming the step.
        local step
        if readonly and ctx.editing then
            step = "The game is paused while the page is edited."
        elseif state.phase == "over" then
            if state.result == "won" then
                step = "The party won the game."
            elseif state.result == "pulled" then
                step = "The stake was pulled. The dealer packs up."
            else
                step = cond(eff.onLoss == "again", "The party lost. The dealer offers another game.", "The party lost the game.")
            end
        elseif state.phase == "ready" or state.phase == "revealed" then
            if eff.dealer == "director" and not dmhub.isDM then
                step = "Waiting for the Director to deal."
            else
                step = cond(state.phase == "ready", "Press Deal to start.", "Press Deal for the next round.")
            end
        elseif view.countdown ~= nil then
            step = string.format("Dealing in %d...", math.ceil(view.countdown))
        elseif not view.viewDone then
            local _, slowed = MyViewFactor(game, eff)
            step = cond(slowed, "Shuffling... (your Intuition slows the shuffle)", "Shuffling...")
        elseif r.bet == nil and not betOpen then
            step = "Waiting for everyone to finish watching."
        elseif m_betting then
            step = "Choose where to bet, then confirm."
        else
            step = "Point, watch, talk it over, then place the bet."
        end
        stepLabel.text = step

        local stake = StakeText(eff)
        scoreLabel.text = string.format("Round %d. Won %d of %d, lost %d of %d.%s", math.max(1, state.round or 0),
            state.wins or 0, eff.wins, state.losses or 0, eff.losses,
            stake ~= nil and string.format(" Stake: %s.", stake) or "")

        --this player's own test results.
        local mine = {}
        local follow = (r.follow or {})[me]
        if follow ~= nil and game.test ~= nil and r.data ~= nil then
            mine[#mine + 1] = string.format("%s: %s", game.test.label, FollowText(game, data, follow, eff))
        end
        local dealerTier = (r.dealer or {})[me]
        if dealerTier ~= nil then
            mine[#mine + 1] = string.format("Watch the dealer: %s", DealerText(dealerTier, r.cheat, game))
        end
        heroLabel:SetClass("collapsed", tok ~= nil or not open)
        mineLabel.text = cond(#mine > 0, "Only you see this:\n" .. table.concat(mine, "\n"), "")
        --test results guide this round's choices; once the game is over they only mislead.
        mineLabel:SetClass("collapsed", #mine == 0 or state.phase == "over")

        local watchers = {}
        for userid in pairs(r.watched or {}) do
            watchers[#watchers + 1] = Puzzle.UserName(userid)
        end
        table.sort(watchers)
        watchersLabel.text = cond(#watchers > 0, "Watched closely: " .. table.concat(watchers, ", "), "")
        watchersLabel:SetClass("collapsed", #watchers == 0)

        logLabel.text = tostring(state.log or "")
        logLabel:SetClass("collapsed", logLabel.text == "")

        --buttons.
        local canDeal = (state.phase == "ready" or state.phase == "revealed") and not readonly
            and (eff.dealer ~= "director" or dmhub.isDM)
        buttons.deal:SetClass("collapsed", not canDeal)
        local testsOn = eff.tests == true
        local followKey = string.format("follow:%s:%s:%s", tostring(state.game), tostring(state.round), tostring(ctx.id))
        buttons.follow:SetClass("collapsed", not (open and testsOn and game.test ~= nil and follow == nil))
        buttons.follow:SetClass("disabled", tok == nil or m_rolling[followKey] == true)
        buttons.dealer:SetClass("collapsed", not (open and testsOn and (state.dealerWatched or {})[me] == nil))
        buttons.dealer:SetClass("disabled", tok == nil)
        buttons.call:SetClass("collapsed", not (open and dealerTier == 3 and r.cheat == true))
        buttons.pull:SetClass("collapsed", not (open and dealerTier == 2))
        buttons.bet:SetClass("collapsed", not open or m_betting)
        buttons.bet:SetClass("disabled", not betOpen or tok == nil)
        buttons.again:SetClass("collapsed", not (state.phase == "over" and state.result ~= "won" and eff.onLoss == "again" and not readonly))

        if m_betting and not open then
            m_betting = false
            m_betOption = nil
        end
        betRow:SetClass("collapsed", not m_betting)
        betRow.captureEscape = m_betting
        if m_betting then
            local who = tok ~= nil and HeroName(tok) or "your hero"
            local choice = m_betOption ~= nil and options[m_betOption] or nil
            local covered = tok ~= nil and (eff.stake == "none" or CanCover(tok, eff))
            if not covered then
                betPrompt.text = string.format("%s can't cover the stake (%s).", who, stake or "")
            elseif choice == nil then
                betPrompt.text = string.format("Betting as %s. Choose: press 1-%d or click.", who, #options)
            elseif stake ~= nil then
                betPrompt.text = string.format("%s bets %s on %s?", who, stake, choice)
            else
                betPrompt.text = string.format("%s bets on %s?", who, choice)
            end
            betConfirm:SetClass("disabled", choice == nil or not covered)
        end

        local key = string.format("%s:%s:%s:%s", tostring(state.phase), tostring(state.round), tostring(view.viewDone), tostring(m_betting))
        m_lastKey = key
    end

    local function Button(key, text, click)
        buttons[key] = gui.Button{
            classes = {"sizeS", "collapsed"},
            text = text,
            width = 150,
            height = 28,
            --left, not the journal's centred default.
            halign = "left",
            hmargin = 3,
            vmargin = 2,
            click = function(element)
                if element:HasClass("disabled") then
                    return
                end
                click()
            end,
        }
        return buttons[key]
    end

    board = game.Board()
    dealerLabel = gui.Label{ classes = {"sizeM"}, width = 480, height = "auto", halign = "left", italics = true, text = "" }
    stepLabel = gui.Label{ classes = {"sizeM", "bold"}, width = 480, height = "auto", halign = "left", tmargin = 4, text = "" }
    scoreLabel = gui.Label{ classes = {"sizeS"}, width = 480, height = "auto", halign = "left", text = "" }
    heroLabel = gui.Label{ classes = {"sizeS", "collapsed"}, width = 480, height = "auto", halign = "left", text = "Select your hero to watch or bet." }
    mineLabel = gui.Label{ classes = {"sizeS", "info", "collapsed"}, width = 480, height = "auto", halign = "left", tmargin = 4, text = "" }
    watchersLabel = gui.Label{ classes = {"sizeS", "collapsed"}, width = 480, height = "auto", halign = "left", text = "" }
    logLabel = gui.Label{ classes = {"sizeS", "collapsed"}, width = 480, height = "auto", halign = "left", tmargin = 4, text = "" }

    betPrompt = gui.Label{ classes = {"sizeM"}, width = 300, height = "auto", valign = "center", text = "" }
    betConfirm = gui.Button{
        classes = {"sizeS"},
        text = "Confirm (Enter)",
        width = 150,
        height = 28,
        hmargin = 3,
        click = function(element)
            if not element:HasClass("disabled") then
                ConfirmBet()
            end
        end,
    }
    betRow = gui.Panel{
        classes = {"collapsed"},
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
        tmargin = 4,
        betPrompt,
        betConfirm,
        gui.Button{ classes = {"sizeS"}, text = "Cancel (Esc)", width = 130, height = 28, hmargin = 3, click = function() CancelBet() end },
        --while the bet is open, Esc cancels it rather than closing the window.
        captureEscape = false,
        escapePriority = EscapePriority.EXIT_DIALOG + 1,
        escape = function(element)
            CancelBet()
        end,
    }

    local keybinds = {
        { id = "chance_enter", defaultBind = "return" },
        { id = "chance_enter2", defaultBind = "enter" },
    }
    for i = 1, 9 do
        keybinds[#keybinds + 1] = { id = "chance_" .. i, defaultBind = tostring(i) }
    end

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        keybinds = keybinds,
        keybind = function(element, id)
            if id == "chance_enter" or id == "chance_enter2" then
                ConfirmBet()
                return
            end
            local n = tonumber(string.sub(id, 8))
            if n ~= nil then
                local state = State()
                local options = (state.r or {}).data ~= nil and game.Options(state.r.data) or {}
                if n <= #options then
                    Choose(math.tointeger(n) or 1)
                end
            end
        end,
        refreshPuzzle = function(element, newCtx)
            m_ctx = newCtx
            Refresh()
        end,
        chanceRefresh = function(element)
            Refresh()
        end,
        --the deal plays out against the shared clock: smooth while it runs,
        --a slow check otherwise (countdowns, the bet opening).
        thinkTime = 1 / 60,
        think = function(element)
            local state = State()
            if state.phase == "dealing" then
                local t, done, countdown = ViewTimes()
                if not done or countdown ~= nil then
                    board:FireEventTree("chanceView", View())
                end
                element.data.tick = (element.data.tick or 0) + 1
                if element.data.tick % 15 == 0 then
                    Refresh()
                end
            end
        end,
        data = {},

        dealerLabel,
        board,
        stepLabel,
        scoreLabel,
        mineLabel,
        heroLabel,
        betRow,
        gui.Panel{
            flow = "horizontal",
            width = 480,
            height = "auto",
            halign = "left",
            wrap = true,
            tmargin = 4,
            Button("deal", "Deal", function() Request({ kind = "deal", director = dmhub.isDM == true }) end),
            Button("follow", (game.test ~= nil and game.test.label or "Watch closely"), function() StartTest("follow") end),
            Button("dealer", "Watch the dealer", function() StartTest("dealer") end),
            Button("call", "Call it out", function()
                local tok = MyHero()
                Request({ kind = "call", tokenid = tok ~= nil and tok.charid or nil })
            end),
            Button("pull", "Pull the stake", function()
                local tok = MyHero()
                Request({ kind = "pull", tokenid = tok ~= nil and tok.charid or nil })
            end),
            Button("bet", "Place the bet", function() OpenBet() end),
            Button("again", "Play again", function() Request({ kind = "playagain" }) end),
        },
        watchersLabel,
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
                text = "Show the shuffle slowly",
                value = g_slowSetting:Get() == true,
                change = function(element) g_slowSetting:Set(element.value) Refresh() end,
            },
            gui.Check{
                classes = {"sizeS"},
                width = "auto",
                height = 22,
                hmargin = 4,
                text = "Don't watch, just roll",
                value = g_skipSetting:Get() == true,
                change = function(element) g_skipSetting:Set(element.value) Refresh() end,
            },
            gui.Check{
                classes = {"sizeS"},
                width = "auto",
                height = 22,
                hmargin = 4,
                text = "Larger view",
                value = g_largeSetting:Get() == true,
                change = function(element) g_largeSetting:Set(element.value) Refresh() end,
            },
        },
    }
    return resultPanel
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

--Register a game of chance. It becomes a puzzle type with the same id.
---@param game ChanceGameDef
function GameOfChance.Register(game)
    assert(type(game.id) == "string" and game.id ~= "", "GameOfChance.Register: id required")
    g_games[game.id] = game
    PuzzleType.Register{
        id = game.id,
        name = game.name,
        fields = LayerFields(game),
        noTimeLimit = true,
        NewState = function(config, ctx)
            return NewGameState()
        end,
        IsSolved = function(state, config)
            return state.result == "won"
        end,
        IsFailed = function(state, config, now)
            return state.result == "lost" and Effective(config).onLoss == "fail"
        end,
        Render = function(ctx)
            return Render(game, ctx)
        end,
        HostTick = function(id)
            HostTick(game, id)
        end,
    }
end
