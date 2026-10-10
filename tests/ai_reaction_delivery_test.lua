--Run from C:/dev/dmhub: dependencies/lua/bin/lua.exe draw-steel-codex/tests/ai_reaction_delivery_test.lua
--Exercise the production protocol with independent host/player snapshots and
--a controllable transport. The scalar codec stands in for the engine's JSON API.
--Snapshots cross the transport the way the server stores them: a
--ServerTimestamp() placeholder on a property leaf resolves to the clock.
local now = 0
local placeholder = "__serverTimestamp"
local function clone(v)
    if v == placeholder then return now*1000 end
    if type(v) ~= "table" then return v end
    local result = {}
    for k,x in pairs(v) do result[k] = clone(x) end
    return result
end
local function encode(v)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    local keys, result = {}, {}
    for k in pairs(v) do keys[#keys+1] = k end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    for _,k in ipairs(keys) do result[#result+1] = "[" .. encode(k) .. "]=" .. encode(v[k]) end
    return "{" .. table.concat(result, ",") .. "}"
end
local function decode(v)
    local fn = load("return " .. v, "message", "t", {})
    if fn == nil then return {success = false} end
    local ok, result = pcall(fn)
    return {success = ok, result = result}
end
--The same suite can run in an isolated engine environment with its actual JSON
--codec. All tokens, transport, and UI remain test doubles in either environment.
--AIReactionTestJSON is injected only by the isolated engine harness; absent under plain lua.exe.
---@diagnostic disable-next-line: undefined-global
if AIReactionTestJSON then encode=AIReactionTestJSON.encode; decode=AIReactionTestJSON.decode end
local serial = 0
dmhub = {userid = "host", ToJson = encode, FromJson = decode, Time = function() return now end,
    LookupTokenId = function() return nil end, LookupToken = function(p) return p.token end,
    GetCharacterById = function(id) return {properties={charid=id}} end,
    GenerateGuid = function() serial = serial + 1; return "event-" .. serial end}
--ServerTimestamp() is a placeholder the server resolves only on property
--leaves. The plain leaves this suite writes are modeled as already resolved,
--but a placeholder inside a JSON-encoded record would never be resolved, so
--the codec rejects one; string records must use dmhub.serverTimeMilliseconds.
function ServerTimestamp() return placeholder end
local rawEncode = encode
encode = function(v)
    local function scan(x)
        if x == placeholder then error("ServerTimestamp() placeholder inside a JSON-encoded record") end
        if type(x) == "table" then for _,y in pairs(x) do scan(y) end end
    end
    scan(v)
    return rawEncode(v)
end
dmhub.ToJson = encode
setmetatable(dmhub, {__index = function(_, k) if k == "serverTimeMilliseconds" then return now*1000 end end})
function TimestampAgeInSeconds(t) if type(t) ~= "number" then return 0 end return now-t/1000 end
function EventTimestampAge(t) if type(t) == "number" or t == placeholder then return TimestampAgeInSeconds(t) end end
table.shallow_copy = function(t) local r = {}; for k,v in pairs(t) do r[k]=v end; return r end
string.starts_with = function(s,prefix) return s:sub(1,#prefix)==prefix end
creature = {}
function creature:try_get(k, default) local v=rawget(self,k); if v == nil then return default end; return v end
function creature:get_or_add(k, default) local v=rawget(self,k); if v == nil then self[k]=default; return default end; return v end
local function source(path, first, last)
    --AIReactionTestSources is injected only by the isolated engine harness, like AIReactionTestJSON.
    ---@diagnostic disable-next-line: undefined-global
    local s=AIReactionTestSources and AIReactionTestSources[path]
    if s == nil then local f=assert(io.open(path)); s=f:read("*a"); f:close() end
    local start=assert(s:find(first,1,true)); local finish=assert(s:find(last,start+#first,true))
    return s:sub(start,finish-1)
end
local rules="draw-steel-codex/DMHub Game Rules/Creature.lua"
assert(load(source(rules,"local g_aiActivityReactionExpirySeconds =", "function creature:TriggeredAbilityEnabled")))()
assert(load("local g_aiActivityReactionExpirySeconds = 600\nlocal g_aiReactionDeliverySeconds = 15\n" ..
    source(rules,"function creature:BeginPendingAIActivityReaction", "--How long a trigger prompt stays available")))()
local checks=0
local function check(value, message) assert(value,message); checks=checks+1 end
local function makeClient()
    local p=setmetatable({}, {__index=creature})
    p.token={properties=p, valid=true, playerControlled=true, charid="censor", name="Human Censor"}
    function p.token:ModifyProperties(options) options.execute() end
    p.TriggerEvent=function() end
    return p
end
local host, player, calls
local function reset()
    now=0; dmhub.userid="host"; host=makeClient(); player=makeClient(); calls=0
    player.TriggerEvent=function(_,event,info) calls=calls+1; assert(event=="move" and info.remote) end
end
local function queue()
    dmhub.userid="host"
    host:QueueAIReactionEvent("move", {aiActivityId="activity", subject="charid:trapper"}, "player", {"Judgment"})
    return "event-" .. serial
end
local function deliver()
    player.aiReactionRequests=clone(host.aiReactionRequests)
    dmhub.userid="player"; player:PumpAIReactionEvents(); dmhub.userid="host"
end
local function acknowledge()
    host.aiReactionReceipts=clone(player.aiReactionReceipts)
    host.pendingAIActivityReactions=clone(player.pendingAIActivityReactions)
    host.availableTriggers=clone(player.availableTriggers)
end
--An ineligible Judgment still gets an evaluation acknowledgment, with no prompt.
reset(); local id=queue()
check(host:GetAIActivityReactionStatus("activity")==1,"host waits for evaluation")
deliver(); acknowledge()
check(calls==1 and host:GetAIActivityReactionStatus("activity")==0,"no legal reaction releases wait")
deliver(); check(calls==1,"duplicate delivery cannot execute again")
--Lost request: retries preserve the ID, original deadline and full payload.
reset(); id=queue(); host.aiReactionRequests={}; now=3
host:GetAIActivityReactionStatus("activity")
local repaired=decode(host.aiReactionRequests[id]).result
check(repaired.id==id and repaired.attempt==2 and repaired.timestamp==0,"retry repairs complete envelope")
deliver(); acknowledge(); check(calls==1,"repaired request evaluated once")
--Lost acknowledgment, including after player Lua reload, cannot replay evaluation.
reset(); id=queue(); deliver(); now=3
host:GetAIActivityReactionStatus("activity"); deliver(); acknowledge()
check(calls==1,"lost acknowledgment retry deduplicated")
player._tmp_aiReactionReceipts=nil; deliver(); check(calls==1,"persistent receipt survives reload")
player.aiReactionReceipts={}; now=6; deliver(); acknowledge()
check(host:GetAIActivityReactionStatus("activity")==0 and calls==1,"local receipt repairs lost shared acknowledgment")
--An interrupted evaluating claim is never replayed, even after a reload.
reset(); id=queue()
player.aiReactionReceipts={[id]=encode{id=id,activityId="activity",timestamp=0,state="evaluating"}}
deliver(); acknowledge(); now=15
local _,_,err=host:GetAIActivityReactionStatus("activity")
check(calls==0 and err:find("interrupted"),"ambiguous claim pauses without replay")
--No recipient and late delivery: fail promptly and never execute stale movement.
reset(); queue(); now=15
_,_,err=host:GetAIActivityReactionStatus("activity")
check(err:find("acknowledgment"),"missing client times out after 15 seconds")
now=16; deliver(); acknowledge()
check(calls==0,"late movement event cannot produce a delayed reaction")
_,_,err=host:GetAIActivityReactionStatus("activity")
check(err:find("deadline"),"late rejection acknowledged")
--A malformed head does not block unrelated valid events or steal another user's.
reset()
player.triggeredEvents={{info={path={}}}, {userid="other",eventName="move",timestamp=0},
    {userid="player",eventName="move",timestamp=0,info={}}}
dmhub.userid="player"; player:PumpTriggeredEvents()
check(calls==1 and player.triggeredEvents[1]==nil and player.triggeredEvents[3]==nil
    and player.triggeredEvents[2].userid=="other","legacy queue processed per recipient and record")
--A queue missing its first event is still read.
reset()
player.triggeredEvents={[2]={userid="player",eventName="move",timestamp=0,info={}}}
dmhub.userid="player"; player:PumpTriggeredEvents()
check(calls==1 and player.triggeredEvents[2]==nil,"sparse legacy queue drained")
--Only the handled event is deleted. Other players' events and the version key stay.
reset()
local guidQueue={version=2, a={userid="player",eventName="move",timestamp=0,info={}},
    b={userid="other",eventName="move",timestamp=0}}
player.triggeredEvents=guidQueue
dmhub.userid="player"; player:PumpTriggeredEvents()
check(calls==1 and player.triggeredEvents==guidQueue and guidQueue.version==2 and guidQueue.a==nil and guidQueue.b~=nil,
    "guid queue: handled key deleted, others and version kept")
--A damaged new envelope is restored on retry; evaluation exceptions are terminal.
reset(); id=queue(); host.aiReactionRequests[id]="broken"
deliver(); check(calls==0,"malformed envelope not executed")
now=3; host:GetAIActivityReactionStatus("activity"); deliver(); acknowledge()
check(calls==1,"malformed envelope restored from host outbox")
reset(); queue(); player.TriggerEvent=function() calls=calls+1; error("injected evaluation failure") end
deliver(); acknowledge(); deliver()
_,_,err=host:GetAIActivityReactionStatus("activity")
check(calls==1 and err:find("injected"),"evaluation errors are reported and never retried")
--A trigger evaluated on the host's own client writes the marker locally, so
--the host reads its own unresolved ServerTimestamp() placeholder until the
--server echoes the number. That is a live marker, never an expired one.
reset()
host:BeginPendingAIActivityReaction("activity","local-prompt","Hero Death")
host.availableTriggers={["local-prompt"]={}}
check(host.pendingAIActivityReactions["local-prompt"].timestamp==placeholder,"writer holds the placeholder before echo")
local n,description,failure=host:GetAIActivityReactionStatus("activity")
check(failure==nil and n==1 and description:find("answer Hero Death"),"unresolved local marker counts as pending, not expired")
check(host:CountPendingAIActivityReactions("activity")==1,"unresolved local marker is counted")
now=20
_,_,failure=host:GetAIActivityReactionStatus("activity")
check(failure==nil,"unresolved local marker never trips the delivery deadline")
host:CompletePendingAIActivityReaction("activity","local-prompt")
check(host:CountPendingAIActivityReactions("activity")==0,"local completion also holds the placeholder and is terminal")
--Damaged marker timestamps still fail loudly instead of hanging the AI.
reset(); host.pendingAIActivityReactions={junk={activityId="activity",timestamp="garbage",state="awaiting_choice"}}
_,_,failure=host:GetAIActivityReactionStatus("activity")
check(failure and failure:find("could not be confirmed"),"junk marker timestamp is reported")
--Actual prompts can wait longer than the delivery timeout, then remain pending
--after acceptance until the cast's completion callback arrives.
reset(); queue()
player.TriggerEvent=function(self)
    calls=calls+1
    self:BeginPendingAIActivityReaction("activity","prompt","Judgment")
    self.availableTriggers={prompt={}}
end
deliver(); acknowledge(); now=60
local n,description,failure=host:GetAIActivityReactionStatus("activity")
check(n==1 and not failure and description:find("answer Judgment"),"real prompt has no short delivery timeout")
player:SetAIActivityReactionResolving("activity","prompt"); player.availableTriggers={}; acknowledge()
n,description,failure=host:GetAIActivityReactionStatus("activity")
check(n==1 and not failure and description:find("finish"),"accepted reaction waits for cast")
player:CompletePendingAIActivityReaction("activity","prompt"); acknowledge()
check(host:GetAIActivityReactionStatus("activity")==0,"finish callback releases barrier")
check(host.pendingAIActivityReactions.prompt.state=="completed","completed reaction retains tombstone")
player:SetAIActivityReactionResolving("activity","prompt"); acknowledge()
check(host:GetAIActivityReactionStatus("activity")==0,"late resolving call cannot reopen completed reaction")
--The exact old orphan shape now reports a failure instead of silently expiring.
reset(); host.pendingAIActivityReactions={orphan={activityId="activity",timestamp=0}}; now=15
_,_,err=host:GetAIActivityReactionStatus("activity")
check(err:find("no matching"),"orphan marker produces actionable failure")
--Starting another reaction must not garbage-collect unresolved old work.
now=601; host:BeginPendingAIActivityReaction("other-activity","new-prompt","Other")
check(host.pendingAIActivityReactions.orphan~=nil,"unresolved marker retained for explicit recovery")
_,_,err=host:GetAIActivityReactionStatus("activity")
check(err:find("completion"),"expired unresolved reaction fails instead of releasing barrier")
--Bad delivery metadata must report a failure, never throw into turn recovery.
reset(); id=queue(); host._tmp_aiReactionOutbox=nil
host.aiReactionRequests[id]=encode{id=id,activityId="activity"}
_,_,err=host:GetAIActivityReactionStatus("activity")
check(err:find("malformed"),"malformed metadata yields failure")
reset(); host.pendingAIActivityReactions={orphan={activityId="activity",timestamp=0}}; now=15
--Production movement wait must stop AI and leave movement execution unfinished.
local modalMessage
gui={ModalMessage=function(args) modalMessage=args.message end}
MonsterAI={active=true, IsAIRunning=function() return true end, StopAI=function() MonsterAI.active=false end}
function MonsterAI:LogDecision() end
function MonsterAI:CountPendingMinionDeathConfirmations() return 0 end
--The "AI is waiting on a player" notice replicates through a shared
--document and is shown by the tip banner; neither is under test here.
MonsterAI.SetWaiting=function() end
MonsterAI.ClearWaiting=function() end
dmhub.allTokens={host.token}
local aiSource="draw-steel-codex/Monster AI/MonsterAI.lua"
--The AI profiler's file locals are no-ops here.
local function profNoop() end
ProfBegin, ProfEnd, ProfCount, ProfPhaseBegin, ProfPhaseEnd, ProfRequestReport = profNoop, profNoop, profNoop, profNoop, profNoop, profNoop
assert(load(source(aiSource,"function MonsterAI:CountPendingActivityReactions", "--Count squad deaths")))()
assert(load("local mod={}\n" .. source(aiSource,"function MonsterAI:WaitForMovementActivity", "function MonsterAI:MoveToken")))()
local ai=setmetatable({}, {__index=MonsterAI})
local completed=ai:WaitForMovementActivity({valid=true,isMoving=false},"activity")
check(not completed and not MonsterAI.active and MonsterAI.reactionFailure:find("Human Censor"),"orphan stops AI with token-specific explanation")
check(modalMessage==MonsterAI.reactionFailure,"failure visible without open AI panel")
--A failed wait propagates through the real movement executor's abort flag.
assert(load(source(aiSource,"function MonsterAI:MoveToken", "function MonsterAI:ExecuteWithTheoreticalMovementLoc")))()
function MonsterAI:GetMovementToken(t) return t end
function MonsterAI:MovementLocOverlapsCreature() return false end
MonsterAI.LocLogName=tostring; MonsterAI.TokenLogName=function(t) return t.name end
local mover={valid=true,name="Trapper",charid="trapper",loc="origin",properties=setmetatable({}, {__index=creature})}
function mover:Move()
    host.pendingAIActivityReactions={orphan={activityId=creature.GetTokenAIActivity(self.charid),timestamp=0}}
    return {}
end
MonsterAI.active=true
local ok=pcall(ai.MoveToken,ai,mover,"destination",{})
check(not ok and ai._tmp_abortTurn~=nil,"movement failure sets turn abort before unwinding")
--Exercise the outer turn boundary as well: cleanup runs, but initiative cannot
--advance when movement was interrupted by an unconfirmed player reaction.
assert(load("local OrderMountedRidersFirst=function(t) return t end\nlocal RunYieldingFunction=pcall\n" ..
    source(aiSource,"function MonsterAI:PlayTurnCoroutine", "local function FindAbilityByName")))()
assert(load("local RunYieldingFunction=pcall\n" ..
    source(aiSource,"function MonsterAI:PlayTurnSafely", "function MonsterAI:PlayTurnCoroutine")))()
table.keys=function(t) local r={}; for k in pairs(t) do r[#r+1]=k end; return r end
table.values=function(t) local r={}; for _,v in pairs(t) do r[#r+1]=v end; return r end
local advanced,cleaned=0,0
GameHud={instance={NextInitiative=function() advanced=advanced+1 end}}
dmhub.initiativeQueue={round=2,CurrentInitiativeId=function() return "turn" end}
InitiativeQueue={GetTokensForInitiativeId=function() return {mover} end}
MonsterAI.TokenIsLiveCombatant=function(t) return t.valid end
MonsterAI.TargetsLogName=function() return "Trapper" end
MonsterAI.AbilitiesLogName=function() return "Knockback" end
MonsterAI.try_get=creature.try_get
MonsterAI.Analysis=function() return {} end
MonsterAI.SetLogContext=function() end
MonsterAI.HandleMaliceAbilityStartOfTurn=function() end
MonsterAI.FocusCameraOnActor=function() end
MonsterAI.BeginTokenControl=function() return {} end
MonsterAI.EndTokenControl=function() cleaned=cleaned+1 end
MonsterAI.SetupCombatants=function(self) self.allyTokens={}; self.enemyTokens={} end
MonsterAI.CalculateRemainingMovementPaths=function() return {} end
MonsterAI.WaitForAbilityIdle=function() return true end
MonsterAI.FindAndExecuteMove=function(self) return self:MoveToken(mover,"destination",{}) end
ai.log={}; MonsterAI.active=true
local actorFailure
MonsterAI.LogDecision=function(_,event,fields) if event=="ACTOR ERROR" then actorFailure=fields.reason end end
ok=ai:PlayTurnSafely("turn")
check(ok and cleaned==1 and advanced==0 and ai._tmp_abortTurn~=nil and actorFailure:find("no matching"),
    "turn cleanup preserves current initiative on delivery failure")
print("AI reaction delivery: " .. checks .. " checks passed")
