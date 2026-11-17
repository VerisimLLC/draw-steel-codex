local mod = dmhub.GetModLoading()

-- The "Warded seal" puzzle type: split-information co-op (split-info-coop-brief.md). One
-- player, the hands, sees a generated runic ward and acts on it; the others hold its codex
-- pages and must talk them through. The ward and codex come from PuzzleWardGen; the host
-- deals the parts at Begin and decides every action.
--
-- State:
--   phase   = "gathering" | "playing"
--   ward    = the generated ward (PuzzleWardGen), written once by the host at Begin
--   parts   = { hands = userid, solo = boolean, readers = { <userid> = "m1,L2" } }
--   act     = { m1 = { cut = { t3 = true } }, m2 = { lit = "2,4" }, m3 = { pos = 5, set = 7 } }
--   strikes = number; log = { <guid> = {at, text} }
--   chat    = { c<seq> = {seq, user, style = "say"|"quote"|"ask"|"point", text} }, chatSeq

local LOG_LINES = 6
local CHAT_KEEP = 40
local CHAT_SHOW = 10

--The ward's own art, fixed whatever the app's theme; starker under a high-contrast scheme.
---@return {bg: string, border: string, lit: string, rune: string, cursor: string, thick: number}
local function WardColours()
    local high = false
    pcall(function() high = ThemeEngine.GetAccessibility().highContrast == true end)
    if high then
        return { bg = "#000000ff", border = "#ffffffff", lit = "#ffd700ff", rune = "#ffffffff", cursor = "#00e5ffff", thick = 12 }
    end
    return { bg = "#15121cff", border = "#6c5a8cff", lit = "#f2c96bff", rune = "#e9e2f5ff", cursor = "#56b4e9ff", thick = 8 }
end

--The ward's pictures are fixed pixels, so they follow the player's UI scale. With the icon
--rail on, the engine zooms the whole window instead.
---@return number
local function ArtScale()
    if dmhub.GetSettingValue("iconrail") == true then
        return 1
    end
    local scale = 1
    pcall(function() scale = ThemeEngine.GetAccessibility().scale or 1 end)
    if type(scale) ~= "number" or scale <= 0 then
        return 1
    end
    return scale
end

--Keyboard play for the hands: a command context while the seal window has the focus.
local COMMAND_CONTEXT = "wardseal"
local KEY_COMMANDS = {}
local g_bindingsReady = false

local function EnsureBindings()
    if g_bindingsReady then
        return
    end
    g_bindingsReady = true
    local function Bind(key, cmd)
        dmhub.SetCommandBinding(key, cmd, COMMAND_CONTEXT)
        KEY_COMMANDS[#KEY_COMMANDS + 1] = cmd
    end
    Bind("up", "seal_up")
    Bind("down", "seal_down")
    Bind("left", "seal_left")
    Bind("right", "seal_right")
    Bind("return", "seal_act")
    Bind("enter", "seal_act2")
    Bind("space", "seal_act3")
    Bind("q", "seal_quote")
    --Escape belongs to the window (it closes it), so No is N.
    Bind("n", "seal_cancel")
end

local PRESETS = {
    simple = { count = 0, depth = "plain", strikes = 3 }, --count 0: one or two, by the seed
    vault = { count = 3, depth = "conditional", strikes = 3 },
    archmage = { count = 4, depth = "chained", strikes = 2 },
}

local KIND_NAMES = { threads = "Threads", glyphs = "Glyphs", dial = "Sigil dial" }

--Which part a player would rather have in split puzzles; each window reports it at the
--gathering, since account settings are not visible to other players.
local g_partPreference = setting{
    id = "splitpuzzlepart",
    description = "In split puzzles I'd rather",
    storage = "account",
    default = "either",
    editor = "dropdown",
    section = "Game",
    enum = {
        { value = "either", text = "Either part" },
        { value = "hands", text = "Be the hands" },
        { value = "read", text = "Read" },
    },
}

---@param config table
---@return {count: integer, depth: string, strikes: integer, kinds: string}
local function Effective(config)
    local preset = PRESETS[config.preset or "vault"]
    if preset ~= nil then
        return { count = preset.count, depth = preset.depth, strikes = preset.strikes, kinds = "mixed" }
    end
    return {
        count = math.max(1, math.min(4, math.tointeger(tonumber(config.modules)) or 3)),
        depth = tostring(config.depth or "conditional"),
        strikes = math.max(1, math.min(5, math.tointeger(tonumber(config.strikes)) or 3)),
        kinds = tostring(config.kinds or "mixed"),
    }
end

--The module kinds for a ward, in order.
---@param eff table
---@param random fun(k: integer): integer
---@return string[]
local function ModuleKinds(eff, random)
    local count = eff.count
    if count == 0 then
        count = random(2)
    end
    if eff.kinds ~= "mixed" then
        local kinds = {}
        for i = 1, count do
            kinds[i] = eff.kinds
        end
        return kinds
    end
    local order = { "threads", "glyphs", "dial" }
    for i = #order, 2, -1 do
        local j = random(i)
        order[i], order[j] = order[j], order[i]
    end
    order[4] = "threads"
    local kinds = {}
    for i = 1, count do
        kinds[i] = order[i]
    end
    return kinds
end

--------------------------------------------------------------------------------
-- Reading the board
--------------------------------------------------------------------------------

---@param state table
---@param i integer
---@return table
local function Act(state, i)
    local act = type(state.act) == "table" and state.act["m" .. i] or nil
    if type(act) ~= "table" then
        return {}
    end
    return act
end

---@param text any
---@return integer[]
local function Numbers(text)
    local result = {}
    for part in string.gmatch(tostring(text or ""), "[^,]+") do
        result[#result + 1] = math.tointeger(tonumber(part)) or 0
    end
    return result
end

---@param state table
---@param i integer
---@return boolean
local function ModuleDone(state, i)
    local ward = state.ward
    local m = ward ~= nil and ward.modules[i] or nil
    if m == nil then
        return false
    end
    local act = Act(state, i)
    if m.kind == "threads" then
        return type(act.cut) == "table" and act.cut["t" .. m.answer] == true
    elseif m.kind == "glyphs" then
        return #Numbers(act.lit) >= 4
    end
    return act.set ~= nil and act.set == m.answer
end

--A dial that waits on the Glyphs is sealed until every Glyphs module is done.
---@param state table
---@param i integer
---@return boolean
local function ModuleSealed(state, i)
    local m = state.ward.modules[i]
    if m.kind ~= "dial" or not m.afterGlyphs then
        return false
    end
    for k, other in ipairs(state.ward.modules) do
        if other.kind == "glyphs" and not ModuleDone(state, k) then
            return true
        end
    end
    return false
end

---@param ward table
---@return string[] page keys: "m1".."mN", plus "L1".."L3" for the Lexicon pages the rules use
local function PageKeys(ward)
    local keys = {}
    for i in ipairs(ward.modules) do
        keys[#keys + 1] = "m" .. i
    end
    local refs = PuzzleWardGen.LexiconRefs(ward)
    for k = 1, 3 do
        if refs[k] then
            keys[#keys + 1] = "L" .. k
        end
    end
    return keys
end

---@param ward table
---@param key string
---@return {title: string, intro: string, lines: string[]}|nil
local function PageFor(ward, key)
    local kind, n = key:sub(1, 1), math.tointeger(tonumber(key:sub(2)))
    if n == nil then
        return nil
    end
    if kind == "m" and ward.modules[n] ~= nil then
        return PuzzleWardGen.PageText(ward, n)
    elseif kind == "L" then
        return PuzzleWardGen.LexiconText(ward)[n]
    end
    return nil
end

--What this player holds: "hands", "reader", "solo", "director" or "watching".
---@param state table
---@param userid string
---@param isDirector boolean
---@return string role, string[] pages
local function RoleOf(state, userid, isDirector)
    local parts = type(state.parts) == "table" and state.parts or {}
    if parts.hands == userid then
        return cond(parts.solo == true, "solo", "hands"), {}
    end
    local pages = type(parts.readers) == "table" and parts.readers[userid] or nil
    if type(pages) == "string" then
        local keys = {}
        for key in string.gmatch(pages, "[^,]+") do
            keys[#keys + 1] = key
        end
        return "reader", keys
    end
    if isDirector then
        return "director", {}
    end
    return "watching", {}
end

---@param userid string
---@return boolean
local function IsDirectorUser(userid)
    local dm = false
    pcall(function() dm = dmhub.GetSessionInfo(userid).dm == true end)
    return dm
end

--Players at the seal who can be dealt a part: present, not a Director.
---@param id string
---@return string[]
local function PlayersAtSeal(id)
    local result = {}
    for _, userid in ipairs(Puzzle.PresentUsers(id)) do
        if not IsDirectorUser(userid) then
            result[#result + 1] = userid
        end
    end
    return result
end

---@param ward table
---@param i integer
---@param n integer
---@return string
local function ThreadWords(ward, i, n)
    local t = ward.modules[i].threads[n]
    return string.format("Thread %d (%s, %s)", n, PuzzleRunes.threadColours[t.colour].name, PuzzleRunes.threadPatterns[t.pattern].name)
end

--------------------------------------------------------------------------------
-- The host: dealing and judging
--------------------------------------------------------------------------------

---@param state table
---@param text string
local function Log(state, text)
    state.log = state.log or {}
    --several lines can land in one host tick, so they carry their order.
    state.logSeq = (tonumber(state.logSeq) or 0) + 1
    state.log[dmhub.GenerateGuid()] = { at = dmhub.serverTime, seq = state.logSeq, text = text }
end

local CHAT_STYLES = { say = true, quote = true, ask = true, point = true }

--A party chat line: plain text (no markup), capped, the oldest trimmed.
---@param state table
---@param userid string
---@param req table
local function Say(state, userid, req)
    local text = tostring(req.text or ""):gsub("[<>]", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if text == "" then
        return
    end
    state.chat = state.chat or {}
    state.chatSeq = (tonumber(state.chatSeq) or 0) + 1
    local seq = state.chatSeq
    state.chat["c" .. seq] = { seq = seq, user = userid, style = CHAT_STYLES[req.style] and req.style or "say", text = text:sub(1, 200) }
    for key, line in pairs(state.chat) do
        if type(line) ~= "table" or (tonumber(line.seq) or 0) <= seq - CHAT_KEEP then
            state.chat[key] = nil
        end
    end
end

---@param parts table
---@param userid string
---@return string[]
local function PagesOf(parts, userid)
    local list = {}
    for key in string.gmatch(tostring((parts.readers or {})[userid] or ""), "[^,]+") do
        list[#list + 1] = key
    end
    return list
end

--The page the fewest readers hold; on a tie a Lexicon page before a module page.
---@param ward table
---@param parts table
---@return string
local function LeastCovered(ward, parts)
    local counts = {}
    local keys = PageKeys(ward)
    for _, key in ipairs(keys) do
        counts[key] = 0
    end
    for _, pages in pairs(parts.readers or {}) do
        for key in string.gmatch(tostring(pages), "[^,]+") do
            if counts[key] ~= nil then
                counts[key] = counts[key] + 1
            end
        end
    end
    local best, bestCount = keys[1], math.huge
    for _, prefix in ipairs({ "L", "m" }) do
        for _, key in ipairs(keys) do
            if key:sub(1, 1) == prefix and counts[key] < bestCount then
                best, bestCount = key, counts[key]
            end
        end
    end
    return best
end

--Pages round-robin to the readers; readers left without one get the least-covered page.
---@param ward table
---@param parts table
---@param readers string[]
local function DealPages(ward, parts, readers)
    parts.readers = {}
    if #readers == 0 then
        return
    end
    local held = {}
    for _, r in ipairs(readers) do
        held[r] = {}
    end
    for k, key in ipairs(PageKeys(ward)) do
        local r = readers[(k - 1) % #readers + 1]
        held[r][#held[r] + 1] = key
    end
    for _, r in ipairs(readers) do
        if #held[r] > 0 then
            parts.readers[r] = table.concat(held[r], ",")
        end
    end
    for _, r in ipairs(readers) do
        if #held[r] == 0 then
            parts.readers[r] = LeastCovered(ward, parts)
        end
    end
end

--The hands: a Director's pin, else someone who would rather be the hands, else "either".
---@param players string[]
---@param state table
---@param config table
---@param random fun(k: integer): integer
---@return string
local function ChooseHands(players, state, config, random)
    local pins = type(config.roles) == "table" and config.roles or {}
    for _, userid in ipairs(players) do
        if pins[userid] == "hands" then
            return userid
        end
    end
    local prefs = type(state.prefs) == "table" and state.prefs or {}
    for _, want in ipairs({ "hands", "either" }) do
        local pool = {}
        for _, userid in ipairs(players) do
            if (prefs[userid] or "either") == want then
                pool[#pool + 1] = userid
            end
        end
        if #pool > 0 then
            return pool[random(#pool)]
        end
    end
    return players[random(#players)]
end

---@param ward table
---@param key string
---@return string
local function PageTitle(ward, key)
    local page = PageFor(ward, key)
    return page ~= nil and page.title or key
end

--Deal the parts among the players at the seal. keepWard: re-deal the same ward.
---@param id string
---@param state table
---@param config table
---@param requester string
---@param keepWard boolean|nil
local function Deal(id, state, config, requester, keepWard)
    local players = PlayersAtSeal(id)
    table.sort(players)
    --nobody but the presser (a Director testing alone): they play solo.
    if #players == 0 then
        players = { requester }
    end
    local random = Puzzle.SeededRandom(dmhub.GenerateGuid())
    local ward = state.ward
    if not keepWard or ward == nil then
        local eff = Effective(config)
        local kinds = ModuleKinds(eff, random)
        local hasThreads = false
        for _, kind in ipairs(kinds) do
            hasThreads = hasThreads or kind == "threads"
        end
        --more readers than modules: rules that need the Lexicon give the spare readers a page.
        local lexicon = hasThreads and eff.depth ~= "chained" and #players - 1 > #kinds
        ward = PuzzleWardGen.Generate(random, { modules = kinds, depth = eff.depth, lexicon = lexicon })
    end
    local hands = ChooseHands(players, state, config, random)
    local readers = {}
    for _, userid in ipairs(players) do
        if userid ~= hands then
            readers[#readers + 1] = userid
        end
    end
    for i = #readers, 2, -1 do
        local j = random(i)
        readers[i], readers[j] = readers[j], readers[i]
    end
    local parts = { hands = hands, solo = #players == 1, readers = {} }
    DealPages(ward, parts, readers)
    state.parts = parts
    state.former = {}
    state.offers = {}
    state.away = nil
    if not keepWard then
        state.phase = "playing"
        state.ward = ward
        state.act = {}
        state.strikes = 0
    end
    if parts.solo then
        Log(state, string.format("%s faces the ward alone.", Puzzle.UserName(parts.hands)))
    else
        Log(state, string.format("%s has the ward in hand; the others hold the codex.", Puzzle.UserName(parts.hands)))
    end
end

---@param parts table
---@param userid string
---@return boolean
local function Dealt(parts, userid)
    return parts.hands == userid or (parts.readers or {})[userid] ~= nil
end

---@param parts table
---@param a string
---@param b string
local function SwapParts(parts, a, b)
    local pa = parts.hands == a and "H" or parts.readers[a]
    local pb = parts.hands == b and "H" or parts.readers[b]
    parts.readers[a] = nil
    parts.readers[b] = nil
    for _, pair in ipairs({ { a, pb }, { b, pa } }) do
        if pair[2] == "H" then
            parts.hands = pair[1]
        elseif pair[2] ~= nil then
            parts.readers[pair[1]] = pair[2]
        end
    end
end

---@param state table
---@return boolean
local function Started(state)
    return (state.strikes or 0) > 0 or next(state.act or {}) ~= nil
end

--The Director, or the host of a game with no Director (the host runs this code).
---@param userid string
---@return boolean
local function CanReferee(userid)
    return IsDirectorUser(userid) or userid == dmhub.userid
end

--Heroes who have braced at this seal (tokenid -> record); kept through a Reset.
---@param id string
---@return table<string, table>
local function BraceTries(id)
    local tries = Puzzle.ReadKept(id).brace
    if type(tries) ~= "table" then
        return {}
    end
    return tries
end

--A Director is in the game, so they decide on more time.
---@return boolean
local function DirectorOnline()
    for _, userid in ipairs(dmhub.users or {}) do
        local online = false
        pcall(function()
            local info = dmhub.GetSessionInfo(userid)
            online = info.dm == true and not info.loggedOut
        end)
        if online then
            return true
        end
    end
    return false
end

local ROLL_SECONDS = 60

--Host: hold the timer while anyone is rolling a test, and let it go when they are done.
--Only a pause this made is resumed, never the Director's own.
---@param id string
---@param state table
---@param after fun()[]
---@return boolean changed
local function RollPause(id, state, after)
    if state.phase ~= "playing" then
        return false
    end
    local now = dmhub.serverTime
    local changed = false
    local rolling = false
    for userid, at in pairs(state.rolling or {}) do
        if type(at) ~= "number" or now - at > ROLL_SECONDS then
            state.rolling[userid] = nil
            changed = true
        else
            rolling = true
        end
    end
    if rolling and not state.rollPaused and Puzzle.TimeLeft(id) ~= nil and not Puzzle.TimerPaused(id) then
        state.rollPaused = true
        after[#after + 1] = function() Puzzle.PauseTimer(id) end
        changed = true
    elseif not rolling and state.rollPaused then
        state.rollPaused = nil
        after[#after + 1] = function() Puzzle.ResumeTimer(id) end
        changed = true
    end
    return changed
end


local AWAY_SECONDS = 5
local GONE_SECONDS = 60
local OFFER_SECONDS = 120

--Host-only: when each player was last seen at each seal. Not synced; a new host starts fresh.
---@type table<string, table<string, number>>
local g_lastSeen = {}

--Host: the hands stepping away, being replaced, a former hands coming back, stale offers.
---@param id string
---@param state table
---@return boolean changed
local function Presence(id, state)
    if state.phase ~= "playing" or type(state.parts) ~= "table" then
        return false
    end
    local parts = state.parts
    parts.readers = parts.readers or {}
    local now = dmhub.serverTime
    local seen = g_lastSeen[id] or {}
    g_lastSeen[id] = seen
    local present = {}
    for _, userid in ipairs(Puzzle.PresentUsers(id)) do
        present[userid] = true
        seen[userid] = now
    end
    local changed = false
    local hands = parts.hands
    if hands ~= nil and not parts.solo then
        if present[hands] then
            if state.away then
                state.away = nil
                changed = true
            end
        else
            seen[hands] = seen[hands] or now
            local gone = now - seen[hands]
            if gone >= AWAY_SECONDS and not state.away then
                state.away = true
                Log(state, string.format("%s, the hands, is away.", Puzzle.UserName(hands)))
                changed = true
            end
            if gone >= GONE_SECONDS then
                local prefs = state.prefs or {}
                local pick = nil
                for _, want in ipairs({ "hands", "either", "read" }) do
                    for userid in pairs(parts.readers) do
                        if pick == nil and present[userid] and (prefs[userid] or "either") == want then
                            pick = userid
                        end
                    end
                end
                if pick ~= nil then
                    local pages = PagesOf(parts, pick)
                    parts.readers[pick] = nil
                    parts.hands = pick
                    state.former = state.former or {}
                    state.former[hands] = true
                    local others = {}
                    for userid in pairs(parts.readers) do
                        if present[userid] then
                            others[#others + 1] = userid
                        end
                    end
                    table.sort(others)
                    if #others == 0 then
                        parts.solo = true
                    end
                    --the new hands' pages go round the readers still here.
                    for k, key in ipairs(pages) do
                        local r = others[(k - 1) % math.max(1, #others) + 1]
                        if r ~= nil then
                            local held = PagesOf(parts, r)
                            local has = false
                            for _, h in ipairs(held) do
                                has = has or h == key
                            end
                            if not has then
                                held[#held + 1] = key
                            end
                            parts.readers[r] = table.concat(held, ",")
                        end
                    end
                    state.away = nil
                    Log(state, string.format("%s has gone; %s takes the hands.", Puzzle.UserName(hands), Puzzle.UserName(pick)))
                    changed = true
                end
            end
        end
    end
    --a former hands back at the seal reads again.
    for userid in pairs(state.former or {}) do
        if present[userid] and not Dealt(parts, userid) then
            local key = LeastCovered(state.ward, parts)
            parts.readers[userid] = key
            parts.solo = false
            state.former[userid] = nil
            Log(state, string.format("%s is back and reads the %s page.", Puzzle.UserName(userid), PageTitle(state.ward, key)))
            changed = true
        end
    end
    --every page needs a reader: a page left with nobody (its reader took the hands, or
    --left with no one to pass it to) goes to whoever holds the fewest pages.
    if not parts.solo and next(parts.readers) ~= nil then
        local counts = {}
        for _, key in ipairs(PageKeys(state.ward)) do
            counts[key] = 0
        end
        for _, pages in pairs(parts.readers) do
            for key in string.gmatch(tostring(pages), "[^,]+") do
                if counts[key] ~= nil then
                    counts[key] = counts[key] + 1
                end
            end
        end
        for _, key in ipairs(PageKeys(state.ward)) do
            if counts[key] == 0 then
                local best, bestCount = nil, math.huge
                local readers = {}
                for userid in pairs(parts.readers) do
                    readers[#readers + 1] = userid
                end
                table.sort(readers)
                for _, userid in ipairs(readers) do
                    local n = #PagesOf(parts, userid) + (present[userid] and 0 or 100)
                    if n < bestCount then
                        best, bestCount = userid, n
                    end
                end
                if best ~= nil then
                    local held = PagesOf(parts, best)
                    held[#held + 1] = key
                    parts.readers[best] = table.concat(held, ",")
                    counts[key] = 1
                    Log(state, string.format("%s now also holds the %s page.", Puzzle.UserName(best), PageTitle(state.ward, key)))
                    changed = true
                end
            end
        end
    end
    for guid, offer in pairs(state.offers or {}) do
        if type(offer) ~= "table" or now - (tonumber(offer.at) or 0) > OFFER_SECONDS then
            state.offers[guid] = nil
            changed = true
        end
    end
    return changed
end

---@param state table
---@param config table
---@param userid string
---@param words string what was done, for the strike line
local function Strike(state, config, userid, words)
    if state.braced then
        state.braced = nil
        Log(state, string.format("%s %s: the ward flares, but braced hands hold it. No strike.", Puzzle.UserName(userid), words))
        return
    end
    state.strikes = (state.strikes or 0) + 1
    local limit = Effective(config).strikes
    if state.strikes >= limit then
        Log(state, string.format("%s %s: the ward bursts!", Puzzle.UserName(userid), words))
    else
        Log(state, string.format("Strike %d of %d: %s %s.", state.strikes, limit, Puzzle.UserName(userid), words))
    end
end

---@type PuzzleRequestHandler
local function HandleRequest(id, state, req, userid, after)
    local config = Puzzle.ReadConfig(id)
    if req.kind == "say" then
        Say(state, userid, req)
        return
    end
    if req.kind == "begin" then
        if state.phase ~= "playing" then
            Deal(id, state, config, userid)
            if Puzzle.EffectiveLimit(config) > 0 and Puzzle.TimeLeft(id) == nil then
                after[#after + 1] = function() Puzzle.StartTimer(id) end
            end
        end
        return
    end
    if state.phase ~= "playing" or state.ward == nil then
        return
    end
    local parts = state.parts or {}
    parts.readers = parts.readers or {}
    state.rolling = state.rolling or {}
    if req.kind == "rolling" then
        state.rolling[userid] = (req.on == true) and dmhub.serverTime or nil
        return
    elseif req.kind == "brace" then
        state.rolling[userid] = nil
        local tokenid = req.tokenid
        if config.brace == false or parts.hands ~= userid or type(tokenid) ~= "string" then
            return
        end
        local tier = math.tointeger(tonumber(req.tier)) or 1
        local outcome = Puzzle.TestOutcome(tier, tonumber(req.natural), tostring(config.testDifficulty or "medium"))
        --checked in the follow-up step: two requests in one tick both see the saved kept data.
        after[#after + 1] = function()
            if BraceTries(id)[tokenid] ~= nil then
                return
            end
            Puzzle.ChangeKept(id, function(kept)
                kept.brace = kept.brace or {}
                kept.brace[tokenid] = { tier = tier, user = userid, at = dmhub.serverTime }
            end, "Brace")
            local ok = outcome == "success" or outcome == "consequence"
            Puzzle.Change(id, function(st)
                if ok then
                    st.braced = true
                    Log(st, string.format("%s braces (tier %d): the next slip won't count.", Puzzle.UserName(userid), tier))
                else
                    Log(st, string.format("%s tries to brace, but their hands won't steady (tier %d).", Puzzle.UserName(userid), tier))
                end
            end, "Brace")
        end
        return
    elseif req.kind == "study" then
        state.rolling[userid] = nil
        local tokenid, key = req.tokenid, req.page
        if config.study == false or type(tokenid) ~= "string" or type(key) ~= "string" or key:sub(1, 1) ~= "m" then
            return
        end
        local holds = parts.solo == true and parts.hands == userid
        for _, k in ipairs(PagesOf(parts, userid)) do
            holds = holds or k == key
        end
        local i = math.tointeger(tonumber(key:sub(2)))
        if not holds or i == nil or state.ward.modules[i] == nil then
            return
        end
        --once per hero per ward: kept in the board, so a Reset (a new ward) clears it.
        state.studied = state.studied or {}
        if state.studied[tokenid] then
            return
        end
        state.studied[tokenid] = true
        local tier = math.tointeger(tonumber(req.tier)) or 1
        local outcome = Puzzle.TestOutcome(tier, tonumber(req.natural), tostring(config.testDifficulty or "medium"))
        local count = 0
        if outcome == "success" or outcome == "consequence" then
            count = tier >= 3 and 2 or 1
        end
        state.studyMarks = state.studyMarks or {}
        local deciding = PuzzleWardGen.DecidingLine(state.ward, i)
        local candidates = {}
        for _, line in ipairs(PuzzleWardGen.PageText(state.ward, i).lines) do
            local n = math.tointeger(tonumber(line:match("^(%d+)%.")))
            if n ~= nil and n ~= deciding and state.studyMarks[key .. "_" .. n] == nil then
                candidates[#candidates + 1] = n
            end
        end
        local random = Puzzle.SeededRandom(dmhub.GenerateGuid())
        local struck = {}
        while #struck < count and #candidates > 0 do
            local n = table.remove(candidates, random(#candidates))
            state.studyMarks[key .. "_" .. n] = { user = userid }
            struck[#struck + 1] = tostring(n)
        end
        table.sort(struck)
        local title = PageTitle(state.ward, key)
        if #struck == 0 then
            Log(state, string.format("%s studies the %s page but learns nothing (tier %d).", Puzzle.UserName(userid), title, tier))
        else
            Log(state, string.format("%s studies the ward and strikes out rule%s %s on the %s page.", Puzzle.UserName(userid),
                #struck > 1 and "s" or "", table.concat(struck, " and "), title))
        end
        return
    elseif req.kind == "moretime" then
        if Puzzle.TimeLeft(id) == nil then
            return
        end
        --unnamed: nobody has to say it was them.
        if DirectorOnline() then
            if state.timeAsk == nil then
                state.timeAsk = dmhub.serverTime
                Log(state, "Someone at the seal asks for more time.")
            end
        else
            after[#after + 1] = function()
                local left = Puzzle.TimeLeft(id)
                if left ~= nil then
                    Puzzle.ExtendTimer(id, left)
                end
            end
            Log(state, "Someone asks for more time: the ward's pulse slows.")
        end
        return
    elseif req.kind == "timeanswer" then
        if not CanReferee(userid) or state.timeAsk == nil then
            return
        end
        state.timeAsk = nil
        if req.give == true then
            after[#after + 1] = function()
                local left = Puzzle.TimeLeft(id)
                if left ~= nil then
                    Puzzle.ExtendTimer(id, left)
                end
            end
            Log(state, "The Director gives more time: the ward's pulse slows.")
        else
            Log(state, "The Director keeps the time as it is.")
        end
        return
    end
    if req.kind == "join" then
        if not Dealt(parts, userid) and not IsDirectorUser(userid) then
            local key = LeastCovered(state.ward, parts)
            parts.readers[userid] = key
            parts.solo = false
            Log(state, string.format("%s joins and reads the %s page.", Puzzle.UserName(userid), PageTitle(state.ward, key)))
        end
        return
    elseif req.kind == "offer" then
        local to = req.to
        local offerKind = req.offerKind
        if not Dealt(parts, userid) or type(to) ~= "string" or to == userid or not Dealt(parts, to) then
            return
        end
        if offerKind == "pass" and parts.hands ~= userid then
            return
        elseif offerKind == "take" and parts.hands ~= to then
            return
        elseif offerKind ~= "pass" and offerKind ~= "take" and offerKind ~= "swap" then
            return
        end
        for guid, offer in pairs(state.offers) do
            if type(offer) == "table" and offer.from == userid then
                state.offers[guid] = nil
            end
        end
        --swapping once the work has started needs the Director's (or host's) OK.
        state.offers[dmhub.GenerateGuid()] = { kind = offerKind, from = userid, to = to, at = dmhub.serverTime,
            approved = offerKind ~= "swap" or not Started(state) }
        return
    elseif req.kind == "answer" or req.kind == "approve" then
        local guid = req.offer
        local offer = type(guid) == "string" and state.offers[guid] or nil
        if type(offer) ~= "table" then
            return
        end
        if req.kind == "answer" and req.accept ~= true then
            if userid == offer.to or userid == offer.from or CanReferee(userid) then
                state.offers[guid] = nil
            end
            return
        end
        if req.kind == "answer" and (userid == offer.to or (offer.kind == "take" and CanReferee(userid))) then
            offer.accepted = true
            if offer.kind == "take" and CanReferee(userid) then
                offer.approved = true
            end
        elseif req.kind == "approve" and CanReferee(userid) then
            offer.approved = true
            if offer.kind == "take" then
                offer.accepted = true
            end
        end
        if offer.accepted and offer.approved then
            state.offers[guid] = nil
            if Dealt(parts, offer.from) and Dealt(parts, offer.to) then
                SwapParts(parts, offer.from, offer.to)
                if offer.kind == "swap" then
                    Log(state, string.format("%s and %s swap parts.", Puzzle.UserName(offer.from), Puzzle.UserName(offer.to)))
                else
                    Log(state, string.format("%s now has the hands.", Puzzle.UserName(parts.hands)))
                end
            end
        end
        return
    elseif req.kind == "makehands" then
        local target = req.target
        if not CanReferee(userid) or type(target) ~= "string" or target == parts.hands then
            return
        end
        if Dealt(parts, target) then
            SwapParts(parts, parts.hands, target)
        else
            local old = parts.hands
            parts.hands = target
            parts.readers[target] = nil
            if old ~= nil then
                parts.readers[old] = LeastCovered(state.ward, parts)
            end
            parts.solo = false
        end
        state.away = nil
        Log(state, string.format("%s now has the hands.", Puzzle.UserName(target)))
        return
    elseif req.kind == "redeal" then
        if CanReferee(userid) then
            Deal(id, state, config, userid, true)
        end
        return
    end
    if parts.hands ~= userid then
        return
    end
    local limit = Effective(config).strikes
    if (state.strikes or 0) >= limit then
        return
    end
    local i = math.tointeger(tonumber(req.module))
    local m = i ~= nil and state.ward.modules[i] or nil
    if i == nil or m == nil or ModuleDone(state, i) or ModuleSealed(state, i) then
        return
    end
    state.act = state.act or {}
    state.act["m" .. i] = state.act["m" .. i] or {}
    local act = state.act["m" .. i]
    if req.kind == "cut" and m.kind == "threads" then
        local n = math.tointeger(tonumber(req.thread))
        if n == nil or n < 1 or n > #m.threads then
            return
        end
        act.cut = act.cut or {}
        if act.cut["t" .. n] then
            return
        end
        act.cut["t" .. n] = true
        if n == m.answer then
            Log(state, string.format("%s cut %s. The threads go dark.", Puzzle.UserName(userid), ThreadWords(state.ward, i, n)))
        else
            Strike(state, config, userid, "cut " .. ThreadWords(state.ward, i, n))
        end
    elseif req.kind == "touch" and m.kind == "glyphs" then
        local pos = math.tointeger(tonumber(req.glyph))
        if pos == nil or pos < 1 or pos > 4 then
            return
        end
        local lit = Numbers(act.lit)
        for _, p in ipairs(lit) do
            if p == pos then
                return
            end
        end
        local name = string.format("Glyph %s (%s)", PuzzleWardGen.letters[pos], PuzzleRunes.Name(m.glyphs[pos]))
        if m.answer[#lit + 1] == pos then
            lit[#lit + 1] = pos
            act.lit = table.concat(lit, ",")
            if #lit >= 4 then
                Log(state, string.format("%s touched %s. The glyphs burn out.", Puzzle.UserName(userid), name))
            end
        else
            Strike(state, config, userid, "touched " .. name)
        end
    elseif req.kind == "set" and m.kind == "dial" then
        local rune = math.tointeger(tonumber(req.rune))
        if rune == nil or rune < 1 or rune > #PuzzleRunes.list then
            return
        end
        if rune == m.answer then
            act.set = rune
            Log(state, string.format("%s set the dial to %s. The sigil sinks into the stone.", Puzzle.UserName(userid), PuzzleRunes.Name(rune)))
        else
            Strike(state, config, userid, "set the dial to " .. PuzzleRunes.Name(rune))
        end
    end
end

---@param id string
local function HostTick(id)
    local status = Puzzle.Status(id)
    if status.solved or status.failed then
        return
    end
    local after = {}
    Puzzle.Change(id, function(state)
        local changed = Puzzle.ProcessRequests(id, state, HandleRequest, after)
        changed = Presence(id, state) or changed
        changed = RollPause(id, state, after) or changed
        if not changed then
            return false
        end
    end, "Warded seal")
    for _, fn in ipairs(after) do
        pcall(fn)
    end
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

--Private pencil marks: puzzle id -> "key:line" -> true. Never synced.
---@type table<string, table<string, boolean>>
local g_pencil = {}

---@param ctx PuzzleContext
---@return Panel
local function Render(ctx)
    EnsureBindings()
    local m_ctx = ctx
    local m_confirmSolo = false
    local m_gatherKey = nil
    local m_thinks = 0
    local resultPanel
    local body
    local chatPanel
    local chatInputRow
    local C = WardColours()
    --keyboard: the parts the hands can act on, the one under the cursor, an action
    --waiting for "Confirm each action".
    local m_targets = {} ---@type table[]
    local m_cursor = 1
    local m_contextActive = false
    local m_pending = nil ---@type {req: table, words: string, at: number}|nil
    local m_signature = nil

    local function State()
        return m_ctx.state or {}
    end

    local function Request(args)
        Puzzle.Request(m_ctx.id, args)
    end

    local Refresh

    local SIZE_UP = { sizeXs = "sizeS", sizeS = "sizeM", sizeM = "sizeL", sizeL = "sizeXl" }

    --"Larger text": every size class one step up.
    ---@param classes string[]
    ---@return string[]
    local function Classes(classes)
        if not m_ctx:Assist("text") then
            return classes
        end
        local out = {}
        for i, c in ipairs(classes) do
            out[i] = SIZE_UP[c] or c
        end
        return out
    end

    --a control's fixed size, grown to fit larger text.
    ---@param px number
    ---@return number
    local function H(px)
        return m_ctx:Assist("text") and math.floor(px * 1.35) or px
    end

    --the ward's pictures: "Larger ward" and the UI scale.
    ---@param px number
    ---@return number
    local function Art(px)
        return math.floor(px * (m_ctx:Assist("large") and 1.5 or 1) * ArtScale())
    end

    --keys reach the seal only while its window itself holds the focus (not the chat box).
    local function SyncContext()
        --only the hands has anything for the keys to do; for anyone else a focus change
        --must not rebuild the panel (that would close an open dropdown).
        local want = #m_targets > 0 and resultPanel ~= nil and resultPanel.valid and gui.GetFocus() == resultPanel
        if want ~= m_contextActive then
            m_contextActive = want
            if want then
                dmhub.PushCommandContext(COMMAND_CONTEXT)
            else
                dmhub.PopCommandContext(COMMAND_CONTEXT)
            end
            --redraw (cursor, key hint) only on gaining the keys: losing them can mean a
            --dropdown just opened, and a rebuild would close it.
            if want and Refresh ~= nil then
                Refresh()
            end
        end
    end

    local function Focus()
        if resultPanel ~= nil and resultPanel.valid and gui.GetFocus() ~= resultPanel then
            gui.SetFocus(resultPanel)
        end
        SyncContext()
    end

    --a chat line from this player.
    ---@param style string
    ---@param text string
    local function Post(style, text)
        Request({ kind = "say", style = style, text = text })
    end

    --an action on the ward: straight to the host, or held for a yes under "Confirm each action".
    ---@param req table
    ---@param words string
    local function Do(req, words)
        if m_ctx:Assist("confirm") then
            m_pending = { req = req, words = words, at = dmhub.Time() }
            Refresh()
            return
        end
        Request(req)
    end

    ---@param text string
    ---@param classes string[]|nil
    ---@param extra table|nil
    ---@return Panel
    local function Label(text, classes, extra)
        local args = { classes = Classes(classes or {"sizeS"}), width = "auto", maxWidth = m_ctx:Assist("text") and 700 or 520, height = "auto", text = text }
        for k, v in pairs(extra or {}) do
            args[k] = v
        end
        return gui.Label(args)
    end

    local function RuneIcon(rune, size, color)
        local r = PuzzleRunes.list[rune]
        return gui.Panel{
            width = size,
            height = size,
            valign = "center",
            bgimage = r ~= nil and r.icon or "panels/square.png",
            bgcolor = color or C.rune,
            interactable = false,
        }
    end

    local function Gathering()
        local players = PlayersAtSeal(m_ctx.id)
        local names = {}
        for i, userid in ipairs(players) do
            names[i] = Puzzle.UserName(userid)
        end
        local children = {}
        if #names == 0 then
            children[#children + 1] = Label("Nobody is at the seal yet.", {"sizeM"})
        else
            children[#children + 1] = Label(string.format("At the seal: %s.", table.concat(names, ", ")), {"sizeM"})
        end
        children[#children + 1] = Label("Waiting for the others. Anyone can begin; the parts are dealt then.", {"sizeS", "fgMuted"})
        if m_ctx.isDirector then
            children[#children + 1] = Label("Directors are not dealt a part.", {"sizeS", "fgMuted"})
        else
            children[#children + 1] = gui.Panel{
                flow = "horizontal", width = "auto", height = "auto", tmargin = 6,
                Label("I'd rather:", {"sizeS"}, { valign = "center", hmargin = 4 }),
                gui.Dropdown{
                    width = 180,
                    options = { { id = "either", text = "Either part" }, { id = "hands", text = "Be the hands" }, { id = "read", text = "Read" } },
                    idChosen = g_partPreference:Get(),
                    change = function(dropdown)
                        ---@cast dropdown Dropdown
                        g_partPreference:Set(dropdown.idChosen)
                    end,
                },
            }
        end
        --the Director (or the host with no Director) can say who will be the hands.
        if IsDMOrPlayerHost() and #players > 1 then
            local pins = type(m_ctx.config.roles) == "table" and m_ctx.config.roles or {}
            for _, userid in ipairs(players) do
                local uid = userid
                local pinned = pins[uid] == "hands"
                children[#children + 1] = gui.Panel{
                    flow = "horizontal", width = "auto", height = "auto", vmargin = 1,
                    Label(Puzzle.UserName(uid) .. (pinned and " (will be the hands)" or ""), {"sizeS"}, { width = 240, valign = "center" }),
                    gui.Button{
                        classes = Classes{"sizeXs"}, text = pinned and "Let the deal decide" or "Make the hands",
                        width = 140, height = H(22), valign = "center",
                        click = function()
                            local roles = {}
                            if not pinned then
                                roles[uid] = "hands"
                            end
                            Puzzle.SetConfig(m_ctx.id, { roles = roles })
                        end,
                    },
                }
            end
        end
        if m_confirmSolo then
            children[#children + 1] = Label("You alone will see the ward and its codex. Begin?", {"sizeM"}, { tmargin = 6 })
            children[#children + 1] = gui.Panel{
                flow = "horizontal", width = "auto", height = "auto",
                gui.Button{ classes = Classes{"sizeS"}, text = "Begin alone", width = 120, hmargin = 4,
                    click = function() m_confirmSolo = false Request({ kind = "begin" }) end },
                gui.Button{ classes = Classes{"sizeS"}, text = "Cancel", width = 90,
                    click = function() m_confirmSolo = false Refresh() end },
            }
        else
            children[#children + 1] = gui.Button{
                classes = Classes{"sizeM"},
                text = "Begin",
                width = 140,
                tmargin = 8,
                click = function()
                    if #players <= 1 then
                        m_confirmSolo = true
                        Refresh()
                        return
                    end
                    Request({ kind = "begin" })
                end,
            }
        end
        return children
    end

    --The shared view everyone gets: the modules, their state and who holds each page.
    local function ModuleList()
        local state = State()
        local holders = {}
        for userid, pages in pairs((state.parts or {}).readers or {}) do
            for key in string.gmatch(tostring(pages), "[^,]+") do
                holders[key] = holders[key] or {}
                holders[key][#holders[key] + 1] = Puzzle.UserName(userid)
            end
        end
        local lines = {}
        for i, m in ipairs(state.ward.modules) do
            local status
            if ModuleDone(state, i) then
                status = "done"
            elseif ModuleSealed(state, i) then
                status = "sealed until the Glyphs are done"
            else
                status = "unbroken"
            end
            local who = holders["m" .. i]
            lines[#lines + 1] = string.format("%d. %s -- %s%s", i, KIND_NAMES[m.kind], status,
                who ~= nil and (" -- page: " .. table.concat(who, ", ")) or "")
        end
        for k = 1, 3 do
            local who = holders["L" .. k]
            if who ~= nil then
                lines[#lines + 1] = string.format("Lexicon %d -- page: %s", k, table.concat(who, ", "))
            end
        end
        return Label(table.concat(lines, "\n"), {"sizeS"}, { tmargin = 4 })
    end

    --is this part under the keyboard cursor? (n is 0 for a dial)
    local function Cursor(i, n)
        local t = m_targets[m_cursor]
        return m_contextActive and t ~= nil and t.i == i and t.n == n
    end

    local function TurnDial(i, step)
        local state = State()
        local m = state.ward.modules[i]
        local pos = math.tointeger(tonumber(Act(state, i).pos)) or m.waking
        local v = ((pos - 1 + step) % #PuzzleRunes.list) + 1
        m_ctx:Change(function(st)
            st.act = st.act or {}
            st.act["m" .. i] = st.act["m" .. i] or {}
            st.act["m" .. i].pos = v
        end, "Turn the dial")
    end

    ---@param i integer
    ---@param m table
    ---@return string
    local function DialWords(i, m)
        local pos = math.tointeger(tonumber(Act(State(), i).pos)) or m.waking
        return string.format("Sigil dial: woke on %s, now shows %s.", PuzzleRunes.Name(m.waking), PuzzleRunes.Name(pos))
    end

    --one line for the chat that says everything the hands sees on a module.
    ---@param i integer
    ---@param m table
    ---@return string
    local function ModuleWords(i, m)
        local items = {}
        if m.kind == "threads" then
            for n, t in ipairs(m.threads) do
                items[n] = string.format("%d %s, %s", n, PuzzleRunes.threadColours[t.colour].name, PuzzleRunes.threadPatterns[t.pattern].name)
            end
            return "Threads: " .. table.concat(items, "; ") .. "."
        elseif m.kind == "glyphs" then
            for pos, rune in ipairs(m.glyphs) do
                items[pos] = string.format("%s %s", PuzzleWardGen.letters[pos], PuzzleRunes.Name(rune))
            end
            return "Glyphs: " .. table.concat(items, ", ") .. "."
        end
        return DialWords(i, m)
    end

    --a label the hands can click to quote it in the chat.
    local function Quotable(text, words, classes, extra, canAct)
        extra = extra or {}
        if canAct then
            extra.press = function() Post("quote", words) end
        end
        return Label(text, classes, extra)
    end

    local function WardFace(canAct)
        local face = State().ward.face
        local words = string.format("Rim: %s. Candles lit: %d.", PuzzleRunes.Name(face.rim), face.candles)
        return gui.Panel{
            flow = "horizontal", width = "auto", height = "auto", vmargin = 4,
            Label("Rim:", {"sizeM"}, { valign = "center" }),
            RuneIcon(face.rim, Art(28)),
            Quotable(string.format("%s.   Candles lit: %d", PuzzleRunes.Name(face.rim), face.candles), words, {"sizeM"}, { valign = "center", hmargin = 6 }, canAct),
        }
    end

    local function ThreadsView(i, m, canAct)
        local act = Act(State(), i)
        local rows = {}
        for n, t in ipairs(m.threads) do
            local severed = type(act.cut) == "table" and act.cut["t" .. n] == true
            local words = string.format("Thread %d: %s, %s", n, PuzzleRunes.threadColours[t.colour].name, PuzzleRunes.threadPatterns[t.pattern].name)
            local req = { kind = "cut", module = i, thread = n }
            if canAct and not severed then
                m_targets[#m_targets + 1] = { i = i, n = n, words = words, req = req, ask = "Cut " .. words .. "?" }
            end
            local here = Cursor(i, n)
            rows[#rows + 1] = gui.Panel{
                flow = "horizontal", width = "auto", height = "auto", vmargin = 1,
                bgimage = "panels/square.png", bgcolor = "#00000000", border = here and 2 or 0, borderColor = C.cursor,
                gui.Panel{
                    width = Art(260), height = Art(20), valign = "center", opacity = severed and 0.35 or 1,
                    PuzzleRunes.ThreadPanel(t.colour, t.pattern, Art(260), Art(C.thick)),
                },
                Quotable(words .. (severed and " (severed)" or ""), words, {"sizeS"}, { width = H(220), valign = "center", hmargin = 8 }, canAct),
                (canAct and not severed) and gui.Button{
                    classes = Classes{"sizeXs"}, text = "Cut", width = H(50), height = H(22), valign = "center",
                    click = function() Focus() Do(req, "Cut " .. words .. "?") end,
                } or nil,
            }
        end
        return rows
    end

    local function GlyphsView(i, m, canAct)
        local lit = {}
        for _, p in ipairs(Numbers(Act(State(), i).lit)) do
            lit[p] = true
        end
        local cells = {}
        for pos, rune in ipairs(m.glyphs) do
            local words = string.format("Glyph %s: %s", PuzzleWardGen.letters[pos], PuzzleRunes.Name(rune))
            local req = { kind = "touch", module = i, glyph = pos }
            if canAct and not lit[pos] then
                m_targets[#m_targets + 1] = { i = i, n = pos, words = words, req = req, ask = "Touch " .. words .. "?" }
            end
            local here = Cursor(i, pos)
            cells[#cells + 1] = gui.Panel{
                flow = "vertical", width = math.max(Art(96), H(96)), height = "auto", hmargin = 4,
                gui.Panel{
                    width = Art(56), height = Art(56), halign = "center",
                    bgimage = "panels/square.png", bgcolor = C.bg,
                    border = (here or lit[pos]) and 3 or 1, borderColor = here and C.cursor or (lit[pos] and C.lit or C.border),
                    press = function()
                        if canAct and not lit[pos] then
                            Focus()
                            Do(req, "Touch " .. words .. "?")
                        end
                    end,
                    gui.Panel{ width = Art(40), height = Art(40), halign = "center", valign = "center",
                        bgimage = PuzzleRunes.list[rune].icon, bgcolor = lit[pos] and C.lit or C.rune, interactable = false },
                },
                Quotable(string.format("%s: %s%s", PuzzleWardGen.letters[pos], PuzzleRunes.Name(rune), lit[pos] and " (lit)" or ""), words,
                    {"sizeS"}, { halign = "center", textAlignment = "center", width = math.max(Art(96), H(96)) }, canAct),
            }
        end
        return { gui.Panel{ flow = "horizontal", width = "auto", height = "auto", children = cells } }
    end

    local function DialView(i, m, canAct)
        local state = State()
        local pos = math.tointeger(tonumber(Act(state, i).pos)) or m.waking
        local live = canAct and not ModuleSealed(state, i)
        local words = DialWords(i, m)
        local req = { kind = "set", module = i, rune = pos }
        local ask = string.format("Set the seal on %s?", PuzzleRunes.Name(pos))
        if live then
            m_targets[#m_targets + 1] = { i = i, n = 0, dial = true, words = words, req = req, ask = ask }
        end
        local here = Cursor(i, 0)
        local rows = {
            Quotable(string.format("Woke on %s.", PuzzleRunes.Name(m.waking)), words, {"sizeS"}, nil, canAct),
            gui.Panel{
                flow = "horizontal", width = "auto", height = "auto", vmargin = 2,
                live and gui.Button{ classes = Classes{"sizeXs"}, text = "-", width = H(30), height = H(24), valign = "center",
                    click = function() Focus() TurnDial(i, -1) end } or nil,
                gui.Panel{ width = Art(56), height = Art(56), hmargin = 6, bgimage = "panels/square.png", bgcolor = C.bg,
                    border = here and 3 or 2, borderColor = here and C.cursor or C.border,
                    RuneIcon(pos, Art(40)) },
                live and gui.Button{ classes = Classes{"sizeXs"}, text = "+", width = H(30), height = H(24), valign = "center",
                    click = function() Focus() TurnDial(i, 1) end } or nil,
                Quotable(PuzzleRunes.Name(pos), words, {"sizeM"}, { valign = "center", hmargin = 8 }, canAct),
                live and gui.Button{ classes = Classes{"sizeS"}, text = "Set the seal", width = H(120), valign = "center", hmargin = 8,
                    click = function() Focus() Do(req, ask) end } or nil,
            },
        }
        if ModuleSealed(state, i) then
            rows[#rows + 1] = Label("Sealed until the Glyphs are done.", {"sizeS", "fgMuted"})
        end
        return rows
    end

    --The ward itself: face and every module, for the hands (and solo, and the Director).
    local function WardView(canAct)
        local state = State()
        m_targets = {}
        local children = {}
        if m_pending ~= nil and canAct then
            children[#children + 1] = gui.Panel{
                flow = "horizontal", width = "auto", height = "auto", vmargin = 4,
                Label(m_pending.words, {"sizeM", "bold"}, { valign = "center", hmargin = 4 }),
                gui.Button{ classes = Classes{"sizeS"}, text = "Yes", width = H(70), hmargin = 4, valign = "center",
                    click = function()
                        local pending = m_pending
                        m_pending = nil
                        if pending ~= nil then
                            Request(pending.req)
                        end
                        Focus()
                        Refresh()
                    end },
                gui.Button{ classes = Classes{"sizeS"}, text = "No", width = H(70), valign = "center",
                    click = function() m_pending = nil Focus() Refresh() end },
            }
        end
        children[#children + 1] = WardFace(canAct)
        for i, m in ipairs(state.ward.modules) do
            local done = ModuleDone(state, i)
            children[#children + 1] = gui.Panel{
                flow = "horizontal", width = "auto", height = "auto", tmargin = 6,
                Label(string.format("%d. %s%s", i, KIND_NAMES[m.kind], done and " (done)" or ""), {"sizeM", "bold"}, { valign = "center" }),
                (canAct and not done) and gui.Button{ classes = Classes{"sizeXs"}, text = "Quote", width = H(60), height = H(22), hmargin = 8, valign = "center",
                    click = function() Post("quote", ModuleWords(i, m)) end } or nil,
            }
            local rows = {}
            if not done then
                if m.kind == "threads" then
                    rows = ThreadsView(i, m, canAct)
                elseif m.kind == "glyphs" then
                    rows = GlyphsView(i, m, canAct)
                else
                    rows = DialView(i, m, canAct)
                end
            end
            for _, row in ipairs(rows) do
                children[#children + 1] = row
            end
        end
        m_cursor = math.max(1, math.min(m_cursor, #m_targets))
        if canAct then
            children[#children + 1] = Label(m_contextActive
                and ("Keys: Up and Down choose a part, Left and Right turn the dial, Enter acts, Q quotes it in the chat."
                    .. (m_ctx:Assist("confirm") and " Enter again says yes; N says no." or ""))
                or "Click a part's name to quote it in the chat. Click the ward to play with the keyboard.",
                {"sizeXs", "fgMuted"}, { tmargin = 6 })
        end
        return gui.Panel{
            flow = "vertical", width = "auto", height = "auto", pad = 10, borderBox = true, tmargin = 4,
            bgimage = "panels/square.png", bgcolor = C.bg, border = 1, borderColor = C.border,
            click = canAct and function() Focus() end or nil,
            children = children,
        }
    end

    --the keyboard's Enter: answer a waiting confirm, else act on the part under the cursor.
    local function Activate()
        if m_pending ~= nil then
            --one Enter press fires both the "return" and "enter" bindings: the second
            --must not answer the question the first just asked.
            if dmhub.Time() - m_pending.at < 0.3 then
                return
            end
            local pending = m_pending
            m_pending = nil
            Request(pending.req)
            Refresh()
            return
        end
        local t = m_targets[m_cursor]
        if t ~= nil then
            Do(t.req, t.ask)
        end
    end

    ---@param step integer
    local function MoveCursor(step)
        if #m_targets == 0 then
            return
        end
        m_cursor = ((m_cursor - 1 + step) % #m_targets) + 1
        Refresh()
    end

    local BRACE_TIERS = { "Your hands shake.", "Your hands steady.", "Your hands are stone." }
    local STUDY_TIERS = { "The ward keeps its secrets.", "You see through one rule.", "You see through two rules." }

    --A test roll: the timer waits while it is open; the result goes to the host.
    ---@param tok CharacterToken
    ---@param attrid string
    ---@param skill string
    ---@param name string
    ---@param tiers string[]
    ---@param args table the request to send with the result
    local function RollFor(tok, attrid, skill, name, tiers, args)
        local id = m_ctx.id
        Request({ kind = "rolling", on = true })
        Puzzle.RollTest(tok, attrid, skill, name, tiers, function()
            return not Puzzle.Status(id).solved and not Puzzle.Status(id).failed
        end, function(tier, natural)
            args.tokenid = tok.charid
            args.tier = tier
            args.natural = natural
            Puzzle.Request(id, args)
        end, function()
            Puzzle.Request(id, { kind = "rolling", on = false })
        end)
    end

    --The Study button on a module page, for whoever holds it.
    ---@param key string
    ---@return Panel|nil
    local function StudyButton(key)
        local state = State()
        local role = RoleOf(state, m_ctx.userid, m_ctx.isDirector)
        if key:sub(1, 1) ~= "m" or m_ctx.config.study == false or m_ctx.readonly or (role ~= "reader" and role ~= "solo") then
            return nil
        end
        local tok = Puzzle.MyHero()
        local reason = nil
        if tok == nil then
            reason = "Select your hero to study."
        elseif (state.studied or {})[tok.charid] then
            reason = "Your hero has studied this ward."
        end
        if reason ~= nil then
            return Label(reason, {"sizeXs", "fgMuted"}, { valign = "center", hmargin = 8 })
        end
        return gui.Button{
            classes = Classes{"sizeXs"}, text = "Study (Reason)", width = "auto", minWidth = 110, hpad = 6, height = H(22), hmargin = 8, valign = "center",
            click = function()
                RollFor(tok --[[@as CharacterToken]], "rea", "Magic", "Study the ward", STUDY_TIERS, { kind = "study", page = key })
            end,
        }
    end

    --Brace for the hands, More time for the players, the Director's answer.
    ---@param role string
    ---@param canAct boolean
    ---@return Panel[]
    local function TestRows(role, canAct)
        local state = State()
        local rows = {}
        if canAct and m_ctx.config.brace ~= false then
            if state.braced then
                rows[#rows + 1] = Label("Braced: your next slip won't count.", {"sizeS", "bold"}, { tmargin = 4 })
            else
                local tok = Puzzle.MyHero()
                local reason = nil
                if tok == nil then
                    reason = "Select your hero to brace."
                elseif BraceTries(m_ctx.id)[tok.charid] ~= nil then
                    reason = "Your hero has braced at this seal."
                end
                if reason ~= nil then
                    rows[#rows + 1] = Label(reason, {"sizeS", "fgMuted"}, { tmargin = 4 })
                else
                    rows[#rows + 1] = gui.Button{
                        classes = Classes{"sizeS"}, text = "Brace (Agility)", width = 160, tmargin = 4,
                        click = function()
                            RollFor(tok --[[@as CharacterToken]], "agl", "Sabotage", "Brace", BRACE_TIERS, { kind = "brace" })
                        end,
                    }
                end
            end
        end
        if Puzzle.TimeLeft(m_ctx.id) ~= nil and not m_ctx.readonly then
            if state.timeAsk ~= nil and IsDMOrPlayerHost() then
                rows[#rows + 1] = gui.Panel{
                    flow = "horizontal", width = "auto", height = "auto", tmargin = 4,
                    Label("Someone at the seal asks for more time.", {"sizeS"}, { valign = "center" }),
                    gui.Button{ classes = Classes{"sizeXs"}, text = "Double the time", width = "auto", hpad = 6, height = H(22), hmargin = 4, valign = "center",
                        click = function() Request({ kind = "timeanswer", give = true }) end },
                    gui.Button{ classes = Classes{"sizeXs"}, text = "No", width = 50, height = H(22), valign = "center",
                        click = function() Request({ kind = "timeanswer", give = false }) end },
                }
            elseif not m_ctx.isDirector then
                rows[#rows + 1] = gui.Button{
                    classes = Classes{"sizeS"}, text = state.timeAsk ~= nil and "More time asked" or "More time", width = 160, tmargin = 4,
                    click = function()
                        if state.timeAsk == nil then
                            Request({ kind = "moretime" })
                        end
                    end,
                }
            end
        end
        return rows
    end


    --A reader's Ask (questions from this page's rules) and Point (an action for the hands).
    ---@param key string
    ---@return Panel|nil
    local function AskRow(key)
        local state = State()
        local role = RoleOf(state, m_ctx.userid, m_ctx.isDirector)
        if role ~= "reader" or m_ctx.readonly then
            return nil
        end
        local asks = {}
        for k, q in ipairs(PuzzleWardGen.Questions(state.ward, key)) do
            asks[k] = { id = q, text = q }
        end
        local controls = {
            gui.Dropdown{
                classes = Classes{"sizeS"}, width = H(300), hmargin = 3,
                options = asks,
                textDefault = "Ask the hands...",
                change = function(dropdown)
                    ---@cast dropdown Dropdown
                    if dropdown.idChosen ~= nil then
                        Post("ask", tostring(dropdown.idChosen))
                    end
                end,
            },
        }
        local i = key:sub(1, 1) == "m" and math.tointeger(tonumber(key:sub(2))) or nil
        local m = i ~= nil and state.ward.modules[i] or nil
        if m ~= nil then
            --never more than the page already tells: up to six threads, any rune.
            local points = {}
            if m.kind == "threads" then
                for n = 1, 6 do
                    points[#points + 1] = string.format("cut Thread %d", n)
                end
            elseif m.kind == "glyphs" then
                for _, letter in ipairs(PuzzleWardGen.letters) do
                    points[#points + 1] = string.format("touch Glyph %s", letter)
                end
                for _, r in ipairs(PuzzleRunes.list) do
                    points[#points + 1] = string.format("touch the %s", r.name)
                end
            else
                for _, r in ipairs(PuzzleRunes.list) do
                    points[#points + 1] = string.format("set the dial to %s", r.name)
                end
            end
            local options = {}
            for k, text in ipairs(points) do
                options[k] = { id = text, text = text }
            end
            controls[#controls + 1] = gui.Dropdown{
                classes = Classes{"sizeS"}, width = H(200), hmargin = 3,
                options = options,
                textDefault = "Point...",
                change = function(dropdown)
                    ---@cast dropdown Dropdown
                    if dropdown.idChosen ~= nil then
                        Post("point", tostring(dropdown.idChosen))
                    end
                end,
            }
        end
        return gui.Panel{ flow = "horizontal", width = "auto", height = "auto", vmargin = 2, children = controls }
    end

    --A codex page: click a rule to pencil it out (only you see it).
    local function PageView(key)
        local page = PageFor(State().ward, key)
        if page == nil then
            return nil
        end
        local pencil = g_pencil[m_ctx.id] or {}
        g_pencil[m_ctx.id] = pencil
        local children = {
            gui.Panel{
                flow = "horizontal", width = "auto", height = "auto",
                Label(page.title, {"sizeM", "bold"}, { valign = "center" }),
                StudyButton(key),
            },
            AskRow(key),
            Label(page.intro, {"sizeS", "fgMuted"}),
        }
        local marks = State().studyMarks or {}
        if key:sub(1, 1) == "m" then
            children[#children + 1] = Label(PuzzleWardGen.pageHeader, {"sizeS", "bold"})
        end
        for n, line in ipairs(page.lines) do
            local mark = key .. ":" .. n
            local studied = type(marks[key .. "_" .. n]) == "table"
            local out = pencil[mark] == true or studied
            children[#children + 1] = gui.Label{
                classes = Classes{"sizeS", out and "fgMuted" or "fg"},
                width = m_ctx:Assist("text") and 640 or 480, height = "auto", vmargin = 1,
                text = out and ("<s>" .. line .. "</s>" .. (studied and " (studied)" or "")) or line,
                press = function()
                    pencil[mark] = (not out) or nil
                    Refresh()
                end,
            }
        end
        return gui.Panel{ flow = "vertical", width = "auto", height = "auto", tmargin = 8, children = children }
    end

    local function LogText()
        local entries = {}
        for _, e in pairs(State().log or {}) do
            if type(e) == "table" then
                entries[#entries + 1] = e
            end
        end
        table.sort(entries, function(a, b) return (tonumber(a.seq) or 0) < (tonumber(b.seq) or 0) end)
        local lines = {}
        for i = math.max(1, #entries - LOG_LINES + 1), #entries do
            lines[#lines + 1] = entries[i].text
        end
        return table.concat(lines, "\n")
    end

    --Changing parts: offers to and from this player, Join in, and the referee's controls.
    ---@param role string
    ---@return Panel[]
    local function PartsRows(role)
        local state = State()
        local parts = state.parts or {}
        local me = m_ctx.userid
        local rows = {}
        local offers = {}
        for guid, offer in pairs(state.offers or {}) do
            if type(offer) == "table" then
                offers[#offers + 1] = { guid = guid, offer = offer }
            end
        end
        table.sort(offers, function(a, b) return (tonumber(a.offer.at) or 0) < (tonumber(b.offer.at) or 0) end)

        local function Buttons(...)
            return gui.Panel{ flow = "horizontal", width = "auto", height = "auto", vmargin = 1, children = { ... } }
        end
        local function Small(text, fn)
            return gui.Button{ classes = Classes{"sizeXs"}, text = text, width = "auto", minWidth = 70, hpad = 6, height = H(22), hmargin = 3, valign = "center", click = fn }
        end

        if role == "watching" and not m_ctx.readonly then
            rows[#rows + 1] = Buttons(
                Label("The seal is being worked. Join in to read a page.", {"sizeS"}, { valign = "center" }),
                Small("Join in", function() Request({ kind = "join" }) end))
        end

        local dealt = role == "hands" or role == "reader"
        for _, entry in ipairs(offers) do
            local o, guid = entry.offer, entry.guid
            local from, to = Puzzle.UserName(o.from), Puzzle.UserName(o.to)
            if o.to == me and not o.accepted then
                local text
                if o.kind == "swap" then
                    text = string.format("%s offers to swap parts with you.", from)
                elseif o.kind == "pass" then
                    text = string.format("%s offers you the hands.", from)
                else
                    text = string.format("%s asks to take the hands.", from)
                end
                rows[#rows + 1] = Buttons(Label(text, {"sizeS"}, { valign = "center" }),
                    Small("Accept", function() Request({ kind = "answer", offer = guid, accept = true }) end),
                    Small("Decline", function() Request({ kind = "answer", offer = guid, accept = false }) end))
            elseif o.from == me then
                local text = string.format("Waiting for %s%s.", cond(o.accepted, "", to), cond(o.approved, "", cond(o.accepted, "the Director's OK", " and the Director's OK")))
                rows[#rows + 1] = Buttons(Label(text, {"sizeS", "fgMuted"}, { valign = "center" }),
                    Small("Cancel", function() Request({ kind = "answer", offer = guid, accept = false }) end))
            end
            if IsDMOrPlayerHost() and not o.approved then
                local text
                if o.kind == "take" then
                    text = string.format("%s asks to take the hands from %s.", from, to)
                else
                    text = string.format("%s and %s want to swap parts.", from, to)
                end
                rows[#rows + 1] = Buttons(Label(text, {"sizeS"}, { valign = "center" }),
                    Small("Approve", function() Request({ kind = "approve", offer = guid }) end))
            end
        end

        if dealt and not parts.solo and not m_ctx.readonly then
            local others = {}
            if parts.hands ~= nil and parts.hands ~= me then
                others[#others + 1] = parts.hands
            end
            for userid in pairs(parts.readers or {}) do
                if userid ~= me then
                    others[#others + 1] = userid
                end
            end
            table.sort(others)
            local options = {}
            for _, userid in ipairs(others) do
                options[#options + 1] = { id = userid, text = Puzzle.UserName(userid) }
            end
            if #options > 0 then
                local verb = cond(role == "hands", "Pass the hands to...", "Swap parts with...")
                local controls = {
                    gui.Dropdown{
                        width = 200, hmargin = 3,
                        options = options,
                        textDefault = verb,
                        change = function(dropdown)
                            ---@cast dropdown Dropdown
                            Request({ kind = "offer", offerKind = cond(role == "hands", "pass", "swap"), to = dropdown.idChosen })
                        end,
                    },
                }
                if role == "reader" and parts.hands ~= nil then
                    controls[#controls + 1] = Small("Take the hands", function()
                        Request({ kind = "offer", offerKind = "take", to = parts.hands })
                    end)
                end
                rows[#rows + 1] = gui.Panel{ flow = "horizontal", width = "auto", height = "auto", vmargin = 2, children = controls }
            end
        end

        --the referee: who holds what, make anyone the hands, deal again.
        if IsDMOrPlayerHost() and not m_ctx.readonly then
            local players = {}
            local seen = {}
            if parts.hands ~= nil then
                players[#players + 1] = parts.hands
                seen[parts.hands] = true
            end
            for userid in pairs(parts.readers or {}) do
                if not seen[userid] then
                    players[#players + 1] = userid
                    seen[userid] = true
                end
            end
            for _, userid in ipairs(PlayersAtSeal(m_ctx.id)) do
                if not seen[userid] then
                    players[#players + 1] = userid
                    seen[userid] = true
                end
            end
            rows[#rows + 1] = Label("Parts", {"sizeS", "bold"}, { tmargin = 4 })
            for _, userid in ipairs(players) do
                local uid = userid
                local held
                if parts.hands == uid then
                    held = "the hands"
                elseif (parts.readers or {})[uid] ~= nil then
                    local titles = {}
                    for _, key in ipairs(PagesOf(parts, uid)) do
                        titles[#titles + 1] = PageTitle(state.ward, key)
                    end
                    held = table.concat(titles, ", ")
                else
                    held = "watching"
                end
                rows[#rows + 1] = Buttons(
                    Label(string.format("%s: %s", Puzzle.UserName(uid), held), {"sizeS"}, { width = 280, valign = "center" }),
                    parts.hands ~= uid and Small("Make the hands", function() Request({ kind = "makehands", target = uid }) end) or nil)
            end
            rows[#rows + 1] = Buttons(Small("Deal again", function() Request({ kind = "redeal" }) end))
        end
        return rows
    end

    local function Playing()
        local state = State()
        local role, pages = RoleOf(state, m_ctx.userid, m_ctx.isDirector)
        local canAct = (role == "hands" or role == "solo") and not m_ctx.readonly
        local children = {}
        local card
        if role == "hands" then
            card = "You are the hands. Only you can see the ward and act. Describe it; the others hold the rules."
        elseif role == "solo" then
            card = "You alone hold the ward and its codex."
        elseif role == "reader" then
            local titles = {}
            for k, key in ipairs(pages) do
                local page = PageFor(state.ward, key)
                titles[k] = page ~= nil and page.title or key
            end
            card = string.format("You hold the %s page%s. Ask the hands about what they see.", table.concat(titles, " and "), #pages > 1 and "s" or "")
        elseif role == "director" then
            card = "Director's view: you see the ward and every page. The players hold the parts."
        else
            card = "You are watching. The players hold the parts."
        end
        children[#children + 1] = Label(card, {"sizeM", "bold"})
        if state.away and state.parts ~= nil then
            children[#children + 1] = Label(string.format("%s, the hands, is away. If they are gone for a minute, a reader takes the hands.",
                Puzzle.UserName(state.parts.hands)), {"sizeS", "warning"})
        end
        for _, row in ipairs(PartsRows(role)) do
            children[#children + 1] = row
        end
        children[#children + 1] = ModuleList()
        m_targets = {}
        if not canAct then
            m_pending = nil
        end
        if role == "hands" or role == "solo" or role == "director" then
            children[#children + 1] = WardView(canAct)
        end
        for _, row in ipairs(TestRows(role, canAct)) do
            children[#children + 1] = row
        end
        local show = pages
        if role == "solo" or role == "director" then
            show = PageKeys(state.ward)
        end
        for _, key in ipairs(show) do
            local page = PageView(key)
            if page ~= nil then
                children[#children + 1] = page
            end
        end
        local log = LogText()
        if log ~= "" then
            children[#children + 1] = Label(log, {"sizeS"}, { tmargin = 8 })
        end
        return children
    end

    --The party chat: the last few lines, newest at the bottom.
    ---@return string
    local function ChatText()
        local lines = {}
        for _, line in pairs(State().chat or {}) do
            if type(line) == "table" then
                lines[#lines + 1] = line
            end
        end
        table.sort(lines, function(a, b) return (tonumber(a.seq) or 0) < (tonumber(b.seq) or 0) end)
        local out = {}
        for k = math.max(1, #lines - CHAT_SHOW + 1), #lines do
            local line = lines[k]
            local who = Puzzle.UserName(line.user)
            local text = tostring(line.text)
            if line.style == "quote" then
                out[#out + 1] = string.format("%s sees: %s", who, text)
            elseif line.style == "ask" then
                out[#out + 1] = string.format("%s asks: %s", who, text)
            elseif line.style == "point" then
                out[#out + 1] = string.format("<b>%s points: %s.</b>", who, text)
            else
                out[#out + 1] = string.format("%s: %s", who, text)
            end
        end
        return table.concat(out, "\n")
    end

    local function RefreshChat()
        local text = ChatText()
        local children = { Label("Party chat", {"sizeS", "bold"}) }
        if text == "" then
            children[#children + 1] = Label("Nothing said yet.", {"sizeS", "fgMuted"})
        else
            children[#children + 1] = Label(text, {"sizeS"})
        end
        children[#children + 1] = chatInputRow
        chatInputRow:SetClass("collapsed", m_ctx.readonly == true)
        chatPanel.children = children
    end

    Refresh = function()
        if not resultPanel.valid then
            return
        end
        C = WardColours()
        if State().phase == "playing" and State().ward ~= nil then
            body.children = Playing()
        else
            m_targets = {}
            body.children = Gathering()
        end
        RefreshChat()
    end

    body = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        vscroll = true,
        maxHeight = 640,
    }

    local chatInput = gui.Input{
        classes = {"sizeS"},
        width = 420,
        height = 26,
        placeholderText = "Say something to the party...",
        submit = function(element)
            local text = element.text
            element.text = ""
            if text ~= nil and text ~= "" then
                Post("say", text)
            end
        end,
    }
    chatInputRow = gui.Panel{
        flow = "horizontal", width = "auto", height = "auto", tmargin = 2,
        chatInput,
        gui.Button{ classes = {"sizeS"}, text = "Send", width = 70, height = 26, hmargin = 4, valign = "center",
            click = function()
                local text = chatInput.text
                chatInput.text = ""
                if text ~= nil and text ~= "" then
                    Post("say", text)
                end
            end },
    }
    chatPanel = gui.Panel{
        flow = "vertical", width = "auto", height = "auto", tmargin = 8,
        chatInputRow,
    }

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        --the frame re-sends this every half second while a timer runs; rebuilding each
        --time would close an open dropdown, so only rebuild when what is drawn changed.
        refreshPuzzle = function(element, newCtx)
            m_ctx = newCtx
            local tok = Puzzle.MyHero()
            local sig = table.concat({
                json(m_ctx.state or {}), json(Puzzle.ReadKept(m_ctx.id)), json(m_ctx.config or {}),
                tostring(m_ctx.readonly), tostring(Puzzle.TimeLeft(m_ctx.id) ~= nil), tok ~= nil and tok.charid or "",
                tostring(m_ctx:Assist("confirm")), tostring(m_ctx:Assist("large")), tostring(m_ctx:Assist("text")),
                tostring(IsDMOrPlayerHost()), tostring(WardColours().thick), tostring(ArtScale()),
            }, "|")
            if sig ~= m_signature then
                m_signature = sig
                Refresh()
            end
        end,
        destroy = function(element)
            if m_contextActive then
                m_contextActive = false
                dmhub.PopCommandContext(COMMAND_CONTEXT)
            end
        end,
        commands = KEY_COMMANDS,
        seal_up = function(element) MoveCursor(-1) end,
        seal_down = function(element) MoveCursor(1) end,
        seal_left = function(element)
            local t = m_targets[m_cursor]
            if t ~= nil and t.dial then
                TurnDial(t.i, -1)
            end
        end,
        seal_right = function(element)
            local t = m_targets[m_cursor]
            if t ~= nil and t.dial then
                TurnDial(t.i, 1)
            end
        end,
        seal_act = function(element) Activate() end,
        seal_act2 = function(element) Activate() end,
        seal_act3 = function(element) Activate() end,
        seal_quote = function(element)
            local t = m_targets[m_cursor]
            if t ~= nil then
                Post("quote", t.words)
            end
        end,
        seal_cancel = function(element)
            if m_pending ~= nil then
                m_pending = nil
                Refresh()
            end
        end,
        --keys follow the focus (checked often); the gathering list follows presence,
        --which changes without a board write (checked every 2 s).
        thinkTime = 0.2,
        think = function(element)
            SyncContext()
            m_thinks = m_thinks + 1
            if m_thinks % 10 ~= 0 then
                return
            end
            if State().phase ~= "playing" then
                --tell the host which part this player would rather have.
                local pref = g_partPreference:Get()
                local prefs = State().prefs or {}
                if not m_ctx.isDirector and prefs[m_ctx.userid] ~= pref then
                    local uid = m_ctx.userid
                    m_ctx:Change(function(st)
                        st.prefs = st.prefs or {}
                        st.prefs[uid] = pref
                    end, "Part preference")
                end
                local key = table.concat(PlayersAtSeal(m_ctx.id), ",")
                if key ~= m_gatherKey then
                    m_gatherKey = key
                    Refresh()
                end
            end
        end,
        body,
        chatPanel,
    }
    return resultPanel
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

---@param config table
---@return boolean
local function IsCustom(config)
    return config.preset == "custom"
end

---@param config table
---@return boolean
local function HasTests(config)
    return config.brace ~= false or config.study ~= false
end

PuzzleType.Register{
    id = "wardedseal",
    name = "Warded seal",
    howToPlay = [[
One player is the hands: only they can see the ward and act on it. Everyone else reads: each reader holds pages of the ward's codex, the rules for opening it, but can't see the ward. Talk to each other.

Before you start, choose Be the hands, Read or Either part. Anyone can press Begin, and the parts are dealt then. If you begin alone, you see the ward and the codex both.

Hands: describe what you see. A ward has up to four modules: threads to cut, glyphs to touch in the right order, and a sigil dial to turn and set. Click a part's name to quote it in the party chat.

Readers: find the rules on your pages that fit what the hands describe, and tell them what to do. On each page, the first rule that fits is the one that counts. Some rules need a Lexicon page, which another reader may hold. Ask puts a question from your page to the hands; Point tells them an action.

Every wrong action is a strike. Too many strikes and the seal bursts.

Tests: the hands can Brace (Agility) once, so their next slip doesn't count. Each reader can Study (Reason) once to see through rules on their pages. If the ward is timed, anyone can ask for more time.]],
    fields = {
        { id = "preset", type = "choice", label = "Seal", default = "vault", options = {
            { id = "simple", text = "Simple ward (1-2 modules, plain rules)" },
            { id = "vault", text = "Warded vault (3 modules, some conditions)" },
            { id = "archmage", text = "Archmage's seal (4 modules, chained rules, 2 strikes)" },
            { id = "custom", text = "Customize" },
        } },
        { id = "modules", type = "number", label = "Modules", default = 3, min = 1, max = 4, visible = IsCustom },
        { id = "kinds", type = "choice", label = "Module kinds", default = "mixed", visible = IsCustom, options = {
            { id = "mixed", text = "Mixed" },
            { id = "threads", text = "Threads only" },
            { id = "glyphs", text = "Glyphs only" },
            { id = "dial", text = "Sigil dials only" },
        } },
        { id = "depth", type = "choice", label = "Rules", default = "conditional", visible = IsCustom, options = {
            { id = "plain", text = "Plain" },
            { id = "conditional", text = "Some conditions" },
            { id = "chained", text = "Chained (uses the Lexicon)" },
        } },
        { id = "strikes", type = "number", label = "Strikes before it bursts", default = 3, min = 1, max = 5, visible = IsCustom },
        { id = "brace", type = "toggle", label = "Brace test for the hands (Agility, Sabotage)", default = true },
        { id = "study", type = "toggle", label = "Study the ward test for readers (Reason, Magic)", default = true },
        { id = "testDifficulty", type = "choice", label = "Test difficulty", default = "medium", visible = HasTests, options = {
            { id = "easy", text = "Easy" },
            { id = "medium", text = "Medium" },
            { id = "hard", text = "Hard" },
        } },
        { id = "hint", type = "text", label = "Hint", default = "" },
    },
    assists = {
        { id = "confirm", label = "Confirm each action" },
        { id = "large", label = "Larger ward" },
        { id = "text", label = "Larger text" },
    },
    --changing what the ward is made of makes a new ward.
    ConfigKey = function(config)
        local eff = Effective(config)
        return string.format("%s|%d|%s|%d|%s", tostring(config.preset), eff.count, eff.depth, eff.strikes, eff.kinds)
    end,
    NewState = function(config, ctx)
        return { phase = "gathering", act = {}, strikes = 0, log = {} }
    end,
    IsSolved = function(state, config)
        if state.phase ~= "playing" or type(state.ward) ~= "table" then
            return false
        end
        for i in ipairs(state.ward.modules) do
            if not ModuleDone(state, i) then
                return false
            end
        end
        return true
    end,
    IsFailed = function(state, config, now)
        return state.phase == "playing" and (state.strikes or 0) >= Effective(config).strikes
    end,
    Hint = function(state, config)
        local hint = tostring(config.hint or "")
        if hint == "" then
            return nil
        end
        return hint
    end,
    Status = function(state, config)
        if state.phase ~= "playing" then
            return nil
        end
        return string.format("Strikes: %d of %d", state.strikes or 0, Effective(config).strikes)
    end,
    HostTick = HostTick,
    Render = Render,
}
