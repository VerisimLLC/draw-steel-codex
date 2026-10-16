--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_end_turn_save_test.lua
--Exercise the production prompt lifecycle and AI gate with a remote save cast.
local function section(path, first, last)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    local start = assert(source:find(first, 1, true))
    local finish = last and assert(source:find(last, start + #first, true)) or #source + 1
    return source:sub(start, finish - 1)
end
local function noop(...) end
local function try_get(self, key, default)
    if self[key] == nil then return default end
    return self[key]
end
local function typed(t)
    t.try_get = try_get
    t.has_key = function(self, key) return self[key] ~= nil end
    return t
end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

AbilityInvocation = {new = typed}
ActiveTrigger = {new = function(t) t.triggered = false; t.dismissed = false; t.aiActivityId = false; return t end}
MonsterAI = {TokenIsLiveCombatant = function(t) return t.valid and not t.dead end}
InitiativeQueue = {GetInitiativeId = function(t) return t.charid end}
ServerTimestamp = function() return 1 end
SerializeEventValue = function(v) return v end
DeserializeEventValue = function(v) return v end
DeepCopy = function(v) return v end
GenerateSymbols = function(v) return v end
printf = noop
table.shallow_copy = function(t) local r = {}; for k,v in pairs(t) do r[k] = v end; return r end
AbilityUtils = {ExtractAbilityParameters = noop}
local hero = {id = "hero", charid = "hero", name = "Hero", valid = true, playerControlled = true}
local props = typed{pendingAIActivityReactions = {}, availableTriggers = {}}
hero.properties = props
function hero:ModifyProperties(args) args.execute() end
function props:LookupSymbol(symbols) return symbols end
function props:GetAvailableTriggers() return self.availableTriggers end
function props:GetAvailableTriggerRecord(id) return self.availableTriggers[id] end
function props:DispatchAvailableTrigger(t) self.availableTriggers[t.id] = t end
function props:BeginPendingAIActivityReaction(activityId, id, ability)
    self.pendingAIActivityReactions[id] = {activityId = activityId, state = "awaiting_choice", ability = ability}
end
function props:SetAIActivityReactionResolving(_, id) self.pendingAIActivityReactions[id].state = "resolving" end
function props:CompletePendingAIActivityReaction(_, id) self.pendingAIActivityReactions[id].state = "completed" end
function props:ClearAvailableTrigger(args)
    local t = self.availableTriggers[args.id]
    if t and t.aiActivityId ~= false and (not t.triggered or t.dismissed) then
        self:CompletePendingAIActivityReaction(t.aiActivityId, t.id)
    end
    self.availableTriggers[args.id] = nil
end
local nextId = 0
local cast
dmhub = {
    allTokens = {hero},
    GetTokenById = function() return hero end,
    GenerateGuid = function() nextId = nextId + 1; return tostring(nextId) end,
    Coroutine = function(fn) fn() end,
}
MCDMUtils = {GetStandardAbility = function()
    return {name = "End Turn Saving Throw", MakeTemporaryClone = function() return typed{} end}
end}
ActivatedAbilityInvokeAbilityBehavior = {ExecuteInvoke = function(_, ability)
    --The cast runs on another client. No local CountActiveCasts can observe it.
    cast = ability
end}
local invokePath = "DMHub Game Rules/AbilityInvokeAbility.lua"
assert(load(section(invokePath, "function AbilityInvocation:Invoke()", "--Post a prompt card")))()
assert(load(section(invokePath, "function AbilityInvocation.PromptStandardAbility(args)")))()
--Typed invocation instances dispatch the production Invoke method.
AbilityInvocation.new = function(t) t = typed(t); t.Invoke = AbilityInvocation.Invoke; return t end
local findPending = assert(load(section("Monster AI/MonsterAIPanel.lua",
    "local function FindPendingPlayerSave(queue)", "local g_playerTurnClaimAbilities") .. "\nreturn FindPendingPlayerSave"))()
local queue = {entries = {hero = {}}}
local function prompt()
    return AbilityInvocation.PromptStandardAbility{
        token = hero, standardAbility = "End Turn Saving Throw", targeting = "self",
        hostile = true, aiActivityId = "end-turn-save",
    }
end

check(findPending(queue) == nil, "no saves must leave AI free to act")
local first, second = prompt(), prompt()
check(findPending(queue) == hero, "unanswered saves must block AI")
props.availableTriggers[first].triggered = true
AbilityInvocation.ActivateInvocationPrompt(hero, first)
check(props.availableTriggers[first] == nil, "acceptance consumes the card")
check(props.pendingAIActivityReactions[first].state == "resolving", "acceptance retains a resolving marker")
props.availableTriggers[second].dismissed = true
props:ClearAvailableTrigger{id = second}
check(findPending(queue) == hero, "remote roll must block after all cards disappear")
cast.OnFinishCast(cast, {})
check(findPending(queue) == nil, "finished roll releases the barrier")

first, second = prompt(), prompt()
props.availableTriggers[first].triggered = true
AbilityInvocation.ActivateInvocationPrompt(hero, first)
cast.OnFinishCast(cast, {})
check(findPending(queue) == hero, "finishing one save cannot release another")
props.availableTriggers[second].dismissed = true
props:ClearAvailableTrigger{id = second}
check(findPending(queue) == nil, "dismissal clears the remaining barrier")

first = prompt()
hero.dead = true
check(findPending(queue) == nil, "dead heroes do not strand initiative")
hero.dead = false
check(findPending({entries = {}}) == nil, "heroes outside initiative do not block")
hero.playerControlled = false
check(findPending(queue) == nil, "monster prompts do not block AI trigger dispatch")
hero.playerControlled = true
props.availableTriggers[first].triggered = true
MCDMUtils.GetStandardAbility = function() return nil end
AbilityInvocation.ActivateInvocationPrompt(hero, first)
check(findPending(queue) == nil, "missing ability must not strand a resolving marker")

--Older unanswered save cards still block even without a reaction marker.
props.availableTriggers.legacy = {dismissed = false, invocation = typed{standardAbility = "End Turn Saving Throw"}}
check(findPending(queue) == hero, "legacy save card must block")
props.availableTriggers.legacy.dismissed = true
check(findPending(queue) == nil, "dismissed legacy card must not block")

--Drive the real background loop: a remote save holds an already selected
--monster turn, resumes after completion, and remains stoppable while waiting.
mod = {}
ElevateToHostPermissions = noop
creature = {SetAIActivityInProgress = noop, ClearAIControl = noop}
FindPendingPlayerSave = findPending
GameHud = {BetweenTurnTransitionInProgress = function(...) return false end,
    instance = {initiativeInterface = {}}, GetTokensForInitiativeId = function(...) return {} end}
local turns = 0
local process = {}
MonsterAI.ClearWaiting = noop
MonsterAI.SetWaiting = noop
--The AI profiler is a no-op here.
MonsterAI.ProfBegin, MonsterAI.ProfEnd, MonsterAI.ProfPhaseBegin, MonsterAI.ProfPhaseEnd = noop, noop, noop, noop
MonsterAI.new = function(...)
    return {LogDecision = noop, RunYieldingFunction = function(_, fn) return pcall(fn) end,
        PlayTurnSafely = function() turns = turns + 1; process.stopRequested = true end}
end
queue.IsPlayersTurn = function() return false end
queue.CurrentInitiativeId = function() return "monster" end
queue.EntriesUnmoved = function() return {} end
dmhub.initiativeQueue = queue
local runThread = assert(load(section("Monster AI/MonsterAIPanel.lua",
    "local function MonsterAIThread(process)", "--Programmatic start/stop") .. "\nreturn MonsterAIThread"))()
props.pendingAIActivityReactions.remote = {activityId = "end-turn-save", state = "resolving"}
local thread = coroutine.create(function() runThread(process) end)
assert(coroutine.resume(thread))
assert(coroutine.resume(thread))
check(turns == 0, "AI loop must not play while a remote save resolves")
props.pendingAIActivityReactions.remote.state = "completed"
assert(coroutine.resume(thread))
check(turns == 1, "AI loop resumes after the save finishes")
assert(coroutine.resume(thread))
check(coroutine.status(thread) == "dead", "AI loop honors stop requests")
process = {}
props.pendingAIActivityReactions.remote.state = "resolving"
thread = coroutine.create(function() runThread(process) end)
assert(coroutine.resume(thread))
assert(coroutine.resume(thread))
process.stopRequested = true
assert(coroutine.resume(thread))
check(coroutine.status(thread) == "dead" and turns == 1, "stop during a save must not play a turn")
print(string.format("ai_end_turn_save_test: %d checks passed", checks))
