-- Run from codex root: ../dependencies/lua/bin/lua.exe tests/ai_hidden_strike_square_test.lua
-- A monster that senses a Hidden enemy ("Ignore Hidden Within Range", e.g. Soulsight) only
-- plans strikes on it from squares still within that range. It never plans around a Hidden
-- enemy it cannot sense from where it stands.
dmhub = {GetModLoading = function() return {} end, unitsPerSquare = 1}
CreatureFilter = {Register = function() end}
GameSystem = {RegisterGoblinScriptField = function() end}
dofile("Draw Steel Core Rules/DSRuleUtils.lua")

--The Hidden part of the real targeting rule, using the real helper.
function GameSystem.AllowTargeting(casterToken, targetToken)
    if targetToken.properties.hidden and not RuleUtils.SeesPastHidden(casterToken, targetToken) then
        return false, "Cannot target a hidden creature with a strike", "hidden"
    end
    return true
end

local f = assert(io.open("Monster AI/MonsterAI.lua"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function extract(startText)
    local first = assert(source:find(startText, 1, true), startText)
    local last = assert(source:find("\nend\n", first, true), startText)
    return source:sub(first, last + 4)
end
MonsterAI = {}
function ProfBegin() end
function ProfEnd() end
function ProfCount() end
function MonsterAI.StrikeChargeRange(_, _, range) return range end
assert(load(extract("function MonsterAI.TargetDistance(actor, target)")))()
assert(load(extract("function MonsterAI:FindValidTargetsOfStrike(token, ability, loc, range)")))()

local checks = 0
local function check(v, name) assert(v, name); checks = checks + 1 end
local function at(x) return {x = x, str = "x" .. x} end

local function makeToken(charid, x, props)
    local token = {charid = charid, valid = true, loc = at(x), altitude = 0, tileSize = 1, properties = props}
    function props:CalculateNamedCustomAttribute(name) return (self.attrs or {})[name] or 0 end
    function props:HasNamedCondition(name) return name == "Hidden" and self.hidden == true end
    function props:GetPierceWalls() return 0 end
    function props:CurrentMovementSpeed() return 5 end
    function token:Distance(other) return math.abs(self.loc.x - other.loc.x) end
    function token:GetLineOfSight() return 1 end
    return token
end

--A melee strike with reach 5, so reach never decides these cases; Soulsight 2 does.
local strike = {name = "Soul Bite"}
function strike:HasKeyword(keyword) return keyword == "Strike" or keyword == "Melee" end
function strike:GetRange() return 5 end
function strike:try_get(_, default) return default end
function strike:TargetPassesFilter(casterToken, targetToken) return GameSystem.AllowTargeting(casterToken, targetToken, self) == true end

--Plans a strike by a Soulsight 2 monster at square 0 on a hero at heroX, from strikeX.
local function targetsWhenStrikingFrom(strikeX, heroX, heroHidden)
    local monster = makeToken("monster", 0, {attrs = {["Ignore Hidden Within Range"] = 2}})
    local hero = makeToken("hero", heroX, {hidden = heroHidden})
    local memo = {filters = {}, lineOfSight = {}}
    local ai = setmetatable({enemyTokens = {hero}, activeTactics = {}}, {__index = MonsterAI})
    function ai:PlanningMemo() return memo end
    function ai.TokenIsLiveCombatant() return true end
    function ai:GetMovementToken(token) return token end
    function ai:ExecuteWithTheoreticalMovementLoc(token, destination, fn)
        local saved = token.loc
        token.loc = destination
        local results = table.pack(fn())
        token.loc = saved
        return table.unpack(results, 1, results.n)
    end
    local result = ai:FindValidTargetsOfStrike(monster, strike, at(strikeX))
    return #result
end

check(targetsWhenStrikingFrom(0, 2, true) == 1, "hidden hero 2 away, struck from where the monster senses it")
check(targetsWhenStrikingFrom(-1, 2, true) == 0, "hidden hero 3 away from the strike square is out of Soulsight 2")
check(targetsWhenStrikingFrom(-3, 2, false) == 1, "a hero who is not hidden is struck from 5 away")
check(targetsWhenStrikingFrom(3, 4, true) == 0, "a hidden hero the monster cannot sense from its own square is never planned for")

print(checks .. " AI hidden strike-square checks passed")
