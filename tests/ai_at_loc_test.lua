-- Run from codex root: ../dependencies/lua/bin/lua.exe tests/ai_at_loc_test.lua
local file = assert(io.open("Monster AI/MonsterAI.lua"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local first = assert(source:find("function MonsterAI:MovementTokenIsAtLoc", 1, true))
local last = assert(source:find("\nend\n", first, true))
--Load the function into a private table, not the global MonsterAI, so running
--this file inside DMHub cannot overwrite the real AI.
local env = {MonsterAI = {}}
assert(load(source:sub(first, last + #"\nend"), "MovementTokenIsAtLoc", "t", env))()

--Engine Loc strings look like "x,y,floor", then ":altitude" when not 0, then "|slot" for a Tiny slot.
local function loc(x, y, floor, altitude, slot)
    local base = x .. "," .. y .. "," .. floor
    local str = base
    if altitude ~= 0 then str = str .. ":" .. altitude end
    if slot ~= nil then str = str .. "|" .. slot end
    return {str = str, altitude = altitude, xyfloorOnly = {str = base}}
end

local mover = {}
local ai = setmetatable({}, {__index = env.MonsterAI})
--Stands in for GetMovementToken: a rider moves with its mount, anyone else moves alone.
function ai:GetMovementToken(token) return token.mount or token end

--A size 2 charger tagged with a Tiny slot on landing is still on its landing square.
mover.loc = loc(0, 19, 1, 0, 4)
assert(ai:MovementTokenIsAtLoc(mover, loc(0, 19, 1, 0)), "Tiny slot tag made a correct landing look missed")

assert(not ai:MovementTokenIsAtLoc(mover, loc(0, 18, 1, 0)), "a different square is not the destination")
assert(not ai:MovementTokenIsAtLoc(mover, loc(0, 19, 2, 0)), "a different floor is not the destination")
assert(not ai:MovementTokenIsAtLoc(mover, loc(0, 19, 1, -1)), "a different altitude is not the destination")
assert(not ai:MovementTokenIsAtLoc(mover, nil), "a nil destination is never reached")

mover.loc = loc(-2, 17, 1, -1)
assert(ai:MovementTokenIsAtLoc(mover, loc(-2, 17, 1, -1)), "the same square below ground level is the destination")

--A rider is judged by where its mount stands, not by its own loc.
local rider = {loc = loc(9, 9, 1, 0), mount = mover}
assert(ai:MovementTokenIsAtLoc(rider, loc(-2, 17, 1, -1)), "a rider has arrived when its mount has")
assert(not ai:MovementTokenIsAtLoc(rider, loc(9, 9, 1, 0)), "a rider's own loc does not count")

--A Tiny creature in another slot of the planned square has still arrived.
mover.loc = loc(3, 3, 1, 0, 2)
assert(ai:MovementTokenIsAtLoc(mover, loc(3, 3, 1, 0, 1)), "a different Tiny slot in the same square is the destination")
assert(ai:MovementTokenIsAtLoc(mover, loc(3, 3, 1, 0)), "a slotted loc matches a planned loc without a slot")

print("ai_at_loc_test: OK")
