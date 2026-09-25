--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/end_turn_cast_wait_test.lua
--The between-turn handler that keeps a hero's ended turn current while the
--casts its end-of-turn events started (Revitalizing Limerick's recovery
--prompt) are still resolving on this client.
local function section(path, first, last)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    local start = assert(source:find(first, 1, true))
    local finish = last and assert(source:find(last, start + #first, true)) or #source + 1
    return source:sub(start, finish - 1)
end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local now = 0
local activeCasts = 0
local logs = {}
dmhub = {Time = function() return now end}
ActivatedAbility = {CountActiveCasts = function() return activeCasts end}
printf = function(fmt, ...) logs[#logs+1] = string.format(fmt, ...) end
local registered = nil
GameHud = {RegisterBetweenTurnHandler = function(args) registered = args end}

assert(load(section("Draw Steel Core Rules/MCDMInitiativeBar.lua",
    "--How long the ended turn stays current", "function GameHud:NextInitiative(oncomplete)")))()

check(registered ~= nil and registered.id == "End Turn Casts", "handler registers")
check(registered.priority == 0, "handler runs before the villain-action window (priority 50)")

--Drive the wait the way RunBetweenTurnHandler does: resume, honor the yielded
--delay by advancing the fake clock.
local function drive(setup)
    local result = nil
    local co = coroutine.create(function()
        result = GameHud.WaitForEndTurnCasts({endedInitiativeId = "hero"})
    end)
    local resumes = 0
    while coroutine.status(co) ~= "dead" do
        setup(resumes)
        local ok, delay = coroutine.resume(co)
        assert(ok, delay)
        resumes = resumes + 1
        if coroutine.status(co) ~= "dead" then
            now = now + (delay or 0.1)
        end
        assert(resumes < 100000, "wait never finished")
    end
    return result, resumes
end

--No casts: released after the idle grace, not on the first reading.
activeCasts = 0
local result, resumes = drive(function() end)
check(result == true, "idle client releases the turn")
check(resumes >= 3, "idle grace covers more than a single reading")

--A live prompt cast holds the turn until it finishes.
local finishAt = 47.0
local start = now
result, resumes = drive(function()
    activeCasts = (now - start < finishAt) and 1 or 0
end)
check(result == true, "turn released once the cast finished")
check(now - start >= finishAt, "turn held while the cast was live")

--A cast that ends by immediately starting another (deferred trigger cast) must
--not slip through the single-frame gap.
start = now
result = drive(function()
    local t = now - start
    if t < 2.0 then activeCasts = 1
    elseif t < 2.1 then activeCasts = 0
    elseif t < 5.0 then activeCasts = 1
    else activeCasts = 0 end
end)
check(result == true and now - start >= 5.0, "one-frame gap between chained casts does not release the turn")

--A cast that never finishes is abandoned at the deadline with a log line.
start = now
activeCasts = 1
logs = {}
result = drive(function() end)
check(result == false, "deadline releases a stranded turn")
check(now - start >= 600 and now - start < 601, "deadline is the documented 10 minutes")
local holding, releasing = 0, 0
for _,line in ipairs(logs) do
    if line:find("holding turn hero", 1, true) then holding = holding + 1 end
    if line:find("releasing turn hero", 1, true) then releasing = releasing + 1 end
end
check(releasing == 1, "abandon is logged once")
check(holding >= 10 and holding <= 21, "stall progress is logged about every 30s, got " .. holding)

print(string.format("end_turn_cast_wait_test: %d checks passed", checks))
