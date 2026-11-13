--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_turn_start_wait_test.lua
--The turn-start wait (PR 414 plus the 2026-11-09 review): while the AI holds a
--monster turn for its start-of-turn triggers, it answers the AI-run monsters'
--own prompts, so a Before Start of Turn prompt does not stall the full cap.
local function section(path, first, last)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    local start = assert(source:find(first, 1, true))
    local finish = last and assert(source:find(last, start + #first, true)) or #source + 1
    return source:sub(start, finish - 1)
end
local function noop(...) end
--Mocks of real globals go through rawset so LuaLS does not retype them codex-wide.
local function stub(name, value) rawset(_G, name, value) end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local now = 0
local waitingTexts = {}
local logged = {}
local MonsterAIStub = {
    active = true,
    SetWaiting = function(key) waitingTexts[#waitingTexts+1] = key end,
    ClearWaiting = noop,
}
MonsterAIStub.new = function(t)
    t = t or {}
    return setmetatable(t, {__index = MonsterAIStub})
end
function MonsterAIStub:RunYieldingFunction(fn) return pcall(fn) end
function MonsterAIStub:LogDecision(event) logged[#logged+1] = event end
function MonsterAIStub:WaitForAbilityIdle() return true end
function MonsterAIStub:WaitForActivityReactions(id) return true, id end
stub("MonsterAI", MonsterAIStub)
stub("mod", {})

local answered = {}
function MonsterAIStub:HandleAvailableTrigger(token, trigger)
    answered[#answered+1] = token.charid .. ":" .. trigger.id
    trigger.triggered = true
    if trigger.onAnswer then trigger.onAnswer() end
    return true
end

local function makeToken(charid, opts)
    local triggers = opts.triggers or {}
    local props = {minion = opts.minion or false, minionDead = false, dead = opts.dead or false}
    function props:IsDead() return self.dead end
    function props:GetAvailableTriggers() return triggers end
    return {charid = charid, valid = true, playerControlled = opts.player or false, properties = props}
end

local pending = {count = 2}
local monster = makeToken("monster", {triggers = {
    p1 = {id = "p1", triggered = false, dismissed = false,
        onAnswer = function() pending.count = pending.count - 1 end},
}})
local minion = makeToken("minion", {minion = true, triggers = {
    p2 = {id = "p2", triggered = false, dismissed = false,
        onAnswer = function() pending.count = pending.count - 1 end},
}})
local hero = makeToken("hero", {player = true, triggers = {
    p3 = {id = "p3", triggered = false, dismissed = false},
}})
local corpse = makeToken("corpse", {dead = true, triggers = {
    p4 = {id = "p4", triggered = false, dismissed = false},
}})
stub("dmhub", {allTokens = {monster, minion, hero, corpse}, Time = function() return now end})

assert(load(section("Monster AI/MonsterAI.lua",
    "function MonsterAI:AnswerMinionTriggersDuringWait", "function MonsterAI:WaitForActivityReactionsUnguarded")))()
assert(load(section("Monster AI/MonsterAI.lua",
    "local g_turnStartWaitSeconds", "function MonsterAI:MoveToken")))()

--The minion-death wait still answers minions only.
local tried = {}
MonsterAI.new{}:AnswerMinionTriggersDuringWait(tried)
check(#answered == 1 and answered[1] == "minion:p2", "the minion-death wait answers only minions")
minion.properties:GetAvailableTriggers().p2.triggered = false
pending.count = 2

--The turn-start wait answers every AI-run creature's prompt, and goes on as
--soon as the turns have all begun.
answered = {}
local ai = MonsterAI.new{}
local thread = coroutine.create(function()
    return ai:WaitForTurnStart({activityId = "turn-start:1", pending = pending})
end)
local ok, result, activity = coroutine.resume(thread)
check(ok and coroutine.status(thread) == "dead", "the wait ends once the prompts are answered")
check(result == true and activity == "turn-start:1", "then it waits on the turn's hero reactions")
check(#answered == 2, "both AI-run prompts were answered")
for _,id in ipairs(answered) do
    check(id ~= "hero:p3", "a hero's prompt is the player's to answer")
    check(id ~= "corpse:p4", "a dead creature's prompt is skipped")
end
check(#waitingTexts == 0, "no banner when the turn start was quick")

--A creature that never reports back holds the wait only up to the cap.
pending = {count = 1}
answered = {}
thread = coroutine.create(function()
    return ai:WaitForTurnStart({activityId = "turn-start:2", pending = pending})
end)
ok = coroutine.resume(thread)
check(ok and coroutine.status(thread) == "suspended", "an unfinished turn start holds the AI")
check(#answered == 0, "prompts already answered are not answered again")
now = 31
ok, result = coroutine.resume(thread)
check(ok and result == true, "the cap plays the turn anyway")
check(logged[#logged] == "TURN START WAIT TIMEOUT", "the timeout is logged")

--Stopping the AI ends the wait without playing the turn.
pending = {count = 1}
now = 0
thread = coroutine.create(function()
    return ai:WaitForTurnStart({activityId = "turn-start:3", pending = pending})
end)
coroutine.resume(thread)
MonsterAI.active = false
ok, result = coroutine.resume(thread)
check(ok and result == false, "a stopped AI does not play the turn")

print(string.format("ai_turn_start_wait_test: %d checks passed", checks))
