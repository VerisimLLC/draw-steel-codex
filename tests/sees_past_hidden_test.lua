-- Run from codex root: ../dependencies/lua/bin/lua.exe tests/sees_past_hidden_test.lua
-- RuleUtils.SeesPastHidden: a creature with "Ignore Hidden Within Range" N sees a Hidden
-- creature up to N squares away, counting height the way range does.
dmhub = {GetModLoading = function() return {} end, unitsPerSquare = 5}
CreatureFilter = {Register = function() end}
GameSystem = {RegisterGoblinScriptField = function() end}
dofile("Draw Steel Core Rules/DSRuleUtils.lua")

local checks = 0
local function check(v, name) assert(v, name); checks = checks + 1 end

--A creature standing at x (in squares) and the given altitude. Distance is across only, in
--feet, like the engine's; height comes from altitude and tileSize.
local function makeToken(x, altitude, attrs, tileSize)
    local token = {valid = true, x = x, altitude = altitude or 0, tileSize = tileSize or 1}
    token.properties = {attrs = attrs or {}}
    function token.properties:CalculateNamedCustomAttribute(name) return self.attrs[name] or 0 end
    function token:Distance(other) return math.abs(self.x - other.x) * dmhub.unitsPerSquare end
    return token
end

local sensor = makeToken(0, 0, {["Ignore Hidden Within Range"] = 3})
check(RuleUtils.SeesPastHidden(sensor, makeToken(1)), "1 square away, range 3")
check(RuleUtils.SeesPastHidden(sensor, makeToken(3)), "3 squares away, range 3")
check(not RuleUtils.SeesPastHidden(sensor, makeToken(4)), "4 squares away is beyond range 3")
check(RuleUtils.SeesPastHidden(sensor, makeToken(0, 3)), "3 squares straight up, range 3")
check(not RuleUtils.SeesPastHidden(sensor, makeToken(0, 4)), "4 squares straight up is beyond range 3")
check(RuleUtils.SeesPastHidden(sensor, makeToken(2, 3)), "2 across and 3 up counts as 3")
check(not RuleUtils.SeesPastHidden(sensor, makeToken(2, 4)), "2 across and 4 up counts as 4")

--Height is measured from the top of a tall creature: a Size 2 one reaches a square higher.
local tallSensor = makeToken(0, 0, {["Ignore Hidden Within Range"] = 3}, 2)
check(RuleUtils.SeesPastHidden(tallSensor, makeToken(0, 4)), "Size 2 sensor, 4 up is a gap of 3")

check(not RuleUtils.SeesPastHidden(makeToken(0), makeToken(1)), "no range: an adjacent Hidden creature stays hidden")

print(checks .. " sees-past-hidden checks passed")
