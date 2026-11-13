-- Run from codex root: ../dependencies/lua/bin/lua.exe tests/ai_overlap_altitude_test.lua
-- MonsterAI:MovementLocOverlapsCreature must see a creature down in a pit when the
-- move's loc says "on the ground" with altitude 0 (PJFTCBSE: a charge landed on one).
local f = assert(io.open("Monster AI/MonsterAI.lua"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    return source:sub(start, assert(source:find(last, start + #first, true)) - 1)
end
MonsterAI = {}
local tokensAt = {}
dmhub = {GetTokensAtLoc = function(loc) return tokensAt[loc.x] end}
assert(load(section("function MonsterAI:MovementLocOverlapsCreature", "--Monster AI zone directives")))()

local groundAt = {[0] = 0, [1] = -1, [2] = 3}
local function Loc(x, altitude)
    local loc = {x = x, altitude = altitude, str = x .. ":" .. altitude}
    loc.withGroundAltitude = {altitude = groundAt[x]}
    return loc
end
local function token(id, x, altitude)
    return {valid = true, charid = id, loc = Loc(x, altitude), altitude = altitude, tileSize = 1,
        properties = {IsDead = function() return false end},
        LocsOccupyingWhenAt = function(self, loc) return {loc} end}
end

local ai = setmetatable({}, {__index = MonsterAI})
function ai:GetMovementToken(t) return t end
local mover = token("mover", 0, 0)
local hero = token("hero", 1, -1)
tokensAt[1] = {hero}

local function check(cond, msg) assert(cond, msg) end
check(ai:MovementLocOverlapsCreature(mover, Loc(1, 0)), "ground-relative 0 over a pit sees the creature in it")
check(ai:MovementLocOverlapsCreature(mover, Loc(1, -1)), "absolute pit-floor loc sees it too")
check(not ai:MovementLocOverlapsCreature(mover, Loc(1, 3)), "a flier passing well above does not overlap")
tokensAt[1] = {token("flier", 1, 5)}
check(not ai:MovementLocOverlapsCreature(mover, Loc(1, 0)), "a creature flying high above the pit is not in the way")
local ledge = token("ledge", 2, 3)
tokensAt[2] = {ledge}
check(ai:MovementLocOverlapsCreature(mover, Loc(2, 0)), "ground-relative 0 on raised ground sees the creature on it")
check(ai:MovementLocOverlapsCreature(mover, Loc(2, 3)), "absolute raised-ground loc sees it")
print("ai_overlap_altitude_test: 6 checks passed")
