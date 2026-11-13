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
--Mocks of real globals go through rawset so LuaLS does not retype them codex-wide.
local function stub(name, value) rawset(_G, name, value) end
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
    userid = "player",
    GetTokenById = function() return hero end,
    LookupToken = function() return hero end,
    GenerateGuid = function() nextId = nextId + 1; return tostring(nextId) end,
    --Runs until its first yield, like the engine; a suspended cast is a roll
    --still in progress on the accepting client.
    Coroutine = function(fn) assert(coroutine.resume(coroutine.create(fn))) end,
}
--The production marker writers: resolving stamps, completion, restart cleanup.
stub("g_appLaunchId", "launch-1")
stub("creature", {})
assert(load(section("DMHub Game Rules/Creature.lua",
    "function creature:CompletePendingAIActivityReaction", "--The 4th return is the reaction id")))()
props.SetAIActivityReactionResolving = creature.SetAIActivityReactionResolving
props.CompletePendingAIActivityReaction = creature.CompletePendingAIActivityReaction
props.CompleteReactionsOrphanedByRestart = creature.CompleteReactionsOrphanedByRestart
MCDMUtils = {GetStandardAbility = function()
    return {name = "End Turn Saving Throw", MakeTemporaryClone = function() return typed{} end}
end}
ActivatedAbilityInvokeAbilityBehavior = {ExecuteInvoke = function(_, ability)
    --The roll stays open until the test finishes it (OnFinishCast). Invoke runs
    --on the accepting client, so the host's CountActiveCasts never sees it.
    cast = ability
    coroutine.yield()
end}
local invokePath = "DMHub Game Rules/AbilityInvokeAbility.lua"
assert(load(section(invokePath, "function AbilityInvocation:Invoke()", "--Post a prompt card")))()
assert(load(section(invokePath, "function AbilityInvocation.PromptStandardAbility(args)")))()
--Typed invocation instances dispatch the production Invoke method.
AbilityInvocation.new = function(t) t = typed(t); t.Invoke = AbilityInvocation.Invoke; return t end
local findPending = assert(load(section("Monster AI/MonsterAIPanel.lua",
    "local function FindPendingPlayerSave(queue)", "local g_relayedTriggerWaitSeconds") .. "\nreturn FindPendingPlayerSave"))()
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
props.availableTriggers.legacy = nil

--EMHPEMCY: an accepted save whose cast never reports back must not hold the
--table forever.
MCDMUtils.GetStandardAbility = function()
    return {name = "End Turn Saving Throw", MakeTemporaryClone = function() return typed{} end}
end
local executeInvoke = ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke
ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke = function() error("cast exploded", 0) end
first = prompt()
props.availableTriggers[first].triggered = true
local ok, err = pcall(AbilityInvocation.ActivateInvocationPrompt, hero, first)
check(not ok and tostring(err):find("cast exploded", 1, true) ~= nil, "a cast error still propagates")
check(props.pendingAIActivityReactions[first].state == "completed", "a cast error releases the save wait")
ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke = executeInvoke

first = prompt()
props.availableTriggers[first].triggered = true
AbilityInvocation.ActivateInvocationPrompt(hero, first)
local marker = props.pendingAIActivityReactions[first]
check(marker.resolvingBy == "player" and marker.resolvingLaunch == "launch-1"
    and marker.resolvingSince ~= nil, "acceptance stamps who, when and which launch")
props:CompleteReactionsOrphanedByRestart()
check(marker.state == "resolving", "a cast from this launch may still be running")
props.pendingAIActivityReactions.other = {activityId = "end-turn-save", state = "resolving",
    resolvingBy = "someone-else", resolvingLaunch = "launch-0"}
props.pendingAIActivityReactions.legacy = {activityId = "end-turn-save", state = "resolving"}
stub("g_appLaunchId", "launch-2")
props:CompleteReactionsOrphanedByRestart()
check(props.pendingAIActivityReactions[first].state == "completed", "a restart clears this user's dead save")
check(props.pendingAIActivityReactions.other.state == "resolving", "another user's save is theirs to finish")
check(props.pendingAIActivityReactions.legacy.state == "resolving", "unstamped markers are left alone")
props.pendingAIActivityReactions.other = nil
props.pendingAIActivityReactions.legacy = nil

--The banner's Skip save button.
local isHost, ages = false, {}
stub("IsDMOrPlayerHost", function() return isHost end)
stub("EventTimestampAge", function(t) return ages[t] end)
local stuckSaveSkip, mayDismiss, dismissPrompt = assert(load(section("Monster AI/MonsterAI.lua",
    "local STUCK_SAVE_SKIP_SECONDS", "--The banner buttons (see")
    .. "\nreturn StuckReactionSkip, MayDismissWaitedPrompt, DismissWaitedPrompt"))()
props.pendingAIActivityReactions.stuck = {activityId = "end-turn-save", state = "resolving", resolvingSince = "t"}
local doc = {data = {key = "save", charid = "hero", triggerid = "stuck"}}
ages.t = 31
hero.canControlAsUser = false
check(stuckSaveSkip(doc, hero) == nil, "other players get no Skip")
isHost = true
ages.t = 5
check(stuckSaveSkip(doc, hero) == nil, "no Skip while the save is fresh")
ages.t = 31
props.availableTriggers.stuck = {}
check(stuckSaveSkip(doc, hero) == nil, "no Skip while the card is still there to answer")
props.availableTriggers.stuck = nil
local skip = stuckSaveSkip(doc, hero)
check(skip ~= nil and skip.text == "Skip save", "the host gets Skip on a stuck save")
check(findPending(queue) == hero, "a stuck save holds the AI until skipped")
skip.press()
check(findPending(queue) == nil, "Skip releases the AI")
isHost = false
hero.canControlAsUser = true
props.pendingAIActivityReactions.stuck = {activityId = "end-turn-save", state = "resolving", timestamp = "t"}
check(stuckSaveSkip(doc, hero) ~= nil, "the hero's controller gets Skip; old markers age from the card")
props.pendingAIActivityReactions.stuck = nil

--N4 (2026-11-09): "Waiting for Reyne's Opportunity Attack to finish" -- an
--accepted reaction still resolving -- gets the same Skip, worded for a reaction.
hero.canControlAsUser = false
props.pendingAIActivityReactions.oa = {activityId = "move:1", state = "resolving", resolvingSince = "oa"}
doc = {data = {key = "reaction", charid = "hero", triggerid = "oa"}}
ages.oa = 31
check(stuckSaveSkip(doc, hero) == nil, "other players get no Skip on a reaction")
isHost = true
ages.oa = 29
check(stuckSaveSkip(doc, hero) == nil, "no Skip while a reaction's roll is fresh")
ages.oa = 31
skip = stuckSaveSkip(doc, hero)
check(skip ~= nil and skip.text == "Stop waiting", "the host gets Stop waiting on a stuck reaction")
skip.press()
check(props.pendingAIActivityReactions.oa.state == "completed", "Stop waiting completes the marker only")
props.pendingAIActivityReactions.oa = {activityId = "move:1", state = "awaiting_choice", timestamp = "oa"}
check(stuckSaveSkip(doc, hero) == nil, "an unanswered card is not skipped; it is dismissed")
props.pendingAIActivityReactions.oa = {activityId = "turn-claim", state = "resolving", resolvingSince = "oa"}
doc = {data = {key = "turnclaim", charid = "hero", triggerid = "oa"}}
check(stuckSaveSkip(doc, hero) == nil, "turn claims keep their own capped wait")
props.pendingAIActivityReactions.oa = nil
isHost = false

--Dismiss from the banner: at once for the answering player, after a while for
--a host who is not answering.
local card = {id = "card", timestamp = "card", dismissed = false, triggered = false,
    CanDismiss = function() return true end}
ages.card = 5
check(mayDismiss(hero, card, true), "the answering player may dismiss at once")
check(not mayDismiss(hero, card, false), "other players may not dismiss")
isHost = true
check(not mayDismiss(hero, card, false), "the host waits before dismissing another's card")
ages.card = 31
check(mayDismiss(hero, card, false), "the host may dismiss a card left unanswered")
card.CanDismiss = function() return false end
check(not mayDismiss(hero, card, false), "an undismissable card stays")
card.CanDismiss = function() return true end

--The host's dismiss: the card's own client normally handles it; when that
--client is gone the host clears the card and the marker itself.
local scheduled = {}
dmhub.Schedule = function(_, fn) scheduled[#scheduled+1] = fn end
stub("AbilityKeyOfTrigger", function(t) return "name:" .. tostring(t.id) end)
stub("mod", {})
props.availableTriggers.card = card
props.pendingAIActivityReactions.card = {activityId = "turn-start:1", state = "awaiting_choice", timestamp = "card"}
dismissPrompt(hero, "card", true)
check(card.dismissed and #scheduled == 1, "host dismiss marks the card and schedules the fallback")
scheduled[1]()
check(props.availableTriggers.card == nil, "fallback clears a card no client handled")
check(props.pendingAIActivityReactions.card.state == "completed", "fallback releases the AI")
card.dismissed = false
props.availableTriggers.card = card
props.pendingAIActivityReactions.card = {activityId = "turn-start:1", state = "awaiting_choice", timestamp = "card"}
dismissPrompt(hero, "card", true)
props.availableTriggers.card = nil
props.pendingAIActivityReactions.card.state = "resolving"
scheduled[2]()
check(props.pendingAIActivityReactions.card.state == "resolving",
    "fallback leaves a dismissal its client is running (On Dismiss steps)")
card.dismissed = false
props.availableTriggers.card = card
dismissPrompt(hero, "card", false)
check(card.dismissed and #scheduled == 2, "the answering player's dismiss needs no fallback")
props.availableTriggers.card = nil
props.pendingAIActivityReactions.card = nil
isHost = false

--Drive the real background loop: a remote save holds an already selected
--monster turn, resumes after completion, and remains stoppable while waiting.
--The loop under test reads the module handle as a global here.
---@diagnostic disable-next-line: lowercase-global
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
queue.IsEntryPlayer = function(_, id) return id == "hero" end
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
