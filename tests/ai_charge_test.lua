-- Run from codex root: ../dependencies/lua/bin/lua.exe tests/ai_charge_test.lua
local f = assert(io.open("Monster AI/MonsterAI.lua"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local first = assert(source:find("function MonsterAI:ChargeProbe", 1, true))
local last = assert(source:find("function MonsterAI:LeapProbe", first, true))
MonsterAI = {}
--The AI profiler's file locals are no-ops here.
local function noop() end
ProfBegin, ProfEnd, ProfCount, ProfPhaseBegin, ProfPhaseEnd, ProfRequestReport = noop, noop, noop, noop, noop, noop
local helperStart = assert(source:find("function MonsterAI.TargetDistance", 1, true))
local helperEnd = assert(source:find("function MonsterAI:MovementTokenIsAtLoc", helperStart, true))
assert(load(source:sub(helperStart, helperEnd-1)))()
dmhub = {unitsPerSquare=1, Time = function() return 1 end, CreateChargeRouteCache = function() return {} end}
assert(load(source:sub(first, last-1)))()
local function loc(x, altitude)
    return {x=x, altitude=altitude, str=x .. ":" .. altitude,
        DistanceInTiles=function(self, other) return math.abs(self.x-other.x) end}
end
local origin, ground, relative = loc(0,2), loc(2,2), loc(2,0)
local mover = {id="goblin", altitude=2, tileSize=1, loc=origin, creatureDimensions={x=1},
    properties={CurrentMovementSpeed=function() return 6 end}}
local enemy = {id="enemy", altitude=2, tileSize=1, loc=loc(3,2), Distance=function(_, other) return math.abs(3-other.x) end}
function enemy.loc:LocsInRadius() return {ground} end
function mover:Distance(other) return math.abs(self.loc.x-other.loc.x) end
function mover:ExecuteWithTheoreticalLoc(destination, fn)
    local old, alt = self.loc, self.altitude
    self.loc, self.altitude = destination, destination.altitude
    fn()
    self.loc, self.altitude = old, alt
end
local mode = "legal"
function mover:PlanCharge(dest, options)
    assert(options.chargeJumpDistance == 0 and options.chargeDistance == 6)
    if mode == "blocked" then return nil end
    return {validCharge=true, requiresRoll=mode == "rolled", path={destination=ground,cost=20},
        chargeSegments={{loc=relative,expectedLoc=ground,jump=false}}}
end
--The engine plans no-jump routes only, so a roll-dependent route never comes back.
function mover:FindChargeRoutes(target, radius, range, distance, cache)
    assert(target == enemy and radius == 2 and range == 1 and distance == 6 and cache ~= nil)
    if mode == "blocked" or mode == "rolled" then return {} end
    return {{dest=ground, cost=20}}
end
local ai = setmetatable({}, {__index=MonsterAI})
function ai:try_get(k, default) if self[k] == nil then return default end return self[k] end
function ai:GetMovementToken() return mover end
function ai:MovementTokenIsAtLoc(_, dest) return mover.loc.str == dest.str end
function ai:MoveToken(_, dest, options)
    assert(dest.altitude == 0, "straight-line execution needs relative altitude, not ground altitude")
    assert(options.straightline and options.movementType == "walk" and options.freeMovement)
    assert(options.moveThroughFriends == false)
    if mode == "no path" then return nil, true end
    if mode == "short" then return {}, true end
    mover.loc=ground
    return {}, true
end
assert(ai:ChargeProbe(mover, enemy, 6, 1).dest == ground, "keep absolute elevated landing for validation")
assert(ai:ExecuteChargeMovement(mover, ground), "execute elevated charge")
assert(ai._tmp_moveFailure == nil)
mover.loc=origin
for _,blocked in ipairs({"blocked", "rolled"}) do
    mode=blocked; ai:InvalidatePlanningMemo()
    assert(ai:ChargeProbe(mover,enemy,6,1) == nil, "reject blocked or roll-dependent route")
end
for _,failure in ipairs({"no path", "short"}) do
    mode=failure; ai._tmp_failedChargePlans={}; ai._tmp_moveFailure=nil
    assert(not ai:ExecuteChargeMovement(mover,ground), "failed movement cannot authorize an attack")
    assert(ai._tmp_moveFailure ~= nil)
    mode="legal"
    assert(ai:ChargeProbe(mover,enemy,6,1) == nil, "same route excluded even for another strike registration")
end
mode="legal"; ai._tmp_failedChargePlans={}; ai:InvalidatePlanningMemo()
enemy.altitude=7
assert(ai:ChargeProbe(mover,enemy,6,1) == nil, "ground charge cannot reach flying enemy")
enemy.altitude=3; ai:InvalidatePlanningMemo()
assert(ai:ChargeProbe(mover,enemy,6,1), "charge permits one-square vertical diagonal")
print("AI charge altitude, validation, and failed-route tests passed")
