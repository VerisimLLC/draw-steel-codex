--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/trigger_range_altitude_test.lua
--A triggered action's range counts the vertical gap between the tokens, so a
--flyer 3 squares above its allies is not adjacent to them (4GURAAWK, The Pack Defends).
local function readSource(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return source
end

--the shared 3D distance helper from MCDMRules.lua.
local rules = readSource("Draw Steel Core Rules/MCDMRules.lua")
local helperStart = assert(rules:find("--Shortest 3D distance in squares between two tokens", 1, true), "TokenDistance3D comment not found")
local helperFinish = assert(rules:find("\nend\n", helperStart, true), "TokenDistance3D end not found")
local helperSource = rules:sub(helperStart, helperFinish + 4)
assert(helperSource:find("function TokenDistance3D", 1, true), "TokenDistance3D not found")
local helperChunk = helperSource .. "\nreturn TokenDistance3D\n"
local tokenDistance3D = assert(load(helperChunk))()
TokenDistance3D = tokenDistance3D

--both range checks in PowerTableTriggers.lua.
local triggers = readSource("Draw Steel Core Rules/PowerTableTriggers.lua")
local blockHead = "        if not selfIsTarget and self.range ~= \"\" then\n"
local blockTail = "\n            end\n        end\n"
local rangeChecks = {}
local pos = 1
while true do
    local s = triggers:find(blockHead, pos, true)
    if s == nil then break end
    local e = assert(triggers:find(blockTail, s, true), "range check end not found")
    local body = triggers:sub(s, e + #blockTail - 1)
    local chunk = "local self, token, triggerTarget, selfIsTarget = ...\n" .. body .. "\nreturn \"inrange\"\n"
    rangeChecks[#rangeChecks + 1] = assert(load(chunk))
    pos = e + 1
end
assert(#rangeChecks == 2, "expected 2 trigger range checks, found " .. #rangeChecks)

function ComputeTriggerRange(ability, creature) return ability.range end
function ExecuteGoblinScript(expr, symbols, default) return tonumber(expr) or default end

local function makeToken(x, y, altitude)
    local token = {x = x, y = y, floorAltitude = altitude, tileSize = 1, properties = {LookupSymbol = function() return {} end}}
    --CharacterToken:Distance is horizontal only (TileUtils.DistanceBetween on tile locs).
    function token:Distance(other)
        return math.max(math.abs(self.x - other.x), math.abs(self.y - other.y))
    end
    return token
end

local packDefends = {range = "1"}

local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end

for i, rangeCheck in ipairs(rangeChecks) do
    local ground = makeToken(0, 0, 0)
    local beside = makeToken(1, 0, 0)
    local flyerAbove = makeToken(0, 0, 3)
    local flyerOneUp = makeToken(1, 0, 1)
    local far = makeToken(3, 0, 0)

    check(rangeCheck(packDefends, beside, ground, false) == "inrange",
        "range check " .. i .. ": an ally beside on the ground is in range 1")
    check(rangeCheck(packDefends, flyerOneUp, ground, false) == "inrange",
        "range check " .. i .. ": a flyer diagonally one square up is in range 1")
    check(rangeCheck(packDefends, flyerAbove, ground, false) ~= "inrange",
        "range check " .. i .. ": a flyer 3 squares above (2 square gap) must be out of range 1")
    check(rangeCheck(packDefends, ground, flyerAbove, false) ~= "inrange",
        "range check " .. i .. ": a target 3 squares above must be out of range 1")
    check(rangeCheck(packDefends, far, ground, false) ~= "inrange",
        "range check " .. i .. ": a token 3 squares away on the ground is out of range 1")
    check(rangeCheck({range = "3"}, flyerAbove, ground, false) == "inrange",
        "range check " .. i .. ": a flyer 3 squares up is in range 3")
end

print("trigger_range_altitude: " .. checks .. " checks passed")
