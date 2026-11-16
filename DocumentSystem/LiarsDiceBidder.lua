-- Liar's dice rules and the NPC gamblers' bidding (liars-dice-brief.md #3, #9, #15, #17,
-- C2, C6, C7). Runs no engine code, so tests/liars_dice_bidder_test.lua runs it under the
-- bundled lua.exe.
--
-- A hand is a list of die faces 1-6; ones are wild. A bid is {q = quantity, f = face 2-6}.
-- Faces cannot be bid on ones (the later list has Perudo's rule).

LiarsDiceBidder = {}

local FACES = 6

--How each kind of gambler plays. nerve: how far past their own estimate a bid may go
--before they call it; bluff: chance of raising on a face they don't believe in.
LiarsDiceBidder.styles = {
    honest = { nerve = 0.5, bluff = 0.08 },
    shady = { nerve = 1.0, bluff = 0.25 },
    crooked = { nerve = 1.5, bluff = 0.40 },
}

---@param hand integer[]
---@param f integer
---@return integer
function LiarsDiceBidder.Matches(hand, f)
    local n = 0
    for _, d in ipairs(hand) do
        if d == f or d == 1 then
            n = n + 1
        end
    end
    return n
end

--How many dice on the whole table count for face f.
---@param hands integer[][]
---@param f integer
---@return integer
function LiarsDiceBidder.Count(hands, f)
    local n = 0
    for _, hand in ipairs(hands) do
        n = n + LiarsDiceBidder.Matches(hand, f)
    end
    return n
end

--Is {q, f} a legal next bid after `bid` (nil when opening), with `total` dice in play?
---@param bid {q: integer, f: integer}|nil
---@param q integer
---@param f integer
---@param total integer
---@return boolean
function LiarsDiceBidder.Legal(bid, q, f, total)
    if f < 2 or f > FACES or q < 1 or q > total then
        return false
    end
    if bid == nil then
        return true
    end
    return q > bid.q or (q == bid.q and f > bid.f)
end

--The smallest legal bid on each face, for "Next: ..." and for the bidder.
---@param bid {q: integer, f: integer}|nil
---@param total integer
---@return {q: integer, f: integer}[]
function LiarsDiceBidder.MinRaises(bid, total)
    local out = {}
    for f = 2, FACES do
        local q = 1
        if bid ~= nil then
            q = f > bid.f and bid.q or bid.q + 1
        end
        if q <= total then
            out[#out + 1] = { q = q, f = f }
        end
    end
    return out
end

--What someone holding `known` dice expects on the table for face f: the matches they
--can see plus a third of the dice they can't (two faces in six count: f and wild ones).
---@param known integer[] every die this viewer can see
---@param total integer
---@param f integer
---@return number
function LiarsDiceBidder.Expect(known, total, f)
    return LiarsDiceBidder.Matches(known, f) + (total - #known) / 3
end

--The odds help in words (C7): how a bid of q x f looks from what the party can see.
---@param known integer[]
---@param total integer
---@param q integer
---@param f integer
---@return "sure"|"expected"|"stretch"|"longshot"
function LiarsDiceBidder.Verdict(known, total, q, f)
    if q <= LiarsDiceBidder.Matches(known, f) then
        return "sure"
    end
    local expected = LiarsDiceBidder.Expect(known, total, f)
    if q <= expected + 0.5 then
        return "expected"
    elseif q <= expected + 2 then
        return "stretch"
    end
    return "longshot"
end

---@alias LiarsMove "call"|{q: integer, f: integer}

--One gambler's turn. opts.trust: extra matching dice the gambler credits the last bidder
--with (Sell the bluff, C2); opts.wary: how much less nerve they have (goodwill lost, C4).
---@param random fun(k: integer): integer
---@param hand integer[]
---@param total integer
---@param bid {q: integer, f: integer}|nil
---@param style string
---@param opts {trust: number|nil, wary: number|nil}|nil
---@return LiarsMove
function LiarsDiceBidder.Turn(random, hand, total, bid, style, opts)
    opts = opts or {}
    local s = LiarsDiceBidder.styles[style] or LiarsDiceBidder.styles.honest
    local nerve = s.nerve - (opts.wary or 0)
    if bid ~= nil then
        local believed = LiarsDiceBidder.Expect(hand, total, bid.f) + (opts.trust or 0)
        if bid.q > believed + nerve then
            return "call"
        end
    end
    local best, bestScore = nil, -math.huge
    local raises = LiarsDiceBidder.MinRaises(bid, total)
    for _, raise in ipairs(raises) do
        local expected = LiarsDiceBidder.Expect(hand, total, raise.f)
        local q = raise.q
        if bid == nil then
            q = math.max(1, math.floor(expected))
        end
        local score = expected - q
        if score > bestScore then
            best, bestScore = { q = q, f = raise.f }, score
        end
    end
    if best == nil then
        return "call"
    end
    --a raise this gambler cannot believe either: better to call.
    if bid ~= nil and bestScore < -nerve then
        return "call"
    end
    --a bluff: a legal raise on some other face (random(1000) for a fractional chance).
    if random(1000) <= math.floor(s.bluff * 1000) then
        local pick = raises[random(#raises)]
        if bid == nil then
            pick = { q = math.max(1, best.q), f = pick.f }
        end
        return pick
    end
    return best
end

--Loaded dice (#9, C6), decided by the host at the reveal: a crooked gambler whose own
--challenged bid would fail turns up to two of their dice that don't count to the bid
--face. Returns the new hand and how many dice were loaded (0 = no cheat).
---@param hands integer[][]
---@param seat integer the crooked gambler's index in hands
---@param bid {q: integer, f: integer}
---@return integer[] hand, integer loaded
function LiarsDiceBidder.Load(hands, seat, bid)
    local hand = hands[seat]
    local short = bid.q - LiarsDiceBidder.Count(hands, bid.f)
    if short <= 0 then
        return hand, 0
    end
    local out = {}
    local loaded = 0
    for i, d in ipairs(hand) do
        out[i] = d
        if loaded < math.min(2, short) and d ~= bid.f and d ~= 1 then
            out[i] = bid.f
            loaded = loaded + 1
        end
    end
    return out, loaded
end

--A hand as text, "2,5,5,1,6", and back.
---@param hand integer[]
---@return string
function LiarsDiceBidder.HandText(hand)
    local parts = {}
    for i, d in ipairs(hand) do
        parts[i] = tostring(d)
    end
    return table.concat(parts, ",")
end

---@param text string
---@return integer[]
function LiarsDiceBidder.ParseHand(text)
    local hand = {}
    for d in string.gmatch(tostring(text or ""), "%d") do
        hand[#hand + 1] = math.tointeger(tonumber(d)) or 1
    end
    return hand
end

--The commitment for a hidden hand (#15): 64-bit FNV-1a of salt .. ":" .. hand, as hex.
--Not cryptographic; the salt (published at the reveal) is what stops guessing.
---@param salt string
---@param handText string
---@return string
function LiarsDiceBidder.Commit(salt, handText)
    local h = -3750763034362895579 --0xcbf29ce484222325 as a signed 64-bit integer
    local s = salt .. ":" .. handText
    for i = 1, #s do
        h = h ~ string.byte(s, i)
        h = h * 1099511628211 --wraps modulo 2^64
    end
    return string.format("%016x", h)
end
