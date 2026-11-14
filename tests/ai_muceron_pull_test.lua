-- Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_muceron_pull_test.lua
-- The Demon Muceron with no enemy in Barbed Tongues' reach walks to where
-- Tongue Pull catches two or more, pulls them, then lashes one it pulled.
local f = assert(io.open("Monster AI/MonsterAIDemons.lua"))
local source = f:read("*a"):gsub("\r\n", "\n")
f:close()
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    return source:sub(start, assert(source:find(last, start + #first, true)) - 1)
end

--Utils.lua's table helper.
function table.resize_array(t, n)
    for i=#t,n+1,-1 do t[i] = nil end
end
local moves = {}
local barbedPlan = nil
local enemies = {}
local log = {}
MonsterAI = {
    RegisterMove = function(_, entry) moves[entry.id] = entry end,
    RegisterPrompt = function() end,
    PlanStrikeFromRange = function() return barbedPlan end,
}
function MonsterAI.TargetDistance(actor, target)
    return actor:Distance(target)
end

local stubs = [[
local tongueMinimumTargets = 2
local abilityPause = 0
local function cond(a, b, c) if a then return b end return c end
local function LiveCreature(t) return t ~= nil and t.valid and not t.dead end
local function CanSee() return true end
local function AdjacentEnemiesAt() return 0 end
local function LocKey(loc) return loc.str end
local function AllFleshSquares() return {} end
local function Speak() end
local function TokenTargets(tokens)
    local result = {}
    for _,tok in ipairs(tokens) do result[#result+1] = {token = tok} end
    return result
end
local function DefaultTargetScore(t) return 1 + (t.stamina or 0)*0.01 end
local function SortedStrikeTargets() return {} end
local function TargetsOfRunningCast() return {} end
local function DemonAllies() return {} end
local function FreeStrikeAt() return nil end
local HostileCreatures, MoveCinematically = ...
]]
local function HostileCreatures() return enemies end
local function MoveCinematically(_, token, loc)
    log[#log+1] = "move " .. loc.str
    token.loc = loc
end
assert(load(stubs .. section("-- Muceron: Barbed Tongues and Tongue Pull.", "-- Chorogaunt.")))(
    HostileCreatures, MoveCinematically)

local function loc(x, y) return {x = x, y = y, str = x .. "," .. y} end
local function Distance(self, other)
    local at = other.loc or other
    return math.max(math.abs(self.loc.x - at.x), math.abs(self.loc.y - at.y))
end
local function creature(name, x, y, stamina)
    return {name = name, charid = name, valid = true, altitude = 0, tileSize = 1,
        loc = loc(x, y), stamina = stamina, Distance = Distance}
end

local muceron = creature("muceron", 0, 0)
local pull = {name = "Tongue Pull",
    GetRange = function() return 5 end,
    GetNumTargets = function() return 3 end,
    TargetPassesFilter = function() return true end}
local strike = {name = "Barbed Tongues"}
local ai = {paths = {
    {loc = loc(0, 0), cost = 0},
    {loc = loc(3, 0), cost = 30},
    {loc = loc(6, 0), cost = 60},
}}
function ai:ExecuteWithTheoreticalMovementLoc(token, at, fn)
    local old = token.loc; token.loc = at
    fn(); token.loc = old
end

local move = assert(moves["Demon Muceron: Tongue Pull then Barbed Tongues"], "the pull-first move is registered")
local hero1, hero2 = creature("hero1", 10, 0, 10), creature("hero2", 10, 2, 10)
enemies = {hero1, hero2, creature("far", 30, 0, 10)}

-- Scoring: the square at (6,0) is the only one with two heroes in pull range.
local plan = move.score(move, ai, muceron, pull, strike)
assert(plan ~= nil, "a pull-first plan is found")
assert(plan.loc.str == "6,0", "moves to the square that pulls two heroes")
assert(#plan.targets == 2, "plans to pull both heroes")
assert(plan.score > 0.2, "beats the generic free strikes")
assert(muceron.loc.str == "0,0", "scoring leaves the muceron where it is")

-- Barbed Tongues already reaches someone: the strike-first line handles it.
barbedPlan = {loc = loc(3, 0), target = hero1, score = 1}
local none, reason = move.score(move, ai, muceron, pull, strike)
assert(none == nil and reason:find("already reaches"), "not used when the strike is available")
barbedPlan = nil

-- Only one hero within pull range of any square: not worth the Malice.
enemies = {hero1, creature("far", 30, 0, 10)}
assert(move.score(move, ai, muceron, pull, strike) == nil, "needs at least two enemies to pull")
enemies = {hero1, hero2, creature("far", 30, 0, 10)}

-- Execution: move, pull both heroes, then lash a pulled hero (not a bystander
-- that happens to be in reach, even one the default scorer prefers).
local decoy = creature("decoy", 7, 1, 50)
function ai:ExecuteAbility(token, ability, targets)
    local names = {}
    for _,t in ipairs(targets) do names[#names+1] = t.token.name end
    log[#log+1] = ability.name .. ": " .. table.concat(names, ",")
    if ability == pull then
        for _,t in ipairs(targets) do t.token.loc = loc(token.loc.x + 1, token.loc.y) end
    end
end
function ai:FindValidTargetsOfStrike(token, ability, at)
    assert(ability == strike)
    return {{token = decoy, edges = 0}, {token = hero2, edges = 0}}
end
move.execute(move, ai, muceron, plan, pull, strike)
assert(log[1] == "move 6,0", "moves first: " .. tostring(log[1]))
assert(log[2] == "Tongue Pull: hero1,hero2" or log[2] == "Tongue Pull: hero2,hero1", "pulls both: " .. tostring(log[2]))
assert(log[3] == "Barbed Tongues: hero2", "then lashes a pulled hero: " .. tostring(log[3]))
assert(#log == 3, "nothing else happens")

print("Muceron Tongue Pull then Barbed Tongues tests passed")
