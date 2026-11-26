--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/trigger_prompt_turn_life_test.lua
--Hero trigger prompts and the turn passing (playtest 2026-11-23 N12): ending a
--turn does not wait for them, they live through the next turn (2026-11-05 N4), a
--turn claim waits for the ended turn to pass (AH6SYXTP), and the Monster AI
--waits for open ones.
local function section(path, first, last)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    local start = assert(source:find(first, 1, true), first)
    local finish = assert(source:find(last, start + #first, true), last)
    return source:sub(start, finish - 1)
end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

--Globals the code under test reads, set through rawset so LuaLS does not take
--these stubs for more definitions of the real globals.
local function stub(name, value) rawset(_G, name, value) end
local function noop(...) end
local function try_get(self, key, default)
    local v = self[key]
    if v == nil then return default end
    return v
end

local now = 0
local logs = {}
stub("printf", function(fmt, ...) logs[#logs+1] = string.format(fmt, ...) end)

--A combat with two heroes, the Shadow and a monster group.
local function Queue(guid)
    local q = {guid = guid, hidden = false, currentTurn = false, turnNumber = 0, round = 1, try_get = try_get,
        entries = {tjarra = {}, bob = {}, shadow = {}, orcs = {}}}
    function q:ChoosingTurn() return self.currentTurn == false end
    function q:IsEntryPlayer(id) return id ~= "orcs" end
    function q:Start(id) self.currentTurn = id; self.turnNumber = self.turnNumber + 1 end
    function q:Pass() self.currentTurn = false end
    function q:Cancel() self.currentTurn = false; self.turnNumber = self.turnNumber - 1 end
    function q:NextTurn(id) self.passed = id; self:Pass(); return false end
    return q
end
local queue = Queue("combat-1")
stub("InitiativeQueue", {
    GetInitiativeId = function(token) return token.id end,
    SetTurnTaken = function(q, entry) entry.taken = true end,
})

local function Token(id, playerControlled)
    local props = {try_get = try_get, availableTriggers = {}, triggeredEvents = {}}
    function props:GetResourceRefreshId()
        local q = rawget(_G, "dmhub").initiativeQueue
        return q ~= nil and tostring(q.currentTurn) or "none"
    end
    function props:GetAvailableTriggers() return self.availableTriggers end
    function props:TurnClaimResolving() return self.resolving end
    function props:IsTurnSkipped() return false end
    function props:EndTurn() self.ended = true end
    return {id = id, charid = id, name = id, valid = true, playerControlled = playerControlled, properties = props}
end
local tjarra, bob, shadow, orc = Token("tjarra", true), Token("bob", true), Token("shadow", true), Token("orcs", false)
local dmhubStub = {Time = function() return now end, allTokens = {tjarra, bob, shadow, orc}, initiativeQueue = queue}
stub("dmhub", dmhubStub)

stub("TriggeredAbility", {try_get = try_get})
assert(load(section("DMHub Game Rules/TriggeredAbility.lua",
    "--Seconds a prompt stays up once the turn it belonged to has passed", "--The sustain coroutines below register")))()
local TA = rawget(_G, "TriggeredAbility")

local function Reset()
    queue = Queue("combat-1")
    dmhubStub.initiativeQueue = queue
    logs = {}
    now = 0
end

-- How long a prompt lives --------------------------------------------------

--2026-11-05 N4: Mark raised on Tjarra's turn, Tjarra ends it, Bob starts theirs.
Reset()
queue:Start("tjarra")
local watch = TA.PromptTurnWatch(shadow, false, nil)
check(watch() == nil, "alive in the turn that raised it")
queue:Pass()
check(watch() == nil, "alive while the next turn is chosen")
queue:Start("bob")
check(watch() == nil, "alive when another hero starts their turn")
check(watch() == nil, "alive for the rest of that turn")
queue:Pass()
local left, reason = watch()
check(left == 0 and reason == "the turn after it ended", "ends when the next turn ends")

--The same through a monster's turn.
Reset()
queue:Start("tjarra")
watch = TA.PromptTurnWatch(shadow, false, nil)
queue:Pass()
queue:Start("orcs")
check(watch() == nil, "alive through a monster's turn")
--A claim can replace the current turn with no choosing between.
queue:Start("bob")
check(watch() == 0, "ends when that turn gives way to another")

--Raised between turns (Begin Round, a villain action).
Reset()
watch = TA.PromptTurnWatch(shadow, false, nil)
check(watch() == nil, "alive while choosing")
queue:Start("orcs")
check(watch() == nil, "alive through the first turn after it")
queue:Pass()
check(watch() == 0, "ends with that turn")

--A cancelled turn is not a turn taken.
Reset()
queue:Start("tjarra")
watch = TA.PromptTurnWatch(shadow, false, nil)
queue:Pass()
queue:Start("bob")
watch()
queue:Cancel()
check(watch() == nil, "cancelling the next turn does not end it")
queue:Start("orcs")
check(watch() == nil, "the turn taken instead is the next turn")
queue:Pass()
check(watch() == 0, "and it ends with that one")

--The next turn can be the same creature's again (two turns a round).
Reset()
queue:Start("tjarra")
watch = TA.PromptTurnWatch(shadow, false, nil)
queue:Pass()
queue:Start("tjarra")
watch()
queue:Pass()
check(watch() == 0, "a second turn of the same creature counts as the next turn")

--A reconnect rebuilds the queue as a new object for the same combat (SASGFH6V).
Reset()
queue:Start("tjarra")
watch = TA.PromptTurnWatch(shadow, false, nil)
local rebuilt = Queue("combat-1")
rebuilt.currentTurn, rebuilt.turnNumber = "tjarra", 1
dmhubStub.initiativeQueue = rebuilt
check(watch() == nil, "a rebuilt queue is the same turn")

--Combat over, or another combat.
rebuilt.hidden = true
left, reason = watch()
check(left == 6 and reason == "combat ended; 6s grace elapsed", "6s once combat ends")
dmhubStub.initiativeQueue = Queue("combat-2")
check(watch() == 6, "6s once another combat starts")

--A party hero that is not playerControlled is a hero through its entry.
Reset()
queue:Start("tjarra")
bob.playerControlled = false
watch = TA.PromptTurnWatch(bob, false, nil)
queue:Pass()
queue:Start("shadow")
check(watch() == nil, "party hero follows the hero rule")
bob.playerControlled = true

--A monster's prompt keeps the 6s rule.
Reset()
queue:Start("tjarra")
watch = TA.PromptTurnWatch(orc, false, nil)
queue:Pass()
check(watch() == nil, "monster prompt alive while choosing")
queue:Start("bob")
check(watch() == 6, "monster prompt gets 6s once another turn starts")

-- Turn claims (Hesitation is Weakness) --------------------------------------

local function Ability(fields)
    return setmetatable(fields, {__index = TA})
end
local begin = {typeName = "ActivatedAbilityInitiativeBehavior", try_get = try_get}
local speech = {typeName = "ActivatedAbilityCharacterSpeechBehavior", try_get = try_get}
check(Ability{trigger = "endturn", behaviors = {begin, speech}}:ClaimsTurnAtTurnEnd(), "endturn + Begin Turn claims")
check(not Ability{trigger = "endturn", behaviors = {speech}}:ClaimsTurnAtTurnEnd(), "no initiative behavior, no claim")
check(not Ability{trigger = "dealdamage", behaviors = {begin}}:ClaimsTurnAtTurnEnd(), "other triggers are not end-of-turn claims")
local priority = {typeName = "ActivatedAbilityInitiativeBehavior", mode = "set_priority", try_get = try_get}
check(not Ability{trigger = "endturn", behaviors = {priority}}:ClaimsTurnAtTurnEnd(), "Set Priority is not a claim")

Reset()
queue:Start("tjarra")
watch = TA.PromptTurnWatch(shadow, true, tjarra)
check(watch() == nil, "claim card alive while the ended turn is passing")
queue:Pass()
check(watch() == nil, "claim card alive while choosing, so the Monster AI waits on it")
queue:Start("bob")
left, reason = watch()
check(left == 0 and reason == "another turn started", "claim card ends when another hero starts")
check(TA.WaitToClaimTurn(watch) == false, "an accept that late does not steal the turn")

--The relayed event reached the Shadow's client after the next turn had started.
Reset()
queue:Start("bob")
watch = TA.PromptTurnWatch(shadow, true, tjarra)
check(watch() == 0, "a claim raised too late ends at once")

local function drive(setup)
    local result = nil
    local co = coroutine.create(function() result = TA.WaitToClaimTurn(watch) end)
    local resumes = 0
    while coroutine.status(co) ~= "dead" do
        setup(resumes)
        local ok, delay = coroutine.resume(co)
        assert(ok, delay)
        resumes = resumes + 1
        if coroutine.status(co) ~= "dead" then now = now + (delay or 0.1) end
        assert(resumes < 100000, "wait never finished")
    end
    return result, resumes
end

--Accepted after the turn passed: at once.
Reset()
queue:Start("tjarra")
watch = TA.PromptTurnWatch(shadow, true, tjarra)
queue:Pass()
local result, resumes = drive(noop)
check(result == true and resumes == 1, "claims at once when the turn has passed")

--Accepted while the ending client is still handing off (AH6SYXTP): waits for it.
Reset()
queue:Start("tjarra")
watch = TA.PromptTurnWatch(shadow, true, tjarra)
local claimedWhile = nil
result = drive(function(n)
    if n == 20 then queue:Pass() end
    claimedWhile = queue.currentTurn
end)
check(result == true and claimedWhile == false, "claims only once the ended turn has passed")
check(now >= 1.9, "waited for it")

--Someone else starts before the claim lands.
Reset()
queue:Start("tjarra")
watch = TA.PromptTurnWatch(shadow, true, tjarra)
result = drive(function(n)
    if n == 5 then queue:Pass(); queue:Start("bob") end
end)
check(result == false, "gives way to a turn that started first")

--The ending client never passes the turn.
Reset()
queue:Start("tjarra")
watch = TA.PromptTurnWatch(shadow, true, tjarra)
result = drive(noop)
check(result == true and now >= 45 and now < 46, "claims anyway after 45s, inside the 60s turn-claim marker")
check(#logs == 1 and logs[1]:find("TURNCLAIM::", 1, true) ~= nil, "and says so")

-- The turn passes with a prompt open ---------------------------------------

Reset()
local registered = {}
local hud = {
    RegisterBetweenTurnHandler = function(args) registered[args.id] = args end,
    initiativeInterface = {initiativeQueue = queue},
    choiceInitiativeBar = {FireEvent = noop},
    currentInitiativeId = "tjarra",
    has_key = function(self, key) return self[key] ~= nil end,
    GetTokensForInitiativeId = function() return {tjarra} end,
    NewRound = noop,
}
stub("GameHud", hud)
stub("ActivatedAbility", {CountActiveCasts = function() return 0 end})
stub("DrawSteelActionBar", nil)
---@type thread
local transition = coroutine.create(noop)
dmhubStub.Coroutine = function(fn) transition = coroutine.create(fn) end
assert(load("local g_betweenTurnHandlers = {}\nlocal g_betweenTurnTransitionInProgress = false\n"
    .. section("Draw Steel Core Rules/MCDMInitiativeBar.lua",
        "local function RunBetweenTurnHandler", "local g_beginRoundStyles")
    .. "\nfunction GameHud.TestHandlers(list) for id,h in pairs(list) do g_betweenTurnHandlers[id] = h end end"))()

local ids = {}
for id,_ in pairs(registered) do ids[#ids+1] = id end
check(#ids == 1 and ids[1] == "End Turn Casts", "End Turn Casts is the only hold on a turn ending")
hud.TestHandlers(registered)

local function runTransition(setup)
    local start = now
    local n = 0
    while coroutine.status(transition) ~= "dead" do
        if setup ~= nil then setup(n) end
        local ok, delay = coroutine.resume(transition)
        assert(ok, delay)
        n = n + 1
        if coroutine.status(transition) ~= "dead" then now = now + (delay or 0.1) end
        assert(n < 10000, "transition never finished")
    end
    return now - start
end

local card = {triggered = false, dismissed = false, abilityName = "Hesitation is Weakness", try_get = try_get}
shadow.properties.availableTriggers = {card = card}
queue:Start("tjarra")
hud:NextInitiative()
local took = runTransition()
check(tjarra.properties.ended == true, "end-of-turn events fired")
check(queue.passed == "tjarra" and queue:ChoosingTurn(), "the turn passes with a hero prompt open")
check(took < 1, "and at once, took " .. tostring(took))

--A claim that landed during the handoff is left alone (KC6TUXEY).
queue.passed = nil
queue:Start("tjarra")
hud:NextInitiative()
runTransition(function(n) if n == 2 then queue:Start("shadow") end end)
check(queue.passed == nil and queue.currentTurn == "shadow" and queue.entries.tjarra.taken, "a claimed turn is not passed on")

--A reconnect during the handoff rebuilds the queue; that one advances (SASGFH6V).
queue:Start("tjarra")
rebuilt = Queue("combat-1")
rebuilt:Start("tjarra")
hud:NextInitiative()
runTransition(function(n) if n == 2 then dmhubStub.initiativeQueue = rebuilt end end)
check(rebuilt.passed == "tjarra" and queue.passed == nil, "the rebuilt queue advances")
check(hud.LiveInitiativeQueue(queue) == rebuilt, "same guid matches the rebuilt queue")
check(hud.LiveInitiativeQueue(Queue(nil)) == nil, "a queue with no guid matches only itself")
dmhubStub.initiativeQueue = Queue("combat-2")
check(hud.LiveInitiativeQueue(queue) == nil, "another combat does not match")
dmhubStub.initiativeQueue = nil
check(hud.LiveInitiativeQueue(queue) == nil, "no initiative matches nothing")

-- The Monster AI waits for it ----------------------------------------------

Reset()
stub("MonsterAI", {TokenIsLiveCombatant = function(token) return token.valid end})
stub("TimestampAgeInSeconds", function(t) return now - t end)
local findPending = assert(load(section("Monster AI/MonsterAIPanel.lua",
    "--Seconds a relayed trigger event may hold the monsters", "--The banner text for a FindPendingPlayerTrigger result")
    .. "\nreturn FindPendingPlayerTrigger"))()

local token, trigger = findPending(queue)
check(token == shadow and trigger == card, "an open hero card holds the monsters")
card.dismissed = true
check(findPending(queue) == nil, "dismissing it releases them")
shadow.properties.availableTriggers = {}
shadow.properties.resolving = "Hesitation is Weakness"
local resolving
token, trigger, resolving = findPending(queue)
check(token == shadow and trigger == nil and resolving == "Hesitation is Weakness", "an accepted claim holds them until it lands")
shadow.properties.resolving = nil
shadow.properties.triggeredEvents = {e1 = {userid = "player", timestamp = now}}
check(findPending(queue) == shadow, "a relayed event the hero's client has not evaluated holds them")
now = now + 11
check(findPending(queue) == nil, "but not for long")

io.write(string.format("trigger_prompt_turn_life_test: %d checks passed\n", checks))
