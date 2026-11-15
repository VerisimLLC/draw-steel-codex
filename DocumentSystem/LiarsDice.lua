local mod = dmhub.GetModLoading()

-- Liar's dice (liars-dice-brief.md): a hero, the champion, plays against one to three NPC
-- gamblers. Five d6 each under a cup, ones wild; bid "N dice show face F" across the table;
-- the next player raises or calls Liar; the loser of a challenge loses a die. Only the
-- champion's challenges are rounds (C1). Played through the games-of-chance "turns" flow
-- (GameOfChanceTurns.lua); the bidding and counting are LiarsDiceBidder.lua.
--
-- Public game data (state.g), every client sees it:
--   seats    = { s1 = champion {user, tokenid, name, dice}, s2.. = gambler {cast, name, honesty, dice} }
--   champHand= the champion's dice, shown to the whole party (#6)
--   commits  = { s2 = hash of salt + hand } for each hidden hand (#15)
--   turn, bid = {q, f, by}, hist = { h<seq> = {seq, text} }, nextAt, thinking
--   reveal   = the last challenge, cups up: hands, salt, count, text
-- Host secret (GameOfChanceTurns): { challenge, salt, hands = { s2 = "2,5,5,1,6" } }.

local B = LiarsDiceBidder
local S = GameOfChance.Shared

local DICE = 5
local MAX_SEATS = 4
local HIST_KEEP = 12
local HIST_SHOW = 6
--seconds a gambler "thinks", and the pause after a challenge between gamblers.
local THINK_MIN, THINK_MAX = 1.1, 2.5
local NPC_REVEAL_PAUSE = 3
--the champion's turn left alone this long: the others may take over the seat (C13).
local IDLE_SECONDS = 60

--------------------------------------------------------------------------------
-- The cast (C12): gamblers presets and the Director pick from
--------------------------------------------------------------------------------

local CAST = {
    { id = "grisk", name = "Grisk", honesty = "honest" },
    { id = "mara", name = "Mara", honesty = "honest" },
    { id = "vell", name = "Vell", honesty = "shady" },
    { id = "tobin", name = "Tobin", honesty = "shady" },
    { id = "sable", name = "Sable", honesty = "crooked" },
    { id = "ruk", name = "Old Ruk", honesty = "crooked" },
}

local CAST_BY_ID = {}
for _, c in ipairs(CAST) do
    CAST_BY_ID[c.id] = c
end

local THINK_LINES = {
    honest = { "%s counts the dice on the table.", "%s turns the cup in their hands.", "%s frowns at the bid." },
    shady = { "%s grins and taps the cup.", "%s glances around the table.", "%s hums a little tune." },
    crooked = { "%s's hand drifts toward their sleeve.", "%s smiles too widely.", "%s rattles the cup, just once." },
}

local CALL_LINES = {
    honest = "Liar! Let's see them.",
    shady = "Liar! I don't buy it.",
    crooked = "Liar, friend. Lift your cup.",
}

local CAUGHT_LINES = {
    honest = "Hah. Fair's fair.",
    shady = "Now, now, no need to shout.",
    crooked = "...You saw that, did you?",
}

--Seconds an open test roll holds the champion's next move (C3), and how long
--a forgotten one may hold it (shell #35).
local ROLL_HOLD_SECONDS = 60
local NOTES_KEEP = 8

local CAST_OPTIONS = {}
for _, c in ipairs(CAST) do
    CAST_OPTIONS[#CAST_OPTIONS + 1] = { id = c.id, text = string.format("%s (%s)", c.name, c.honesty) }
end

local PRESETS = {
    tavern = { difficulty = "easy", tests = true, stake = "none", stakeGold = 0, wins = 2, losses = 2, onLoss = "again",
        gamblers = 2, seat2 = "grisk", seat3 = "mara" },
    rigged = { difficulty = "medium", tests = true, stake = "gold", stakeGold = 10, wins = 2, losses = 2, onLoss = "again",
        gamblers = 2, seat2 = "vell", seat3 = "mara" },
    carnival = { difficulty = "hard", tests = true, stake = "recovery", stakeGold = 0, wins = 2, losses = 2, onLoss = "fail",
        gamblers = 2, seat2 = "sable", seat3 = "tobin" },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

---@param g table
---@param i integer
---@return table|nil
local function Seat(g, i)
    return (g.seats or {})["s" .. i]
end

--A seat the caller knows is taken (the one whose turn it is, a challenge's players).
---@param g table
---@param i integer
---@return table
local function TakenSeat(g, i)
    return Seat(g, i) or { name = "?", dice = 0, honesty = "honest" }
end

---@param g table
---@return integer
local function SeatCount(g)
    local n = 0
    for i = 1, MAX_SEATS do
        if Seat(g, i) ~= nil then
            n = i
        end
    end
    return n
end

---@param g table
---@param i integer
---@return boolean
local function Alive(g, i)
    local seat = Seat(g, i)
    return seat ~= nil and (tonumber(seat.dice) or 0) > 0
end

--The next seat after i that still has dice.
---@param g table
---@param i integer
---@return integer
local function NextAlive(g, i)
    local n = SeatCount(g)
    for step = 1, n do
        local j = (i - 1 + step) % n + 1
        if Alive(g, j) then
            return j
        end
    end
    return i
end

---@param g table
---@return integer
local function TotalDice(g)
    local total = 0
    for i = 1, SeatCount(g) do
        total = total + (tonumber((Seat(g, i) or {}).dice) or 0)
    end
    return total
end

---@param q integer
---@param f integer
---@return string
local function BidText(q, f)
    return string.format("%d x %d", q, f)
end

---@param g table
---@param i integer
---@return string
local function SeatName(g, i)
    local seat = Seat(g, i)
    return seat ~= nil and tostring(seat.name) or "?"
end

---@param g table
---@param text string
local function AddHist(g, text)
    g.hist = g.hist or {}
    g.histSeq = (tonumber(g.histSeq) or 0) + 1
    local seq = g.histSeq
    g.hist["h" .. seq] = { seq = seq, text = text }
    for k, line in pairs(g.hist) do
        if type(line) ~= "table" or (tonumber(line.seq) or 0) <= seq - HIST_KEEP then
            g.hist[k] = nil
        end
    end
end

--A gambler's think time at the table's pace (g.pace, set by the host each step).
---@param random fun(k: integer): integer
---@param g table
---@return number
local function ThinkTime(random, g)
    local pace = tonumber(g.pace) or 1
    return (THINK_MIN + (random(15) - 1) / 14 * (THINK_MAX - THINK_MIN)) * pace
end

---@param random fun(k: integer): integer
---@param n integer
---@return integer[]
local function Roll(random, n)
    local hand = {}
    for i = 1, n do
        hand[i] = random(6)
    end
    return hand
end

---@param g table
---@param secret table
---@return integer[][] every hand in seat order (empty for seats out of the game)
local function AllHands(g, secret)
    local hands = {}
    for i = 1, SeatCount(g) do
        if i == 1 then
            hands[i] = B.ParseHand(g.champHand)
        else
            hands[i] = B.ParseHand((secret.hands or {})["s" .. i])
        end
        if not Alive(g, i) then
            hands[i] = {}
        end
    end
    return hands
end

--------------------------------------------------------------------------------
-- The host: shaking, turns, challenges
--------------------------------------------------------------------------------

--Everyone shakes: new hands, the commitments, and the opener's turn.
---@param g table
---@param random fun(k: integer): integer
---@param secret table
local function Shake(g, random, secret)
    secret.challenge = g.challenge
    secret.salt = dmhub.GenerateGuid()
    secret.hands = {}
    g.commits = {}
    for i = 1, SeatCount(g) do
        if Alive(g, i) then
            local hand = B.HandText(Roll(random, tonumber(TakenSeat(g, i).dice) or 0))
            if i == 1 then
                g.champHand = hand
            else
                secret.hands["s" .. i] = hand
                g.commits["s" .. i] = B.Commit(secret.salt, hand)
            end
        end
    end
    g.bid = nil
    g.hist = {}
    g.reveal = nil
    g.pendingShakeAt = nil
    --what tests told the table about this challenge's cups.
    g.reads = {}
    g.sells = {}
    g.sell = nil
    g.known = {}
    g.suggest = {}
    g.turn = Alive(g, tonumber(g.opener) or 1) and (tonumber(g.opener) or 1) or NextAlive(g, tonumber(g.opener) or 1)
    g.thinking = nil
    g.nextAt = nil
    if g.turn ~= 1 then
        g.nextAt = dmhub.serverTime + ThinkTime(random, g)
    else
        g.turnAt = dmhub.serverTime
    end
end

---@param g table
---@param random fun(k: integer): integer
local function PassTurn(g, random)
    g.turn = NextAlive(g, tonumber(g.turn) or 1)
    g.thinking = nil
    g.nextAt = nil
    if g.turn == 1 then
        g.turnAt = dmhub.serverTime
    else
        g.nextAt = dmhub.serverTime + ThinkTime(random, g)
        local seat = TakenSeat(g, g.turn)
        local lines = THINK_LINES[seat.honesty] or THINK_LINES.honest
        g.thinking = string.format(lines[random(#lines)], seat.name)
    end
end

--Lift the cups on the bid on the table: count, the loser drops a die, and report.
---@param g table
---@param secret table
---@param caller integer
---@param random fun(k: integer): integer
---@param events ChanceTurnsEvent[]
local function Resolve(g, secret, caller, random, events)
    local bid = g.bid
    local bidder = tonumber(bid.by) or 1
    local hands = AllHands(g, secret)
    --loaded dice (#9, C6): decided now, and only for a crooked gambler's own short bid.
    local loadedSeat, loadedIdx, original = nil, nil, nil
    if bidder ~= 1 and TakenSeat(g, bidder).honesty == "crooked" then
        local before = hands[bidder]
        local after, loaded = B.Load(hands, bidder, bid)
        if loaded > 0 then
            hands[bidder] = after
            loadedSeat = "s" .. bidder
            original = B.HandText(before)
            local idx = {}
            for k, d in ipairs(after) do
                if d ~= before[k] then
                    idx[#idx + 1] = tostring(k)
                end
            end
            loadedIdx = table.concat(idx, ",")
        end
    end
    local count = B.Count(hands, bid.f)
    local loser = count >= bid.q and caller or bidder
    local seat = TakenSeat(g, loser)
    seat.dice = math.max(0, (tonumber(seat.dice) or 0) - 1)

    local revealed = {}
    for i = 1, #hands do
        revealed["s" .. i] = B.HandText(hands[i])
    end
    local text = string.format("%s called Liar on %s's %s. There were %d (ones count). %s loses a die.",
        SeatName(g, caller), SeatName(g, bidder), BidText(bid.q, bid.f), count, SeatName(g, loser))
    if loadedSeat ~= nil then
        text = text .. string.format(" %s's dice were loaded!", SeatName(g, bidder))
    end
    --a strong read reports belief, not the dice (C17): say so when belief fell short.
    if count < bid.q then
        for _, read in pairs(g.reads or {}) do
            if type(read) == "table" and tonumber(read.target) == bidder and read.believed == true then
                text = text .. string.format(" %s believed it, but the dice fell short.", SeatName(g, bidder))
                break
            end
        end
    end
    g.reveal = { hands = revealed, salt = secret.salt, count = count, q = bid.q, f = bid.f, caller = caller, bidder = bidder, loser = loser, text = text,
        loaded = loadedSeat, loadedIdx = loadedIdx, original = original }
    AddHist(g, text)
    g.opener = loser
    g.turn = nil
    g.nextAt = nil
    g.thinking = nil

    local champ = caller == 1 or bidder == 1
    local gamblersLeft = false
    for i = 2, SeatCount(g) do
        if Alive(g, i) then
            gamblersLeft = true
        end
    end
    if champ then
        local champSeat = TakenSeat(g, 1)
        local result = loser == 1 and "lose" or "win"
        events[#events + 1] = {
            log = text,
            round = result,
            final = (not gamblersLeft) or not Alive(g, 1),
            bettor = { user = champSeat.user, tokenid = champSeat.tokenid },
        }
    elseif not gamblersLeft then
        local champSeat = TakenSeat(g, 1)
        events[#events + 1] = { log = text, round = "win", final = true, bettor = { user = champSeat.user, tokenid = champSeat.tokenid } }
    else
        --gamblers among themselves: a die, a log line, and the cups go round again (C1).
        events[#events + 1] = { log = text }
        g.pendingShakeAt = dmhub.serverTime + NPC_REVEAL_PAUSE * math.max(0.5, tonumber(g.pace) or 1)
    end
end

--A private test result. Most describe this challenge's cups and are hidden after the
--next shake; a game-long one (Watch the table) stays.
---@param g table
---@param userid string
---@param text string
---@param gameLong boolean|nil
local function Note(g, userid, text, gameLong)
    g.notes = g.notes or {}
    local mine = g.notes[userid] or {}
    g.notes[userid] = mine
    g.noteSeq = (tonumber(g.noteSeq) or 0) + 1
    mine["n" .. g.noteSeq] = { seq = g.noteSeq, text = text, challenge = gameLong and 0 or g.challenge }
    for k, n in pairs(mine) do
        if type(n) ~= "table" or (tonumber(n.seq) or 0) <= g.noteSeq - NOTES_KEEP then
            mine[k] = nil
        end
    end
end

---@param g table
---@return boolean
local function RollingOpen(g)
    for _, at in pairs(g.rolling or {}) do
        if type(at) == "number" and dmhub.serverTime - at <= ROLL_HOLD_SECONDS then
            return true
        end
    end
    return false
end

---@param tokenid string|nil
---@param userid string
---@return string
local function HeroName(tokenid, userid)
    local tok = tokenid ~= nil and Puzzle.HeroById(tokenid) or nil
    if tok ~= nil and tok.name ~= nil and tok.name ~= "" then
        return tok.name
    end
    return Puzzle.UserName(userid)
end

--The gamblers who cheat (crooked seats still in the game).
---@param g table
---@return integer[]
local function CrookedSeats(g)
    local out = {}
    for i = 2, SeatCount(g) do
        if Alive(g, i) and TakenSeat(g, i).honesty == "crooked" then
            out[#out + 1] = i
        end
    end
    return out
end

--A party member's test result, judged by the host (#4, #12, #13, C2-C6). Results are
--private notes; what changes at the table is public.
---@param g table
---@param eff table
---@param secret table
---@param req table
---@param userid string
---@param random fun(k: integer): integer
---@return boolean
local function Test(g, eff, secret, req, userid, random)
    (g.rolling or {})[userid] = nil
    if eff.tests ~= true then
        return true
    end
    local tier = math.max(1, math.min(3, math.tointeger(tonumber(req.tier)) or 1))
    local natural = tonumber(req.natural)
    local outcome = S.Outcome(tier, natural, tostring(eff.difficulty or "medium"))
    local ok = outcome == "success" or outcome == "consequence"
    local noticed = outcome == "consequence" or outcome == "failconsequence"
    local champ = Seat(g, 1)
    local isChamp = champ ~= nil and champ.user == userid
    local who = HeroName(req.tokenid, userid)
    local total = TotalDice(g)
    local test = req.test

    if test == "read" then
        local bid = g.bid
        g.reads = g.reads or {}
        if isChamp or bid == nil or tonumber(bid.by) == 1 or tonumber(g.turn) ~= 1 or g.reads[userid] ~= nil then
            return true
        end
        local target = tonumber(bid.by) or 2
        local seat = TakenSeat(g, target)
        local hand = B.ParseHand((secret.hands or {})["s" .. target])
        local believed = B.Expect(hand, total, bid.f) >= bid.q - 0.5
        g.reads[userid] = { target = target, believed = ok and believed or nil }
        local text
        if ok then
            text = believed and string.format("%s believes that bid.", seat.name) or string.format("%s is bluffing.", seat.name)
            if seat.honesty == "crooked" then
                text = text .. " ...Unless they have something up their sleeve."
            end
        else
            text = string.format("%s gives nothing away.", seat.name)
        end
        if noticed then
            g.clammed = g.clammed or {}
            g.clammed["s" .. target] = true
            text = text .. string.format(" %s caught you staring and clams up.", seat.name)
            AddHist(g, string.format("%s notices %s staring.", seat.name, who))
        end
        Note(g, userid, "Read the bid: " .. text)
    elseif test == "sell" then
        g.sells = g.sells or {}
        if tonumber(g.turn) ~= 1 or g.sells[userid] ~= nil then
            return true
        end
        g.sells[userid] = tier
        g.sell = g.sell or { trust = 0, wary = 0 }
        local amount = ok and (tier >= 3 and 2 or 1) or 0
        g.sell.trust = math.max(tonumber(g.sell.trust) or 0, amount)
        if noticed then
            g.sell.wary = 0.5
        end
        AddHist(g, string.format("%s talks up the champion.", who))
        local text
        if amount >= 2 then
            text = "The table hangs on your words: the next gambler gives the champion's bid a lot of credit."
        elseif amount == 1 then
            text = "They lean in to listen: the next gambler gives the champion's bid some credit."
        else
            text = "Nobody's buying it."
        end
        if noticed then
            text = text .. " The gamblers grow wary of the champion."
        end
        Note(g, userid, "Sell the bluff: " .. text)
    elseif test == "peek" then
        g.peeked = g.peeked or {}
        g.guarded = g.guarded or {}
        local target = math.tointeger(tonumber(req.seat))
        if isChamp or g.peeked[userid] ~= nil or target == nil or target < 2 or not Alive(g, target) or g.guarded["s" .. target] then
            return true
        end
        g.peeked[userid] = true
        local seat = TakenSeat(g, target)
        local text
        if ok then
            local hand = B.ParseHand((secret.hands or {})["s" .. target])
            g.known = g.known or {}
            local knownList = B.ParseHand(g.known["s" .. target])
            if #knownList < #hand then
                local face = hand[#knownList + 1]
                knownList[#knownList + 1] = face
                g.known["s" .. target] = B.HandText(knownList)
                text = string.format("You glimpse one of %s's dice: a %d. The party can see it on the table.", seat.name, face)
            else
                text = string.format("You've seen all of %s's dice already.", seat.name)
            end
        else
            text = string.format("You couldn't get a look under %s's cup.", seat.name)
        end
        if noticed then
            --goodwill, never a die (C4): the cup is guarded and they call the champion sooner.
            g.guarded["s" .. target] = true
            g.wary = g.wary or {}
            g.wary["s" .. target] = 0.5
            text = text .. string.format(" %s caught you.", seat.name)
            AddHist(g, string.format("%s caught %s peeking.", seat.name, who))
        end
        Note(g, userid, "Peek at a die: " .. text)
    elseif test == "watch" then
        g.watched = g.watched or {}
        if g.watched[userid] ~= nil then
            return true
        end
        g.watched[userid] = tier
        local crooked = CrookedSeats(g)
        local names = {}
        for k, i in ipairs(crooked) do
            names[k] = TakenSeat(g, i).name
        end
        local text
        --the plain tiers, not the difficulty row (shell #45).
        if tier >= 3 then
            if #crooked > 0 then
                g.caught = g.caught or {}
                for _, i in ipairs(crooked) do
                    g.caught["s" .. i] = true
                end
                text = string.format("%s %s loading dice! The champion can call it out.", table.concat(names, " and "), #names > 1 and "are" or "is")
            else
                text = "Clean table: nobody here is cheating."
            end
        elseif tier == 2 then
            text = "Something's off at this table."
        else
            text = "You didn't see anything odd."
        end
        --the rules' Notice the Cheaters top tier: win without any other test (C6).
        if natural ~= nil and natural >= 19 and #crooked > 0 then
            g.claim = true
            text = text .. " You know exactly how they cheat: the champion may claim the game."
        end
        Note(g, userid, "Watch the table: " .. text, true)
    end
    return true
end

---@param g table
---@return string
local function StartLabel(g)
    if Seat(g, 1) == nil then
        return "Take a seat"
    end
    return "Shake the dice"
end

local function NewGame(eff, random)
    local g = { seats = {}, challenge = 0, opener = 1, hist = {}, histSeq = 0 }
    local n = math.max(1, math.min(3, math.tointeger(tonumber(eff.gamblers)) or 2))
    for i = 1, n do
        local c = CAST_BY_ID[tostring(eff["seat" .. (i + 1)] or "")] or CAST[i]
        local honesty = c.honesty
        --a crooked gambler can never be caught without tests: they play shady (shell #34).
        if honesty == "crooked" and eff.tests ~= true then
            honesty = "shady"
        end
        g.seats["s" .. (i + 1)] = { cast = c.id, name = c.name, honesty = honesty, dice = DICE }
    end
    return g
end

--------------------------------------------------------------------------------
-- The board
--------------------------------------------------------------------------------

local COMMAND_CONTEXT = "liarsdice"
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
    Bind("up", "ld_up")
    Bind("down", "ld_down")
    for f = 2, 6 do
        Bind(tostring(f), "ld_f" .. f)
    end
    Bind("return", "ld_bid")
    Bind("enter", "ld_bid2")
    Bind("l", "ld_liar")
    Bind("s", "ld_suggest")
end

local g_oddsSetting = setting{
    id = "liarsdice:odds",
    storage = "account",
    default = true,
}

local DIE_COLOR = "#f1ecdfff"
local DIE_HIDDEN = "#4a3b2cff"
local MATCH_BORDER = "#56b4e9ff"
local TURN_BORDER = "#f2c96bff"

--Under a high-contrast scheme: white dice on black, stark borders.
---@return boolean
local function HighContrast()
    local high = false
    pcall(function() high = ThemeEngine.GetAccessibility().highContrast == true end)
    return high
end

local FACE_NAMES = { "one", "two", "three", "four", "five", "six" }

local VERDICT_WORDS = {
    sure = "certain: you can see them all",
    expected = "about what to expect",
    stretch = "a stretch",
    longshot = "a long shot",
}

local function Board()
    EnsureBindings()
    --set by the first "chanceTurns" event, before anything below draws.
    local m_view ---@type ChanceTurnsView
    local m_signature = nil
    local m_q, m_f = 1, 2
    local m_bidKey = nil
    local m_contextActive = false
    local m_lastBidAt = -1
    local resultPanel

    local function Large()
        return m_view ~= nil and m_view.large == true
    end

    local function Px(n)
        return math.floor(n * (Large() and 1.4 or 1))
    end

    --Items laid out in lines of perLine: a wrapping panel does not grow its own height,
    --so its second line would overlap whatever comes next.
    ---@param items Panel[]
    ---@param perLine integer
    ---@param tmargin number|nil
    ---@return Panel
    local function Lines(items, perLine, tmargin)
        local lines = {}
        for i = 1, #items, perLine do
            local line = {}
            for k = i, math.min(#items, i + perLine - 1) do
                line[#line + 1] = items[k]
            end
            lines[#lines + 1] = gui.Panel{ flow = "horizontal", width = "auto", height = "auto", children = line }
        end
        return gui.Panel{ flow = "vertical", width = "auto", height = "auto", tmargin = tmargin or 0, children = lines }
    end

    local function Label(text, classes, extra)
        local args = { classes = classes or {"sizeS"}, width = "auto", maxWidth = Px(700), height = "auto", text = text }
        for k, v in pairs(extra or {}) do
            args[k] = v
        end
        return gui.Label(args)
    end

    --one die: the face's pips with its numeral beside it; marked (outline + "+") when
    --it counts for the bid, never by colour alone (C8, C9).
    local function Die(face, opts)
        opts = opts or {}
        local size = Px(opts.size or 30)
        if opts.hidden then
            return gui.Panel{
                width = size, height = size, hmargin = 2, valign = "center",
                bgimage = "panels/square.png", bgcolor = HighContrast() and "#000000ff" or DIE_HIDDEN, border = HighContrast() and 2 or 1,
                borderColor = HighContrast() and "#ffffffff" or "#00000088",
                Label("?", {"sizeS", "bold"}, { halign = "center", valign = "center", interactable = false }),
            }
        end
        return gui.Panel{
            flow = "vertical", width = "auto", height = "auto", hmargin = 2, valign = "center",
            gui.Panel{
                width = size + 4, height = size + 4, halign = "center",
                bgimage = "panels/square.png", bgcolor = "#00000000",
                border = opts.match and (HighContrast() and 3 or 2) or 0, borderColor = HighContrast() and "#00e5ffff" or MATCH_BORDER,
                gui.Panel{ width = size, height = size, halign = "center", valign = "center",
                    bgimage = "phosphor/dice-" .. FACE_NAMES[face] .. ".png", bgcolor = HighContrast() and "#ffffffff" or DIE_COLOR, interactable = false },
            },
            Label(tostring(face) .. (opts.match and "+" or ""), {"sizeXs"}, { halign = "center", interactable = false }),
            opts.tag ~= nil and Label(opts.tag, {"sizeXs", "bold"}, { halign = "center", interactable = false }) or nil,
        }
    end

    local function Me()
        return m_view ~= nil and m_view.me or dmhub.userid
    end

    --every die the whole party can see: the champion's hand and any peeked dice.
    local function KnownDice(g)
        local known = B.ParseHand(g.champHand)
        for _, text in pairs(g.known or {}) do
            for _, d in ipairs(B.ParseHand(text)) do
                known[#known + 1] = d
            end
        end
        return known
    end

    local function IsChampion()
        local champ = Seat(m_view.g, 1)
        return champ ~= nil and champ.user == Me()
    end

    local function IsChampionTurn()
        local view = m_view
        if view == nil or view.phase ~= "playing" or view.readonly then
            return false
        end
        local g = view.g
        local champ = Seat(g, 1)
        return champ ~= nil and champ.user == Me() and tonumber(g.turn) == 1 and g.pendingShakeAt == nil
    end

    --keep the champion's chosen bid legal; after a new bid, start from the smallest
    --raise on the face the champion holds most of.
    local function ResetChoice()
        local g = m_view.g
        local hand = B.ParseHand(g.champHand)
        local total = TotalDice(g)
        local best, bestN = nil, -1
        for _, r in ipairs(B.MinRaises(g.bid, total)) do
            local n = B.Matches(hand, r.f)
            if n > bestN then
                best, bestN = r, n
            end
        end
        if best ~= nil then
            m_q, m_f = best.q, best.f
            --an opening bid starts at what the champion can expect, not at 1.
            if g.bid == nil then
                m_q = math.max(1, math.floor(B.Expect(hand, total, best.f)))
            end
        end
    end

    local function Send(args)
        if m_view ~= nil then
            m_view.request(args)
        end
    end

    local function BidNow()
        if not IsChampionTurn() or dmhub.Time() - m_lastBidAt < 0.3 then
            return
        end
        local g = m_view.g
        if not B.Legal(g.bid, m_q, m_f, TotalDice(g)) then
            return
        end
        m_lastBidAt = dmhub.Time()
        Send({ kind = "move", act = "bid", q = m_q, f = m_f })
    end

    local function CallNow()
        if IsChampionTurn() and m_view.g.bid ~= nil then
            Send({ kind = "move", act = "call" })
        end
    end

    local Rebuild

    local function SetChoice(q, f)
        local total = TotalDice(m_view.g)
        m_q = math.max(1, math.min(total, q))
        m_f = math.max(2, math.min(6, f))
        Rebuild(true)
    end

    --The seats: a cup per player with its dice (the champion's shown, the gamblers'
    --hidden until a reveal), the dice count in words, and whose turn it is.
    local function SeatsRow()
        local g = m_view.g
        local reveal = g.reveal
        local bid = g.bid
        local boxes = {}
        for i = 1, SeatCount(g) do
            local seat = Seat(g, i)
            if seat == nil then
                boxes[#boxes + 1] = gui.Panel{
                    flow = "vertical", width = "auto", minWidth = Px(150), height = "auto", hmargin = 4, pad = 6, borderBox = true,
                    bgimage = "panels/square.png", bgcolor = "#00000033", border = 1, borderColor = "#ffffff22",
                    Label("The champion's seat", {"sizeS", "bold"}),
                    Label("Empty. Take a seat to play.", {"sizeS", "fgMuted"}),
                }
                goto continue
            end
            local dice = tonumber(seat.dice) or 0
            local hand
            if reveal ~= nil and reveal.hands ~= nil then
                hand = B.ParseHand(reveal.hands["s" .. i])
            elseif i == 1 then
                hand = B.ParseHand(g.champHand)
            end
            local face = reveal ~= nil and reveal.f or (bid ~= nil and bid.f or nil)
            local dieRow = {}
            local loadedAt = {}
            if reveal ~= nil and reveal.loaded == "s" .. i then
                for k in string.gmatch(tostring(reveal.loadedIdx or ""), "%d+") do
                    loadedAt[tonumber(k)] = true
                end
            end
            if dice == 0 and (hand == nil or #hand == 0) then
                dieRow[1] = Label("Out of dice", {"sizeS", "fgMuted"})
            elseif hand ~= nil and #hand > 0 then
                for k, d in ipairs(hand) do
                    dieRow[#dieRow + 1] = Die(d, { match = face ~= nil and (d == face or d == 1), tag = loadedAt[k] and "loaded" or nil })
                end
            else
                --a peeked die shows for the whole party (C7 builds on it).
                local known = B.ParseHand((g.known or {})["s" .. i])
                for k = 1, dice do
                    if known[k] ~= nil then
                        dieRow[#dieRow + 1] = Die(known[k], { match = face ~= nil and (known[k] == face or known[k] == 1), tag = "peeked" })
                    else
                        dieRow[#dieRow + 1] = Die(1, { hidden = true })
                    end
                end
            end
            local caption = string.format("%d %s", dice, dice == 1 and "die" or "dice")
            if reveal ~= nil and tonumber(reveal.loser) == i then
                caption = string.format("%d %s now (lost one)", dice, dice == 1 and "die" or "dice")
            end
            if hand ~= nil and #hand > 0 and face ~= nil then
                caption = string.format("%s, %d count", caption, B.Matches(hand, face))
            end
            local active = m_view.phase == "playing" and tonumber(g.turn) == i and g.pendingShakeAt == nil
            local title = i == 1 and string.format("%s (champion)", seat.name) or seat.name
            boxes[#boxes + 1] = gui.Panel{
                flow = "vertical", width = "auto", minWidth = Px(150), height = "auto", hmargin = 4, pad = 6, borderBox = true,
                bgimage = "panels/square.png", bgcolor = "#00000033", border = active and 2 or 1,
                borderColor = active and TURN_BORDER or "#ffffff22",
                Label(title .. (active and " -- to play" or ""), {"sizeS", "bold"}),
                gui.Panel{ flow = "horizontal", width = "auto", height = "auto", vmargin = 3, children = dieRow },
                Label(caption, {"sizeXs", "fgMuted"}),
            }
            ::continue::
        end
        if #boxes == 0 then
            boxes[1] = Label("Nobody has taken a seat yet.", {"sizeS", "fgMuted"})
        end
        return Lines(boxes, (Large() and #boxes > 3) and 2 or 4)
    end

    --The bid on the table in numerals first (C9), and what the party can see of it (C7).
    local function BidLines()
        local g = m_view.g
        local rows = {}
        local total = TotalDice(g)
        if g.bid ~= nil then
            rows[#rows + 1] = Label(string.format("Bid: %s by %s", BidText(g.bid.q, g.bid.f), SeatName(g, tonumber(g.bid.by) or 1)), {"sizeL", "bold"})
        end
        rows[#rows + 1] = Label(string.format("%d dice on the table. Ones are wild: they count as any face.", total), {"sizeS"})
        if g.bid ~= nil and g.champHand ~= nil and g_oddsSetting:Get() == true and g.reveal == nil then
            local known = KnownDice(g)
            local verdict = B.Verdict(known, total, g.bid.q, g.bid.f)
            local hidden = total - #known
            local likely = math.floor(hidden / 3 + 0.5)
            rows[#rows + 1] = Label(string.format("%s is %s. The party can see %d; about %d more are likely among the %d hidden dice.",
                BidText(g.bid.q, g.bid.f), VERDICT_WORDS[verdict], B.Matches(known, g.bid.f), likely, hidden), {"sizeS", "info"})
        end
        return rows
    end

    --"Next: 4 x 6, or 5 x any face" -- the smallest legal raises in words.
    local function NextText(bid, total)
        if bid == nil then
            return "Open with any bid, at least 1 x 2."
        end
        local sameFaces = {}
        for f = bid.f + 1, 6 do
            sameFaces[#sameFaces + 1] = f
        end
        local parts = {}
        if #sameFaces == 1 then
            parts[#parts + 1] = BidText(bid.q, sameFaces[1])
        elseif #sameFaces > 1 then
            parts[#parts + 1] = string.format("%d x %d-%d", bid.q, sameFaces[1], sameFaces[#sameFaces])
        end
        if bid.q + 1 <= total then
            parts[#parts + 1] = string.format("%d x any face", bid.q + 1)
        end
        if #parts == 0 then
            return "No raise is possible: call Liar."
        end
        return "Next: " .. table.concat(parts, ", or ")
    end

    --The champion's controls: quantity, face, Bid and Liar, all on keys too (C15).
    --The rest of the party gets the same picker to suggest a bid (C14).
    local function Controls(suggest)
        local g = m_view.g
        local total = TotalDice(g)
        local legal = B.Legal(g.bid, m_q, m_f, total)
        local faces = {}
        for f = 2, 6 do
            local face = f
            faces[#faces + 1] = gui.Panel{
                width = "auto", height = "auto", hmargin = 1,
                bgimage = "panels/square.png", bgcolor = "#00000000",
                border = m_f == face and 2 or 0, borderColor = TURN_BORDER,
                press = function() SetChoice(m_q, face) end,
                Die(face, {}),
            }
        end
        local reason
        if not legal then
            if m_q > total then
                reason = string.format("There are only %d dice on the table.", total)
            else
                reason = "That's no raise: bid more dice, or the same number of a higher face."
            end
        end
        local known = KnownDice(g)
        local verdict = B.Verdict(known, total, m_q, m_f)
        local rows = {
            gui.Panel{
                flow = "horizontal", width = "auto", height = "auto", tmargin = 4,
                Label("Your bid:", {"sizeM"}, { valign = "center", hmargin = 4 }),
                gui.Button{ classes = {"sizeS"}, text = "-", width = Px(30), height = Px(28), valign = "center", click = function() SetChoice(m_q - 1, m_f) end },
                Label(tostring(m_q), {"sizeL", "bold"}, { valign = "center", hmargin = 6, minWidth = Px(28), textAlignment = "center" }),
                gui.Button{ classes = {"sizeS"}, text = "+", width = Px(30), height = Px(28), valign = "center", click = function() SetChoice(m_q + 1, m_f) end },
                Label("x", {"sizeM"}, { valign = "center", hmargin = 6 }),
                gui.Panel{ flow = "horizontal", width = "auto", height = "auto", valign = "center", children = faces },
            },
            suggest and gui.Panel{
                flow = "horizontal", width = "auto", height = "auto", tmargin = 4,
                gui.Button{ classes = {"sizeS"}, text = string.format("Suggest %s", BidText(m_q, m_f)), width = Px(160), height = Px(28),
                    click = function()
                        local tok = Puzzle.MyHero()
                        Send({ kind = "move", act = "suggest", q = m_q, f = m_f, tokenid = tok ~= nil and tok.charid or nil })
                    end },
            } or gui.Panel{
                flow = "horizontal", width = "auto", height = "auto", tmargin = 4,
                gui.Button{ classes = {"sizeM"}, text = string.format("Bid %s", BidText(m_q, m_f)), width = Px(150), height = Px(32),
                    click = function() BidNow() end },
                g.bid ~= nil and gui.Button{ classes = {"sizeM"}, text = "Liar!", width = Px(110), height = Px(32), hmargin = 8,
                    click = function() CallNow() end } or nil,
            },
            Label(NextText(g.bid, total), {"sizeS"}),
        }
        if reason ~= nil then
            rows[#rows + 1] = Label(reason, {"sizeS", "warning"})
        elseif g_oddsSetting:Get() == true then
            rows[#rows + 1] = Label(string.format("%s would be %s.", BidText(m_q, m_f), VERDICT_WORDS[verdict]), {"sizeS", "info"})
        end
        if not suggest then
            if RollingOpen(g) then
                rows[#rows + 1] = Label("Waiting for a test roll to finish.", {"sizeS", "warning"})
            end
            rows[#rows + 1] = Label(m_contextActive and "Keys: Up and Down change the number, 2-6 pick the face, Enter bids, L calls Liar, S takes the newest suggestion."
                or "Click the table to play with the keyboard.", {"sizeXs", "fgMuted"})
        end
        return rows
    end

    --The party's suggested bids, for everyone; too-low ones greyed with a reason (C14).
    ---@return Panel|nil
    local function Suggestions()
        local g = m_view.g
        local list = {}
        for userid, sug in pairs(g.suggest or {}) do
            if type(sug) == "table" then
                list[#list + 1] = { user = userid, s = sug }
            end
        end
        if #list == 0 then
            return nil
        end
        table.sort(list, function(a, b) return (tonumber(a.s.at) or 0) < (tonumber(b.s.at) or 0) end)
        local champ = IsChampion() and IsChampionTurn()
        local tags = { Label("Suggestions:", {"sizeS", "bold"}, { valign = "center", hmargin = 4 }) }
        for _, item in ipairs(list) do
            local sug = item.s
            local q, f = tonumber(sug.q) or 1, tonumber(sug.f) or 2
            local legal = B.Legal(g.bid, q, f, TotalDice(g))
            local text = string.format("%s: %s%s", tostring(sug.name), BidText(q, f), legal and "" or " (too low now)")
            if champ and legal then
                tags[#tags + 1] = gui.Button{ classes = {"sizeS"}, text = text, width = "auto", hpad = 8, height = Px(26), hmargin = 3, valign = "center",
                    click = function() SetChoice(q, f) end }
            else
                tags[#tags + 1] = Label(text, {"sizeS", legal and "fg" or "fgMuted"}, { valign = "center", hmargin = 6 })
            end
        end
        return Lines(tags, 4, 4)
    end

    --The seat (C13): stand up between challenges; take over an idle champion's turn,
    --with a confirm. The Director's nudges for each gambler (C16).
    local m_confirmTakeover = false

    local function Idle()
        local g = m_view.g
        return m_view.phase == "playing" and tonumber(g.turn) == 1 and g.pendingShakeAt == nil
            and dmhub.serverTime - (tonumber(g.turnAt) or dmhub.serverTime) >= IDLE_SECONDS
    end

    local function SeatRows()
        local g = m_view.g
        local rows = {}
        if m_view.readonly then
            return rows
        end
        local champ = Seat(g, 1)
        local tok = Puzzle.MyHero()
        if champ ~= nil and IsChampion() and m_view.phase ~= "playing" then
            rows[#rows + 1] = gui.Button{ classes = {"sizeS"}, text = "Stand up", width = "auto", hpad = 8, height = Px(28), tmargin = 4, halign = "left",
                click = function() Send({ kind = "move", act = "standup" }) end }
        end
        if champ ~= nil and not IsChampion() and Idle() and tok ~= nil then
            if m_confirmTakeover then
                rows[#rows + 1] = gui.Panel{
                    flow = "horizontal", width = "auto", height = "auto", tmargin = 4,
                    Label(string.format("Take over %s's seat and dice as %s?", champ.name, tok.name or "your hero"), {"sizeS", "bold"}, { valign = "center", hmargin = 4 }),
                    gui.Button{ classes = {"sizeS"}, text = "Yes", width = Px(60), height = Px(26), hmargin = 3, valign = "center",
                        click = function()
                            m_confirmTakeover = false
                            Send({ kind = "move", act = "takeover", tokenid = tok.charid })
                        end },
                    gui.Button{ classes = {"sizeS"}, text = "No", width = Px(60), height = Px(26), valign = "center",
                        click = function() m_confirmTakeover = false Rebuild(true) end },
                }
            else
                rows[#rows + 1] = gui.Button{ classes = {"sizeS"}, text = "Take over the seat", width = "auto", hpad = 8, height = Px(28), tmargin = 4, halign = "left",
                    click = function() m_confirmTakeover = true Rebuild(true) end }
            end
        end
        if dmhub.isDM and m_view.phase == "playing" then
            local nudges = { Label("Director:", {"sizeS", "bold"}, { hmargin = 4 }) }
            for i = 2, SeatCount(g) do
                if Alive(g, i) then
                    local seatIndex = i
                    local pending = (g.nudge or {})["s" .. i]
                    nudges[#nudges + 1] = gui.Panel{
                        flow = "horizontal", width = "auto", height = "auto", vmargin = 1,
                        Label(SeatName(g, i) .. (pending ~= nil and string.format(" (will %s)", pending) or "") .. ":", {"sizeS"}, { valign = "center", hmargin = 4, minWidth = Px(120) }),
                        gui.Button{ classes = {"sizeXs"}, text = "Call next", width = "auto", hpad = 6, height = Px(24), hmargin = 2, valign = "center",
                            click = function() Send({ kind = "move", act = "nudge", seat = seatIndex, nudge = "call" }) end },
                        gui.Button{ classes = {"sizeXs"}, text = "Bluff next", width = "auto", hpad = 6, height = Px(24), hmargin = 2, valign = "center",
                            click = function() Send({ kind = "move", act = "nudge", seat = seatIndex, nudge = "bluff" }) end },
                    }
                end
            end
            rows[#rows + 1] = gui.Panel{ flow = "vertical", width = "auto", height = "auto", tmargin = 6, children = nudges }
        end
        return rows
    end

    --A test for this player's hero: once-per scopes, the roll, and its result to the host.
    local READ_TIERS = { "Their face gives nothing away.", "You get a sense of them.", "You read them like a book." }
    local SELL_TIERS = { "Nobody's buying it.", "They lean in to listen.", "The table hangs on your words." }
    local PEEK_TIERS = { "You can't get a look.", "You glimpse a die.", "A clean look, unseen." }
    local WATCH_TIERS = { "Nothing odd.", "Something's off.", "You see exactly how they cheat." }

    local function RollFor(test, attrid, skill, name, tiers, extra, bane)
        local tok = Puzzle.MyHero()
        if tok == nil then
            return
        end
        Send({ kind = "move", act = "rolling", on = true })
        Puzzle.RollTest(tok, attrid, skill, name, tiers, function()
            return m_view ~= nil and m_view.phase == "playing"
        end, function(tier, natural)
            local args = { kind = "move", act = "test", test = test, tier = tier, natural = natural, tokenid = tok.charid }
            for k, v in pairs(extra or {}) do
                args[k] = v
            end
            Send(args)
        end, function()
            Send({ kind = "move", act = "rolling", on = false })
        end, bane)
    end

    --This player's tests and their private results.
    local function TestRows()
        local g = m_view.g
        local eff = m_view.eff or {}
        local rows = {}
        local me = Me()
        local notes = {}
        for _, n in pairs((g.notes or {})[me] or {}) do
            if type(n) == "table" and (tonumber(n.challenge) == 0 or tonumber(n.challenge) == tonumber(g.challenge)) then
                notes[#notes + 1] = n
            end
        end
        table.sort(notes, function(a, b) return (tonumber(a.seq) or 0) < (tonumber(b.seq) or 0) end)
        if #notes > 0 then
            local lines = {}
            for i = math.max(1, #notes - 3), #notes do
                lines[#lines + 1] = notes[i].text
            end
            rows[#rows + 1] = Label("Only you see this:\n" .. table.concat(lines, "\n"), {"sizeS", "info"}, { tmargin = 4 })
        end
        if eff.tests ~= true or m_view.phase ~= "playing" or m_view.readonly or g.pendingShakeAt ~= nil then
            return rows
        end
        local tok = Puzzle.MyHero()
        if tok == nil then
            rows[#rows + 1] = Label("Select your hero to roll a test.", {"sizeS", "fgMuted"})
            return rows
        end
        local champ = IsChampion()
        local champTurn = tonumber(g.turn) == 1
        local buttons = {}
        local function Add(text, fn)
            buttons[#buttons + 1] = gui.Button{ classes = {"sizeS"}, text = text, width = "auto", hpad = 8, height = Px(28), hmargin = 3, vmargin = 2,
                click = function() fn() end }
        end
        local bid = g.bid
        if not champ and champTurn and bid ~= nil and tonumber(bid.by) ~= 1 and (g.reads or {})[me] == nil then
            local target = tonumber(bid.by) or 2
            local name = SeatName(g, target)
            local bane = (g.clammed or {})["s" .. target] and string.format("%s has clammed up", name) or nil
            Add(string.format("Read %s's bid (Intuition)", name), function()
                RollFor("read", "inu", "Read Person, Gamble", "Read the bid", READ_TIERS, nil, bane)
            end)
        end
        if champTurn and (g.sells or {})[me] == nil then
            Add("Sell the bluff (Presence)", function()
                RollFor("sell", "prs", "Lie, Gamble", "Sell the bluff", SELL_TIERS, nil, nil)
            end)
        end
        if not champ and (g.peeked or {})[me] == nil then
            for i = 2, SeatCount(g) do
                if Alive(g, i) and not (g.guarded or {})["s" .. i] then
                    local seatIndex = i
                    Add(string.format("Peek at %s (Agility)", SeatName(g, i)), function()
                        RollFor("peek", "agl", "Pick Pocket", "Peek at a die", PEEK_TIERS, { seat = seatIndex }, nil)
                    end)
                end
            end
        end
        if (g.watched or {})[me] == nil then
            Add("Watch the table (Intuition)", function()
                RollFor("watch", "inu", "Read Person, Gamble", "Watch the table", WATCH_TIERS, nil, nil)
            end)
        end
        if #buttons > 0 then
            rows[#rows + 1] = Lines(buttons, 3, 4)
        end
        --the champion's answers to a caught cheat (#9, C6).
        if champ then
            local answers = {}
            if g.claim then
                answers[#answers + 1] = gui.Button{ classes = {"sizeS"}, text = "Claim the game", width = "auto", hpad = 8, height = Px(28), hmargin = 3,
                    click = function() Send({ kind = "move", act = "claim" }) end }
            end
            if champTurn then
                for i = 2, SeatCount(g) do
                    if (g.caught or {})["s" .. i] and Alive(g, i) then
                        local seatIndex = i
                        answers[#answers + 1] = gui.Button{ classes = {"sizeS"}, text = string.format("Call out %s's loaded dice", SeatName(g, i)),
                            width = "auto", hpad = 8, height = Px(28), hmargin = 3,
                            click = function() Send({ kind = "move", act = "callout", seat = seatIndex }) end }
                    end
                end
            end
            if #answers > 0 then
                rows[#rows + 1] = gui.Panel{ flow = "horizontal", width = "auto", height = "auto", tmargin = 4, children = answers }
            end
        end
        return rows
    end

    --This challenge's turns, newest last (C11).
    local function History()
        local lines = {}
        for _, line in pairs(m_view.g.hist or {}) do
            if type(line) == "table" then
                lines[#lines + 1] = line
            end
        end
        table.sort(lines, function(a, b) return (tonumber(a.seq) or 0) < (tonumber(b.seq) or 0) end)
        local out = {}
        for i = math.max(1, #lines - HIST_SHOW + 1), #lines do
            out[#out + 1] = lines[i].text
        end
        if #out == 0 then
            return nil
        end
        return Label(table.concat(out, "\n"), {"sizeS"}, { tmargin = 6 })
    end

    Rebuild = function(force)
        if m_view == nil or resultPanel == nil or not resultPanel.valid then
            return
        end
        local g = m_view.g
        local bidKey = json(g.bid or {}) .. tostring(g.challenge)
        if bidKey ~= m_bidKey then
            m_bidKey = bidKey
            ResetChoice()
        end
        local sig = json(g) .. m_view.phase .. tostring(m_view.readonly) .. tostring(m_view.large) .. tostring(g_oddsSetting:Get())
            .. tostring(m_contextActive) .. tostring(m_q) .. ":" .. tostring(m_f)
        if not force and sig == m_signature then
            return
        end
        m_signature = sig
        local children = { SeatsRow() }
        for _, row in ipairs(BidLines()) do
            children[#children + 1] = row
        end
        if g.thinking ~= nil and m_view.phase == "playing" and g.pendingShakeAt == nil then
            children[#children + 1] = Label(g.thinking, {"sizeS", "fgMuted"}, { italics = true })
        end
        if g.reveal ~= nil then
            children[#children + 1] = gui.Panel{
                flow = "vertical", width = "auto", height = "auto", tmargin = 6, pad = 8, borderBox = true,
                bgimage = "panels/square.png", bgcolor = "#00000044", border = 1, borderColor = TURN_BORDER,
                Label(g.reveal.text, {"sizeM", "bold"}),
                Label(string.format("Salt %s -- each hand checks against its hash.", tostring(g.reveal.salt or "")), {"sizeXs", "fgMuted"}),
            }
        end
        if g.reveal == nil then
            local suggestions = Suggestions()
            if suggestions ~= nil then
                children[#children + 1] = suggestions
            end
        end
        if IsChampionTurn() then
            for _, row in ipairs(Controls(false)) do
                children[#children + 1] = row
            end
        elseif m_view.phase == "playing" and not m_view.readonly and Seat(g, 1) ~= nil and not IsChampion() and g.reveal == nil then
            for _, row in ipairs(Controls(true)) do
                children[#children + 1] = row
            end
        end
        for _, row in ipairs(TestRows()) do
            children[#children + 1] = row
        end
        for _, row in ipairs(SeatRows()) do
            children[#children + 1] = row
        end
        local history = History()
        if history ~= nil then
            children[#children + 1] = history
        end
        children[#children + 1] = gui.Check{
            classes = {"sizeS"}, width = "auto", height = 22, tmargin = 4, halign = "left",
            text = "Odds help",
            value = g_oddsSetting:Get() == true,
            change = function(element) g_oddsSetting:Set(element.value) Rebuild(true) end,
        }
        resultPanel.children = children
    end

    local function SyncContext()
        local want = IsChampionTurn() and resultPanel ~= nil and resultPanel.valid and gui.GetFocus() == resultPanel
        if want ~= m_contextActive then
            m_contextActive = want
            if want then
                dmhub.PushCommandContext(COMMAND_CONTEXT)
                Rebuild(true)
            else
                dmhub.PopCommandContext(COMMAND_CONTEXT)
            end
        end
    end

    local function Key(fn)
        return function(element)
            if IsChampionTurn() then
                fn()
            end
        end
    end

    local handlers = {
        data = {},
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        bgimage = "panels/square.png",
        bgcolor = "#00000000",
        chanceTurns = function(element, view)
            m_view = view
            Rebuild(false)
        end,
        click = function(element)
            if IsChampionTurn() then
                gui.SetFocus(element)
                SyncContext()
            end
        end,
        thinkTime = 0.2,
        think = function(element)
            SyncContext()
            if m_view ~= nil then
                local idle = Idle()
                if idle ~= element.data.idle then
                    element.data.idle = idle
                    Rebuild(true)
                end
            end
        end,
        destroy = function(element)
            if m_contextActive then
                m_contextActive = false
                dmhub.PopCommandContext(COMMAND_CONTEXT)
            end
        end,
        commands = KEY_COMMANDS,
        ld_up = Key(function() SetChoice(m_q + 1, m_f) end),
        ld_down = Key(function() SetChoice(m_q - 1, m_f) end),
        ld_bid = Key(BidNow),
        ld_bid2 = Key(BidNow),
        ld_liar = Key(CallNow),
        ld_suggest = Key(function()
            local g = m_view.g
            local best = nil
            for _, sug in pairs(g.suggest or {}) do
                if type(sug) == "table" and B.Legal(g.bid, tonumber(sug.q) or 0, tonumber(sug.f) or 0, TotalDice(g))
                    and (best == nil or (tonumber(sug.at) or 0) > (tonumber(best.at) or 0)) then
                    best = sug
                end
            end
            if best ~= nil then
                SetChoice(tonumber(best.q) or 1, tonumber(best.f) or 2)
            end
        end),
    }
    for f = 2, 6 do
        local face = f
        handlers["ld_f" .. face] = Key(function() SetChoice(m_q, face) end)
    end
    resultPanel = gui.Panel(handlers)
    return resultPanel
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

---@param config table
---@return boolean
local function Seat3(config)
    return (math.tointeger(tonumber(config.gamblers)) or 2) >= 2
end

---@param config table
---@return boolean
local function Seat4(config)
    return (math.tointeger(tonumber(config.gamblers)) or 2) >= 3
end

GameOfChance.Register{
    id = "liarsdice",
    name = "Liar's dice",
    howToPlay = [[
One hero, the champion, plays against the gamblers at the table. Everyone has five dice under a cup. Ones are wild: they count as every face.

Press Take a seat and your selected hero becomes the champion. The whole party sees the champion's dice and can help.

On your turn, bid how many dice on the whole table show one face, such as "four 5s". Every bid must raise the last: more dice, or the same number of a higher face. Or call Liar! if you think the last bid is too high.

When someone calls Liar, the cups lift and the dice are counted. If the bid was right, the caller loses a die. If not, the bidder does. Each challenge the champion takes part in is a round: win enough rounds before you lose too many.

The rest of the party can suggest bids and roll tests: Read the bid (Intuition), Sell the bluff (Presence), Peek at a gambler's die (Agility) and Watch the table (Intuition) for cheating. Odds help shows how likely a bid is.

Keyboard: click the table, then Up and Down change the number, 2-6 pick the face, Enter bids, L calls Liar, and S takes the newest suggestion.]],
    flow = "turns",
    presets = PRESETS,
    presetOptions = {
        { id = "tavern", text = "Friendly tavern (two honest gamblers)" },
        { id = "rigged", text = "Rigged house (a shady gambler, gold stake)" },
        { id = "carnival", text = "Devil's Carnival (a crooked gambler, a Recovery at stake)" },
    },
    fields = {
        { id = "gamblers", type = "number", label = "Gamblers at the table", default = 2, min = 1, max = 3 },
        { id = "seat2", type = "choice", label = "First gambler", default = "grisk", options = CAST_OPTIONS },
        { id = "seat3", type = "choice", label = "Second gambler", default = "mara", options = CAST_OPTIONS, visible = Seat3 },
        { id = "seat4", type = "choice", label = "Third gambler", default = "vell", options = CAST_OPTIONS, visible = Seat4 },
    },
    startLabel = StartLabel,
    NewGame = NewGame,
    CanStart = function(g, eff, req, userid)
        local champ = Seat(g, 1)
        local tokenid = champ ~= nil and champ.tokenid or req.tokenid
        local tok = type(tokenid) == "string" and Puzzle.HeroById(tokenid) or nil
        if tok == nil or (champ ~= nil and not Alive(g, 1)) then
            return false
        end
        --a hero who can't cover the stake can't play for it (shell #32): a stake never
        --takes a hero below nothing, so they could only win.
        return S.CanCover(tok, eff)
    end,
    Start = function(g, eff, random, secret, events, req, userid)
        if Seat(g, 1) == nil then
            local tok = Puzzle.HeroById(req.tokenid)
            local name = Puzzle.UserName(userid)
            if tok ~= nil and tok.name ~= nil and tok.name ~= "" then
                name = tok.name
            end
            --a seat someone stood up from keeps its dice (C13).
            g.seats.s1 = { user = userid, tokenid = req.tokenid, name = name, dice = tonumber(g.vacantDice) or DICE }
            g.vacantDice = nil
            events[#events + 1] = { log = string.format("%s takes a seat at the table.", name) }
        end
        g.challenge = (tonumber(g.challenge) or 0) + 1
        Shake(g, random, secret)
        events[#events + 1] = { log = string.format("Challenge %d: the cups go down.", g.challenge) }
    end,
    Move = function(g, eff, secret, req, userid, random, events, phase)
        local champ = Seat(g, 1)
        local act = req.act
        if act == "standup" then
            --between challenges only: the seat and its dice wait for the next hero.
            if phase == "playing" or champ == nil or champ.user ~= userid then
                return false
            end
            g.vacantDice = tonumber(champ.dice) or DICE
            g.seats.s1 = nil
            events[#events + 1] = { log = string.format("%s stands up from the table.", champ.name) }
            return true
        end
        if phase ~= "playing" then
            return false
        end
        if act == "takeover" then
            --the champion's turn sat idle (stepped away, or gone): another hero takes the
            --same seat and dice (C13). The first request wins; later ones find it taken.
            local tok = type(req.tokenid) == "string" and Puzzle.HeroById(req.tokenid) or nil
            if champ == nil or champ.user == userid or tok == nil or not S.CanCover(tok, eff) or tonumber(g.turn) ~= 1
                or dmhub.serverTime - (tonumber(g.turnAt) or dmhub.serverTime) < IDLE_SECONDS then
                return false
            end
            local name = HeroName(req.tokenid, userid)
            events[#events + 1] = { log = string.format("%s takes over %s's seat.", name, champ.name) }
            AddHist(g, string.format("%s takes over the seat.", name))
            champ.user = userid
            champ.tokenid = req.tokenid
            champ.name = name
            g.turnAt = dmhub.serverTime
            return true
        elseif act == "nudge" then
            --the Director steers a gambler's next move (C16).
            local dm = false
            pcall(function() dm = dmhub.GetSessionInfo(userid).dm == true end)
            local target = math.tointeger(tonumber(req.seat))
            if not dm or target == nil or target < 2 or not Alive(g, target) then
                return false
            end
            g.nudge = g.nudge or {}
            g.nudge["s" .. target] = (req.nudge == "call" or req.nudge == "bluff") and req.nudge or nil
            return true
        end
        if act == "rolling" then
            g.rolling = g.rolling or {}
            g.rolling[userid] = req.on == true and dmhub.serverTime or nil
            return true
        elseif act == "test" then
            return Test(g, eff, secret, req, userid, random)
        elseif act == "suggest" then
            local q = math.tointeger(tonumber(req.q))
            local f = math.tointeger(tonumber(req.f))
            if (champ ~= nil and champ.user == userid) or q == nil or f == nil or not B.Legal(nil, q, f, TotalDice(g)) then
                return false
            end
            g.suggest = g.suggest or {}
            g.suggest[userid] = { q = q, f = f, name = HeroName(req.tokenid, userid), at = dmhub.serverTime }
            return true
        end
        if champ == nil or champ.user ~= userid then
            return false
        end
        if act == "claim" and g.claim then
            --the rules' Notice the Cheaters 17+: win without any other test (C6).
            g.claim = nil
            AddHist(g, string.format("%s shows the table how the cheating works and claims the game.", champ.name))
            events[#events + 1] = { log = string.format("%s claims the game: the cheats are exposed.", champ.name), round = "win", final = true,
                bettor = { user = champ.user, tokenid = champ.tokenid } }
            g.turn = nil
            return true
        end
        if tonumber(g.turn) ~= 1 or g.pendingShakeAt ~= nil or RollingOpen(g) then
            return false
        end
        if act == "callout" then
            local target = math.tointeger(tonumber(req.seat))
            if target == nil or not (g.caught or {})["s" .. target] or not Alive(g, target) then
                return false
            end
            g.caught["s" .. target] = nil
            local seat = TakenSeat(g, target)
            seat.dice = math.max(0, (tonumber(seat.dice) or 0) - 1)
            local text = string.format("%s calls out %s's loaded dice! %s loses a die.", champ.name, seat.name, seat.name)
            AddHist(g, string.format("%s: \"%s\"", seat.name, CAUGHT_LINES[seat.honesty] or CAUGHT_LINES.crooked))
            AddHist(g, text)
            g.reveal = { text = text, loser = target }
            g.opener = target
            g.turn = nil
            local gamblersLeft = false
            for i = 2, SeatCount(g) do
                if Alive(g, i) then
                    gamblersLeft = true
                end
            end
            events[#events + 1] = { log = text, chat = text, round = "win", final = not gamblersLeft,
                bettor = { user = champ.user, tokenid = champ.tokenid } }
            return true
        end
        if req.act == "bid" then
            local q = math.tointeger(tonumber(req.q))
            local f = math.tointeger(tonumber(req.f))
            if q == nil or f == nil or not B.Legal(g.bid, q, f, TotalDice(g)) then
                return false
            end
            g.bid = { q = q, f = f, by = 1 }
            AddHist(g, string.format("%s bids %s.", champ.name, BidText(q, f)))
            PassTurn(g, random)
            return true
        elseif req.act == "call" and g.bid ~= nil then
            AddHist(g, string.format("%s calls Liar!", champ.name))
            Resolve(g, secret, 1, random, events)
            return true
        end
        return false
    end,
    HostStep = function(g, eff, secret, now, random, events, pace)
        g.pace = pace
        local expired = false
        for userid, at in pairs(g.rolling or {}) do
            if type(at) ~= "number" or now - at > ROLL_HOLD_SECONDS then
                g.rolling[userid] = nil
                expired = true
            end
        end
        --a new host has no hands for this challenge: shake again (#15).
        if tonumber(secret.challenge) ~= tonumber(g.challenge) and g.reveal == nil then
            Shake(g, random, secret)
            events[#events + 1] = { log = "The table changed hands: the cups are shaken again." }
            return true
        end
        if g.pendingShakeAt ~= nil then
            if now >= g.pendingShakeAt then
                Shake(g, random, secret)
                return true
            end
            return expired
        end
        local turn = tonumber(g.turn)
        if turn == nil or turn == 1 or g.nextAt == nil or now < g.nextAt then
            return expired
        end
        local seat = TakenSeat(g, turn)
        local hand = B.ParseHand((secret.hands or {})["s" .. turn])
        local opts = nil
        if g.bid ~= nil and tonumber(g.bid.by) == 1 then
            --facing the champion's bid: a sold bluff (C2) and lost goodwill (C4).
            local sell = g.sell or {}
            opts = { trust = tonumber(sell.trust) or 0, wary = (tonumber(sell.wary) or 0) + (tonumber((g.wary or {})["s" .. turn]) or 0) }
            g.sell = nil
        end
        local move = B.Turn(random, hand, TotalDice(g), g.bid, seat.honesty, opts)
        local nudge = (g.nudge or {})["s" .. turn]
        if nudge ~= nil then
            g.nudge["s" .. turn] = nil
            if nudge == "call" and g.bid ~= nil then
                move = "call"
            elseif nudge == "bluff" then
                local raises = B.MinRaises(g.bid, TotalDice(g))
                if #raises > 0 then
                    move = raises[random(#raises)]
                end
            end
        end
        if move == "call" and g.bid ~= nil then
            AddHist(g, string.format("%s: \"%s\"", seat.name, CALL_LINES[seat.honesty] or CALL_LINES.honest))
            Resolve(g, secret, turn, random, events)
        else
            if move == "call" then
                move = { q = 1, f = 2 + random(5) - 1 }
            end
            g.bid = { q = move.q, f = move.f, by = turn }
            AddHist(g, string.format("%s bids %s.", seat.name, BidText(move.q, move.f)))
            PassTurn(g, random)
        end
        return true
    end,
    Status = function(g, eff, phase, viewer)
        local champ = Seat(g, 1)
        if phase ~= "playing" then
            local stake = S.StakeText(eff)
            local tok = nil
            if champ ~= nil then
                tok = Puzzle.HeroById(champ.tokenid)
            else
                tok = Puzzle.MyHero()
            end
            if stake ~= nil and tok ~= nil and not S.CanCover(tok, eff) then
                return string.format("%s can't cover the stake (%s).%s", champ ~= nil and champ.name or (tok.name or "Your hero"), stake,
                    champ ~= nil and " They can stand up for another hero." or "")
            end
            if champ == nil then
                return "Take a seat to play: your selected hero becomes the champion."
            end
            return string.format("Shake the dice for the next challenge. %s plays for the party.", champ.name)
        end
        if g.pendingShakeAt ~= nil then
            return "The gamblers settle it between themselves. The cups go round again."
        end
        local turn = tonumber(g.turn) or 1
        if turn == 1 then
            if RollingOpen(g) then
                return "Waiting for a test roll to finish."
            end
            if champ ~= nil and champ.user == viewer then
                return g.bid ~= nil and string.format("Your turn: raise %s or call Liar.", BidText(g.bid.q, g.bid.f))
                    or "Your turn: open the bidding."
            end
            if dmhub.serverTime - (tonumber(g.turnAt) or dmhub.serverTime) >= IDLE_SECONDS then
                return string.format("%s's turn has waited a while. Anyone can take over the seat.", champ ~= nil and champ.name or "The champion")
            end
            return string.format("%s's turn. Suggest a bid, or watch.", champ ~= nil and champ.name or "The champion")
        end
        return string.format("%s is thinking...", SeatName(g, turn))
    end,
    EndNow = function(g, secret)
        local hands = AllHands(g, secret)
        local revealed = {}
        for i = 1, #hands do
            revealed["s" .. i] = B.HandText(hands[i])
        end
        g.reveal = { hands = revealed, salt = secret.salt, text = "The Director ends the game. The cups are lifted." }
        g.turn = nil
        g.nextAt = nil
        g.thinking = nil
        g.pendingShakeAt = nil
    end,
    Board = Board,
}
