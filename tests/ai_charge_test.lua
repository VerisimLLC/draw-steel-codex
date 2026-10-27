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
--no zone holds the charger (the Hold directive's own checks need a map).
function MonsterAI:HoldConstrains() return false end
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

--NYQSV5BJ: a multi-target Charge strike charges once, to one shared landing.
local selectStart = assert(source:find("function MonsterAI.StrikeChargeRange", 1, true))
local selectEnd = assert(source:find("function MonsterAI:FindValidTargetsOfStrike", selectStart, true))
assert(load(source:sub(selectStart, selectEnd-1)))()
function shallow_copy_table(t) local r = {} for k,v in pairs(t) do r[k] = v end return r end
local function at(x) return {x=x, altitude=0, str="x" .. x} end
local mino = {id="mino", altitude=0, tileSize=1, loc=at(0),
    properties={GetPierceWalls=function() return false end}}
function mino:Distance(other) return math.abs(self.loc.x-other.loc.x) end
function mino:ExecuteWithTheoreticalLoc(destination, fn)
    local old = self.loc
    self.loc = destination
    fn()
    self.loc = old
end
function mino:GetLineOfSight(target) return target.blocked and 0 or 1 end
local function hero(name, x) return {charid=name, altitude=0, tileSize=1, loc=at(x)} end
local flailAndBlade = {meleeAndRanged=false,
    HasKeyword=function(_, k) return k == "Melee" or k == "Charge" or k == "Strike" end,
    GetRange=function() return 1 end, GetNumTargets=function() return 2 end}
local landingAi = setmetatable({}, {__index=MonsterAI})
function landingAi:GetMovementToken() return mino end

--Heroes on opposite sides need two landings: only one is planned.
local east, west = hero("east", 10), hero("west", -10)
local split = landingAi:SelectChargeTargets(mino, flailAndBlade,
    {{token=east, charge=at(9), edges=0}, {token=west, charge=at(-9), edges=0}})
assert(#split == 1 and split[1].charge.str == "x9", "two landings are never planned together")

--A hero next to another hero's landing joins that one charge.
local near = hero("near", 8)
local nearOwn = {token=near, charge=at(7), edges=0}
local shared = landingAi:SelectChargeTargets(mino, flailAndBlade,
    {{token=east, charge=at(9), edges=0}, nearOwn})
assert(#shared == 2, "one landing reaching both targets strikes both")
for _,target in ipairs(shared) do
    assert(target.charge.str == "x9", "every target shares the landing")
end
assert(nearOwn.charge.str == "x7", "joining a landing copies the target, leaving the planner's entry alone")

--Line of sight from the landing is required to join it.
near.blocked = true
assert(#landingAi:SelectChargeTargets(mino, flailAndBlade,
    {{token=east, charge=at(9), edges=0}, nearOwn}) == 1, "no sight from the landing, no strike")
near.blocked = nil

--A hero in reach now and one needing a charge: no charge wins the tie.
local adjacent = {token=hero("adjacent", 1), edges=0}
local mixed = landingAi:SelectChargeTargets(mino, flailAndBlade,
    {{token=east, charge=at(9), edges=0}, adjacent})
assert(#mixed == 1 and mixed[1] == adjacent and mixed[1].charge == nil, "ties keep the creature where it stands")

--A scorer can still prefer the charge.
local preferEast = landingAi:SelectChargeTargets(mino, flailAndBlade,
    {{token=east, charge=at(9), edges=0}, adjacent}, 2,
    function(t) return t.token == east and 2 or 1 end)
assert(#preferEast == 1 and preferEast[1].token == east)

--Targets that already agree, and single-target strikes, are untouched.
local agreeing = {{token=east, charge=at(9), edges=0}, {token=near, charge=at(9), edges=0}}
assert(landingAi:SelectChargeTargets(mino, flailAndBlade, agreeing) == agreeing)
local single = {{token=east, charge=at(9), edges=0}, {token=west, charge=at(-9), edges=0}}
assert(landingAi:SelectChargeTargets(mino, flailAndBlade, single, 1) == single)

--A size 2+ creature asked to move to its own square is not moved (the
--engine used to nudge it a square, which the AI then saw as a failed move).
local moveStart = assert(source:find("function MonsterAI:MoveToken", 1, true))
assert(load(source:sub(moveStart, helperStart-1)))()
local logged = {}
local moveAi = setmetatable({}, {__index=MonsterAI})
function moveAi:GetMovementToken() return mino end
function moveAi:MovementTokenIsAtLoc(_, dest) return mino.loc.str == dest.str end
function moveAi:LogDecision(event) logged[#logged+1] = event end
function MonsterAI.TokenLogName() return "mino" end
function MonsterAI.LocLogName(l) return l and l.str end
function mino:Move() error("Move must not be called for the square the creature stands on") end
local path, survived = moveAi:MoveToken(mino, at(0), {maxCost = 10000})
assert(path == nil and survived == true and moveAi._tmp_moveFailure == nil, "a cost-0 plan is not a failed move")
assert(logged[1] == "MOVEMENT SKIPPED")
print("AI charge altitude, validation, failed-route, shared landing and no-op move tests passed")
