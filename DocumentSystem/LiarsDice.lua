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

local DICE = 5
local MAX_SEATS = 4
local HIST_KEEP = 12
local HIST_SHOW = 6
--seconds a gambler "thinks", and the pause after a challenge between gamblers.
local THINK_MIN, THINK_MAX = 1.1, 2.5
local NPC_REVEAL_PAUSE = 3

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

---@param random fun(k: integer): integer
---@return number
local function ThinkTime(random)
    return THINK_MIN + (random(15) - 1) / 14 * (THINK_MAX - THINK_MIN)
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
    g.turn = Alive(g, tonumber(g.opener) or 1) and (tonumber(g.opener) or 1) or NextAlive(g, tonumber(g.opener) or 1)
    g.thinking = nil
    g.nextAt = nil
    if g.turn ~= 1 then
        g.nextAt = dmhub.serverTime + ThinkTime(random)
    end
end

---@param g table
---@param random fun(k: integer): integer
local function PassTurn(g, random)
    g.turn = NextAlive(g, tonumber(g.turn) or 1)
    g.thinking = nil
    g.nextAt = nil
    if g.turn ~= 1 then
        g.nextAt = dmhub.serverTime + ThinkTime(random)
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
    g.reveal = { hands = revealed, salt = secret.salt, count = count, q = bid.q, f = bid.f, caller = caller, bidder = bidder, loser = loser, text = text }
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
        g.pendingShakeAt = dmhub.serverTime + NPC_REVEAL_PAUSE
    end
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
                bgimage = "panels/square.png", bgcolor = DIE_HIDDEN, border = 1, borderColor = "#00000088",
                Label("?", {"sizeS", "bold"}, { halign = "center", valign = "center", interactable = false }),
            }
        end
        return gui.Panel{
            flow = "vertical", width = "auto", height = "auto", hmargin = 2, valign = "center",
            gui.Panel{
                width = size + 4, height = size + 4, halign = "center",
                bgimage = "panels/square.png", bgcolor = "#00000000",
                border = opts.match and 2 or 0, borderColor = MATCH_BORDER,
                gui.Panel{ width = size, height = size, halign = "center", valign = "center",
                    bgimage = "phosphor/dice-" .. FACE_NAMES[face] .. ".png", bgcolor = DIE_COLOR, interactable = false },
            },
            Label(tostring(face) .. (opts.match and "+" or ""), {"sizeXs"}, { halign = "center", interactable = false }),
        }
    end

    local function Me()
        return m_view ~= nil and m_view.me or dmhub.userid
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
            if dice == 0 and (hand == nil or #hand == 0) then
                dieRow[1] = Label("Out of dice", {"sizeS", "fgMuted"})
            elseif hand ~= nil and #hand > 0 then
                for _, d in ipairs(hand) do
                    dieRow[#dieRow + 1] = Die(d, { match = face ~= nil and (d == face or d == 1) })
                end
            else
                for _ = 1, dice do
                    dieRow[#dieRow + 1] = Die(1, { hidden = true })
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
        return gui.Panel{ flow = "horizontal", width = "auto", height = "auto", wrap = true, children = boxes }
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
            local known = B.ParseHand(g.champHand)
            local verdict = B.Verdict(known, total, g.bid.q, g.bid.f)
            local hidden = total - #known
            local likely = math.floor(hidden / 3 + 0.5)
            rows[#rows + 1] = Label(string.format("%s is %s. The champion holds %d; about %d more are likely among the %d hidden dice.",
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
    local function Controls()
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
        local known = B.ParseHand(g.champHand)
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
            gui.Panel{
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
            rows[#rows + 1] = Label(string.format("Your %s would be %s.", BidText(m_q, m_f), VERDICT_WORDS[verdict]), {"sizeS", "info"})
        end
        rows[#rows + 1] = Label(m_contextActive and "Keys: Up and Down change the number, 2-6 pick the face, Enter bids, L calls Liar."
            or "Click the table to play with the keyboard.", {"sizeXs", "fgMuted"})
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
        if IsChampionTurn() then
            for _, row in ipairs(Controls()) do
                children[#children + 1] = row
            end
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
        if champ == nil then
            return type(req.tokenid) == "string" and Puzzle.HeroById(req.tokenid) ~= nil
        end
        return Alive(g, 1)
    end,
    Start = function(g, eff, random, secret, events, req, userid)
        if Seat(g, 1) == nil then
            local tok = Puzzle.HeroById(req.tokenid)
            local name = Puzzle.UserName(userid)
            if tok ~= nil and tok.name ~= nil and tok.name ~= "" then
                name = tok.name
            end
            g.seats.s1 = { user = userid, tokenid = req.tokenid, name = name, dice = DICE }
            events[#events + 1] = { log = string.format("%s takes a seat at the table.", name) }
        end
        g.challenge = (tonumber(g.challenge) or 0) + 1
        Shake(g, random, secret)
        events[#events + 1] = { log = string.format("Challenge %d: the cups go down.", g.challenge) }
    end,
    Move = function(g, eff, secret, req, userid, random, events)
        local champ = Seat(g, 1)
        if champ == nil or champ.user ~= userid or tonumber(g.turn) ~= 1 or g.pendingShakeAt ~= nil then
            return false
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
    HostStep = function(g, eff, secret, now, random, events)
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
            return false
        end
        local turn = tonumber(g.turn)
        if turn == nil or turn == 1 or g.nextAt == nil or now < g.nextAt then
            return false
        end
        local seat = TakenSeat(g, turn)
        local hand = B.ParseHand((secret.hands or {})["s" .. turn])
        local move = B.Turn(random, hand, TotalDice(g), g.bid, seat.honesty)
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
            if champ ~= nil and champ.user == viewer then
                return g.bid ~= nil and string.format("Your turn: raise %s or call Liar.", BidText(g.bid.q, g.bid.f))
                    or "Your turn: open the bidding."
            end
            return string.format("%s's turn. Suggest a bid, or watch.", champ ~= nil and champ.name or "The champion")
        end
        return string.format("%s is thinking...", SeatName(g, turn))
    end,
    Board = Board,
}
