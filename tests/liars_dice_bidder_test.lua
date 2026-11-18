--Run from the codex root: ../dmhubclient/dependencies/lua/bin/lua.exe tests/liars_dice_bidder_test.lua [games]
--Checks Liar's dice rules (DocumentSystem/LiarsDiceBidder.lua) on fixed cases, then plays
--many simulated games against each kind of gambler: no illegal bid ever, and a sensible
--champion who never bluffs wins close to half of their own challenges.
dofile("DocumentSystem/LiarsDiceBidder.lua")
local B = LiarsDiceBidder

local GAMES = tonumber(arg and arg[1]) or 20000

--Same generator as Puzzle.SeededRandom (PuzzleFramework.lua).
local function SeededRandom(seedText)
    local seed = 7
    for i = 1, #seedText do
        seed = (seed * 31 + string.byte(seedText, i)) % 2147483648
    end
    return function(k)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return (seed // 65536) % k + 1
    end
end

local failures = 0
local function Fail(fmt, ...)
    failures = failures + 1
    if failures <= 25 then
        print("FAIL: " .. string.format(fmt, ...))
    end
end
local function Check(ok, fmt, ...)
    if not ok then
        Fail(fmt, ...)
    end
end

--------------------------------------------------------------------------------
-- Fixed cases
--------------------------------------------------------------------------------

Check(B.Matches({ 2, 5, 5, 1, 6 }, 5) == 3, "Matches: two 5s and a wild one make 3")
Check(B.Matches({ 2, 5, 5, 1, 6 }, 3) == 1, "Matches: only the wild one counts for 3")
Check(B.Count({ { 1, 1 }, { 4, 6, 4 } }, 4) == 4, "Count: wild ones on every hand")

Check(B.Legal(nil, 1, 2, 10), "Legal: any opening bid")
Check(not B.Legal(nil, 1, 1, 10), "Legal: ones can't be bid on")
Check(not B.Legal(nil, 11, 3, 10), "Legal: never more dice than the table holds")
Check(B.Legal({ q = 3, f = 4 }, 3, 5, 10), "Legal: same quantity, higher face")
Check(not B.Legal({ q = 3, f = 4 }, 3, 4, 10), "Legal: the same bid is no raise")
Check(not B.Legal({ q = 3, f = 4 }, 3, 2, 10), "Legal: same quantity, lower face")
Check(B.Legal({ q = 3, f = 4 }, 4, 2, 10), "Legal: more dice, any face")

local raises = B.MinRaises({ q = 4, f = 5 }, 11)
Check(#raises == 5, "MinRaises: one per face")
for _, r in ipairs(raises) do
    Check(B.Legal({ q = 4, f = 5 }, r.q, r.f, 11), "MinRaises: %d x %d is legal", r.q, r.f)
    Check(not B.Legal({ q = 4, f = 5 }, r.q - 1, r.f, 11) or r.q - 1 < 1, "MinRaises: %d x %d is the smallest", r.q, r.f)
end
Check(#B.MinRaises({ q = 10, f = 6 }, 10) == 0, "MinRaises: nothing past the top")

Check(B.Verdict({ 5, 5, 1 }, 10, 3, 5) == "sure", "Verdict: you can see them all")
Check(B.Verdict({ 5, 2, 3 }, 9, 3, 5) == "expected", "Verdict: 1 + 6/3 = 3 is expected")
Check(B.Verdict({ 2, 2, 3 }, 9, 4, 5) == "stretch", "Verdict: 2 past the estimate is a stretch")
Check(B.Verdict({ 2, 2, 3 }, 9, 6, 5) == "longshot", "Verdict: 4 past is a long shot")

local hand, loaded = B.Load({ { 2, 3, 4, 5, 6 }, { 2, 2 } }, 1, { q = 4, f = 6 })
Check(loaded == 2 and B.Count({ hand, { 2, 2 } }, 6) == 3, "Load: at most two dice turn")
hand, loaded = B.Load({ { 6, 6, 1 }, { 2 } }, 1, { q = 3, f = 6 })
Check(loaded == 0, "Load: never on a bid that already stands")
hand, loaded = B.Load({ { 2, 3, 6 }, { 6 } }, 1, { q = 3, f = 6 })
Check(loaded == 1, "Load: only as many as the bid is short")

Check(B.HandText(B.ParseHand("2,5,5,1,6")) == "2,5,5,1,6", "HandText/ParseHand round trip")
local c1 = B.Commit("salt-a", "2,5,5,1,6")
Check(#c1 == 16 and c1 == B.Commit("salt-a", "2,5,5,1,6"), "Commit: 16 hex digits, stable")
Check(c1 ~= B.Commit("salt-b", "2,5,5,1,6"), "Commit: the salt changes it")
Check(c1 ~= B.Commit("salt-a", "2,5,5,1,5"), "Commit: the hand changes it")

local r1, r2 = SeededRandom("x"), SeededRandom("x")
local m1 = B.Turn(r1, { 2, 5, 5, 1, 6 }, 15, { q = 4, f = 3 }, "shady")
local m2 = B.Turn(r2, { 2, 5, 5, 1, 6 }, 15, { q = 4, f = 3 }, "shady")
Check((m1 == "call") == (m2 == "call") and (m1 == "call" or (m1.q == m2.q and m1.f == m2.f)), "Turn: same seed, same move")
Check(B.Turn(SeededRandom("y"), { 2, 3 }, 10, { q = 9, f = 6 }, "honest") == "call", "Turn: an absurd bid is called")
--holding no 6s among 15 dice, an honest gambler expects 10/3 sixes: 4 x 6 is past their
--nerve, but not once they credit the bidder with 2 more (Sell the bluff, C2).
local plain, trusted = 0, 0
for i = 1, 200 do
    if B.Turn(SeededRandom("plain" .. i), { 2, 3, 4, 2, 3 }, 15, { q = 4, f = 6 }, "honest") == "call" then
        plain = plain + 1
    end
    if B.Turn(SeededRandom("trust" .. i), { 2, 3, 4, 2, 3 }, 15, { q = 4, f = 6 }, "honest", { trust = 2 }) ~= "call" then
        trusted = trusted + 1
    end
end
Check(plain == 200, "Turn: without trust, 4 x 6 is called")
Check(trusted == 200, "Turn: trust 2 lets 4 x 6 stand (C2)")

--------------------------------------------------------------------------------
-- Simulated games
--------------------------------------------------------------------------------

local function Roll(random, n)
    local h = {}
    for i = 1, n do
        h[i] = random(6)
    end
    return h
end

--The champion for the simulation: an honest gambler who never bluffs.
B.styles.champion = { nerve = 0.5, bluff = 0 }

local function Challenge(random, seats, styles, opener)
    local hands, total = {}, 0
    for i, n in ipairs(seats) do
        hands[i] = Roll(random, n)
        total = total + n
    end
    local bid, bidder, bids = nil, nil, 0
    local turn = opener
    for _ = 1, 400 do
        if seats[turn] > 0 then
            local move = B.Turn(random, hands[turn], total, bid, styles[turn])
            if move == "call" then
                if bid == nil then
                    return nil, false, bids, "called with no bid"
                end
                local loser = B.Count(hands, bid.f) >= bid.q and turn or bidder
                return loser, (turn == 1 or bidder == 1), bids, nil
            end
            if not B.Legal(bid, move.q, move.f, total) then
                return nil, false, bids, string.format("illegal %d x %d after %s", move.q, move.f, bid and (bid.q .. " x " .. bid.f) or "nothing")
            end
            bid, bidder, bids = move, turn, bids + 1
        end
        turn = turn % #seats + 1
    end
    return nil, false, bids, "never ended"
end

for _, gamblers in ipairs({ 1, 2, 3 }) do
    for _, style in ipairs({ "honest", "shady", "crooked" }) do
        local random = SeededRandom(style .. gamblers)
        local wins, rounds, bidsTotal, challenges, maxBids = 0, 0, 0, 0, 0
        local started = os.clock()
        for g = 1, GAMES do
            local seats, styles = { 5 }, { "champion" }
            for _ = 1, gamblers do
                seats[#seats + 1] = 5
                styles[#styles + 1] = style
            end
            local opener = g % (gamblers + 1) + 1
            for _ = 1, 30 do
                local loser, champIn, bids, problem = Challenge(random, seats, styles, opener)
                challenges = challenges + 1
                bidsTotal = bidsTotal + bids
                maxBids = math.max(maxBids, bids)
                if problem ~= nil or loser == nil then
                    Fail("%d %s game %d: %s", gamblers, style, g, tostring(problem))
                    break
                end
                seats[loser] = seats[loser] - 1
                opener = loser
                if champIn then
                    rounds = rounds + 1
                    if loser ~= 1 then
                        wins = wins + 1
                    end
                    break
                end
                local alive = 0
                for i = 2, #seats do
                    if seats[i] > 0 then
                        alive = alive + 1
                    end
                end
                if alive == 0 then
                    break
                end
            end
        end
        local rate = wins / math.max(1, rounds)
        Check(rate > 0.40 and rate < 0.60, "%d %s: champion wins %.1f%% of their challenges, outside 40-60%%", gamblers, style, rate * 100)
        print(string.format("%d gambler(s) %-8s %6d games %.2fs  champion wins %4.1f%%  bids/challenge %.1f (max %d)",
            gamblers, style, GAMES, os.clock() - started, rate * 100, bidsTotal / challenges, maxBids))
    end
end

if failures > 0 then
    print(string.format("%d FAILURES", failures))
    os.exit(1)
end
print("ALL PASSED")
